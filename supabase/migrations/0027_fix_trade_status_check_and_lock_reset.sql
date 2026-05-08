-- 0027_fix_trade_status_check_and_lock_reset.sql
--
-- Fixes two bugs:
--
-- 1. execute_trade(): STICKERS_NOT_RESERVED check was too broad — it checked
--    both users against the COMBINED sticker array. If the responder already
--    has a sticker that the initiator is offering (as OWNED/AVAILABLE), the
--    check would spuriously fail. Fix: check each user against only THEIR
--    offered stickers.
--
-- 2. lock_inventory_for_trade(): unconditionally reset ALL of the caller's
--    RESERVED stickers to AVAILABLE (lines meant to handle expired locks).
--    This destroyed RESERVED state from other active locks. Fix: only reset
--    stickers that belong to locks we just marked as expired.

-- ============================================================
-- FIX 1: lock_inventory_for_trade — scoped expired-lock reset
-- ============================================================

CREATE OR REPLACE FUNCTION lock_inventory_for_trade(p_match_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id       uuid;
  v_match_status    match_status;
  v_is_participant  boolean;
  v_existing        record;
  v_duplicate_ids   int[];
  v_conflict_ids    int[];
  v_conflict_match  uuid;
  v_new_expires     timestamptz;
  v_has_any_dupes   boolean;
  v_expired_stickers int[];
BEGIN
  v_caller_id := auth.uid();

  IF v_caller_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  -- Verify match exists and caller is a participant
  SELECT status,
         (v_caller_id IN (user1_id, user2_id))
    INTO v_match_status, v_is_participant
    FROM matches
   WHERE id = p_match_id;

  IF v_match_status IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'MATCH_NOT_FOUND');
  END IF;

  IF NOT v_is_participant THEN
    RETURN json_build_object('success', false, 'error', 'NOT_PARTICIPANT');
  END IF;

  IF v_match_status <> 'PENDING' THEN
    RETURN json_build_object('success', false, 'error', 'MATCH_NOT_PENDING');
  END IF;

  -- Serialize concurrent lock attempts on the same match
  PERFORM pg_advisory_xact_lock(hashtext(p_match_id::text));

  -- Collect sticker IDs from expired locks BEFORE marking them released
  SELECT array_agg(s.sid)
    INTO v_expired_stickers
    FROM inventory_locks il,
         LATERAL unnest(il.sticker_ids) AS s(sid)
   WHERE il.match_id = p_match_id
     AND il.user_id = v_caller_id
     AND il.released_at IS NULL
     AND il.expires_at <= now();

  -- Mark any expired locks for this user+match as released
  UPDATE inventory_locks
     SET released_at = now(), release_reason = 'EXPIRED'
   WHERE match_id = p_match_id
     AND user_id = v_caller_id
     AND released_at IS NULL
     AND expires_at <= now();

  -- Reset trade_status ONLY on stickers from the just-expired locks
  IF v_expired_stickers IS NOT NULL AND array_length(v_expired_stickers, 1) > 0 THEN
    UPDATE user_inventory
       SET trade_status = 'AVAILABLE'
     WHERE user_id = v_caller_id
       AND sticker_id = ANY(v_expired_stickers)
       AND trade_status = 'RESERVED';
  END IF;

  -- Check for existing active lock (extend if found)
  SELECT * INTO v_existing
    FROM inventory_locks
   WHERE match_id = p_match_id
     AND user_id = v_caller_id
     AND released_at IS NULL
     AND expires_at > now();

  IF v_existing IS NOT NULL THEN
    v_new_expires := now() + interval '15 minutes';
    UPDATE inventory_locks
       SET expires_at = v_new_expires
     WHERE id = v_existing.id;

    RETURN json_build_object(
      'success',     true,
      'sticker_ids', v_existing.sticker_ids,
      'lock_count',  array_length(v_existing.sticker_ids, 1),
      'expires_at',  v_new_expires,
      'extended',    true
    );
  END IF;

  -- Acquire row-level locks on caller's AVAILABLE DUPLICATE stickers
  PERFORM 1
    FROM user_inventory
   WHERE user_id = v_caller_id
     AND status = 'DUPLICATE'
     AND trade_status = 'AVAILABLE'
     FOR UPDATE;

  -- Aggregate the locked sticker IDs (rows already locked above)
  SELECT array_agg(sticker_id ORDER BY sticker_id)
    INTO v_duplicate_ids
    FROM user_inventory
   WHERE user_id = v_caller_id
     AND status = 'DUPLICATE'
     AND trade_status = 'AVAILABLE';

  -- Check if user has duplicates at all (to distinguish NO_DUPLICATES vs NOT_AVAILABLE)
  IF v_duplicate_ids IS NULL OR array_length(v_duplicate_ids, 1) IS NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM user_inventory
       WHERE user_id = v_caller_id AND status = 'DUPLICATE'
    ) INTO v_has_any_dupes;

    IF v_has_any_dupes THEN
      RETURN json_build_object('success', false, 'error', 'STICKERS_NOT_AVAILABLE');
    ELSE
      RETURN json_build_object('success', false, 'error', 'NO_DUPLICATES');
    END IF;
  END IF;

  -- Check for conflicts with other active locks
  SELECT il.match_id,
         array_agg(s.sid ORDER BY s.sid)
    INTO v_conflict_match, v_conflict_ids
    FROM inventory_locks il,
         LATERAL unnest(il.sticker_ids) AS s(sid)
   WHERE il.user_id = v_caller_id
     AND il.released_at IS NULL
     AND il.expires_at > now()
     AND il.match_id <> p_match_id
     AND s.sid = ANY(v_duplicate_ids)
   GROUP BY il.match_id
   LIMIT 1;

  IF v_conflict_ids IS NOT NULL AND array_length(v_conflict_ids, 1) > 0 THEN
    RETURN json_build_object(
      'success',                false,
      'error',                  'STICKERS_ALREADY_LOCKED',
      'conflicting_sticker_ids', v_conflict_ids,
      'conflicting_match_id',   v_conflict_match
    );
  END IF;

  -- Create or replace the lock row
  v_new_expires := now() + interval '15 minutes';

  INSERT INTO inventory_locks (match_id, user_id, sticker_ids, expires_at)
  VALUES (p_match_id, v_caller_id, v_duplicate_ids, v_new_expires)
  ON CONFLICT (match_id, user_id) DO UPDATE
    SET sticker_ids    = EXCLUDED.sticker_ids,
        locked_at      = now(),
        expires_at     = EXCLUDED.expires_at,
        released_at    = NULL,
        release_reason = NULL;

  -- Set trade_status = RESERVED on locked stickers (AVAILABLE → RESERVED)
  UPDATE user_inventory
     SET trade_status = 'RESERVED'
   WHERE user_id = v_caller_id
     AND sticker_id = ANY(v_duplicate_ids)
     AND trade_status = 'AVAILABLE';

  RETURN json_build_object(
    'success',     true,
    'sticker_ids', v_duplicate_ids,
    'lock_count',  array_length(v_duplicate_ids, 1),
    'expires_at',  v_new_expires,
    'extended',    false
  );
END;
$$;

-- Permissions unchanged
REVOKE ALL ON FUNCTION lock_inventory_for_trade(uuid) FROM public;
REVOKE ALL ON FUNCTION lock_inventory_for_trade(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION lock_inventory_for_trade(uuid) TO authenticated;

-- ============================================================
-- FIX 2: execute_trade — scoped RESERVED check per user
-- ============================================================

CREATE OR REPLACE FUNCTION execute_trade(
  p_match_id              uuid,
  p_initiator_id          uuid,
  p_initiator_sticker_ids int[],
  p_responder_sticker_ids int[],
  p_idempotency_key       uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_responder_id        uuid;
  v_match_status        match_status;
  v_user1               uuid;
  v_user2               uuid;
  v_is_participant      boolean;
  v_initiator_locked    int[];
  v_responder_locked    int[];
  v_trade_id            uuid;
  v_existing            record;
  v_sticker             int;
  v_not_reserved_count  int;
BEGIN
  -- 0. Idempotency check: if trade already recorded, return full response
  SELECT trade_id, match_id, initiator_id, responder_id,
         initiator_sticker_ids, responder_sticker_ids, status
    INTO v_existing
    FROM trade_audit_log
   WHERE idempotency_key = p_idempotency_key;

  IF v_existing IS NOT NULL THEN
    RETURN json_build_object(
      'success',               true,
      'trade_id',              v_existing.trade_id,
      'match_id',              v_existing.match_id,
      'initiator_id',          v_existing.initiator_id,
      'responder_id',          v_existing.responder_id,
      'initiator_sticker_ids', v_existing.initiator_sticker_ids,
      'responder_sticker_ids', v_existing.responder_sticker_ids,
      'status',                v_existing.status,
      'already_completed',     true
    );
  END IF;

  -- 1. Validate match exists, is PENDING, initiator is a participant
  SELECT user1_id, user2_id, status,
         (p_initiator_id IN (user1_id, user2_id))
    INTO v_user1, v_user2, v_match_status, v_is_participant
    FROM matches
   WHERE id = p_match_id;

  IF v_user1 IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'MATCH_NOT_FOUND');
  END IF;

  IF NOT v_is_participant THEN
    RETURN json_build_object('success', false, 'error', 'NOT_PARTICIPANT');
  END IF;

  IF v_match_status <> 'PENDING' THEN
    RETURN json_build_object('success', false, 'error', 'MATCH_NOT_PENDING');
  END IF;

  -- Determine responder (the other participant)
  v_responder_id := CASE WHEN p_initiator_id = v_user1 THEN v_user2 ELSE v_user1 END;

  -- 2. Serialize concurrent trade attempts on this match
  PERFORM pg_advisory_xact_lock(hashtext(p_match_id::text));

  -- 3. Verify both users have active inventory locks
  SELECT sticker_ids INTO v_initiator_locked
    FROM inventory_locks
   WHERE match_id = p_match_id
     AND user_id = p_initiator_id
     AND released_at IS NULL
     AND expires_at > now();

  IF v_initiator_locked IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NO_ACTIVE_LOCK_INITIATOR');
  END IF;

  SELECT sticker_ids INTO v_responder_locked
    FROM inventory_locks
   WHERE match_id = p_match_id
     AND user_id = v_responder_id
     AND released_at IS NULL
     AND expires_at > now();

  IF v_responder_locked IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NO_ACTIVE_LOCK_RESPONDER');
  END IF;

  -- 4. Verify offered stickers are subsets of locked stickers
  IF NOT (p_initiator_sticker_ids <@ v_initiator_locked) THEN
    RETURN json_build_object('success', false, 'error', 'STICKERS_NOT_IN_LOCK');
  END IF;

  IF NOT (p_responder_sticker_ids <@ v_responder_locked) THEN
    RETURN json_build_object('success', false, 'error', 'STICKERS_NOT_IN_LOCK');
  END IF;

  -- 5. Row-level lock on affected inventory rows (must be RESERVED)
  PERFORM 1 FROM user_inventory
   WHERE (  (user_id = p_initiator_id AND sticker_id = ANY(p_initiator_sticker_ids))
         OR (user_id = v_responder_id AND sticker_id = ANY(p_responder_sticker_ids))
         )
     AND trade_status = 'RESERVED'
     FOR UPDATE;

  -- Verify all offered stickers are actually RESERVED (scoped per user)
  SELECT count(*) INTO v_not_reserved_count
    FROM user_inventory
   WHERE (  (user_id = p_initiator_id AND sticker_id = ANY(p_initiator_sticker_ids))
         OR (user_id = v_responder_id AND sticker_id = ANY(p_responder_sticker_ids))
         )
     AND trade_status <> 'RESERVED';

  IF v_not_reserved_count > 0 THEN
    RETURN json_build_object('success', false, 'error', 'STICKERS_NOT_RESERVED');
  END IF;

  -- 6. Transfer stickers: initiator → responder
  FOREACH v_sticker IN ARRAY p_initiator_sticker_ids
  LOOP
    UPDATE user_inventory
       SET status       = CASE WHEN quantity > 1 THEN 'DUPLICATE'::inventory_status
                                                 ELSE 'OWNED'::inventory_status END,
           quantity     = CASE WHEN quantity > 1 THEN quantity - 1 ELSE 1 END,
           trade_status = 'TRADED',
           updated_at   = now()
     WHERE user_id = p_initiator_id
       AND sticker_id = v_sticker
       AND status = 'DUPLICATE'
       AND trade_status = 'RESERVED';

    INSERT INTO user_inventory (user_id, sticker_id, status, quantity, trade_status)
    VALUES (v_responder_id, v_sticker, 'OWNED', 1, 'AVAILABLE')
    ON CONFLICT (user_id, sticker_id) DO UPDATE
      SET status       = CASE
            WHEN user_inventory.status IN ('OWNED', 'DUPLICATE')
              THEN 'DUPLICATE'::inventory_status
            ELSE 'OWNED'::inventory_status
          END,
          quantity     = CASE
            WHEN user_inventory.status IN ('OWNED', 'DUPLICATE')
              THEN user_inventory.quantity + 1
            ELSE 1
          END,
          trade_status = 'AVAILABLE',
          updated_at   = now();
  END LOOP;

  -- 7. Transfer stickers: responder ��� initiator
  FOREACH v_sticker IN ARRAY p_responder_sticker_ids
  LOOP
    UPDATE user_inventory
       SET status       = CASE WHEN quantity > 1 THEN 'DUPLICATE'::inventory_status
                                                 ELSE 'OWNED'::inventory_status END,
           quantity     = CASE WHEN quantity > 1 THEN quantity - 1 ELSE 1 END,
           trade_status = 'TRADED',
           updated_at   = now()
     WHERE user_id = v_responder_id
       AND sticker_id = v_sticker
       AND status = 'DUPLICATE'
       AND trade_status = 'RESERVED';

    INSERT INTO user_inventory (user_id, sticker_id, status, quantity, trade_status)
    VALUES (p_initiator_id, v_sticker, 'OWNED', 1, 'AVAILABLE')
    ON CONFLICT (user_id, sticker_id) DO UPDATE
      SET status       = CASE
            WHEN user_inventory.status IN ('OWNED', 'DUPLICATE')
              THEN 'DUPLICATE'::inventory_status
            ELSE 'OWNED'::inventory_status
          END,
          quantity     = CASE
            WHEN user_inventory.status IN ('OWNED', 'DUPLICATE')
              THEN user_inventory.quantity + 1
            ELSE 1
          END,
          trade_status = 'AVAILABLE',
          updated_at   = now();
  END LOOP;

  -- 8. Record the trade in audit log
  v_trade_id := record_trade(
    p_initiator_id,
    v_responder_id,
    p_initiator_sticker_ids,
    p_responder_sticker_ids,
    'COMPLETED'::trade_status,
    p_idempotency_key,
    p_match_id
  );

  -- 9. Update match status
  UPDATE matches
     SET status = 'COMPLETED'
   WHERE id = p_match_id;

  -- 10. Release inventory locks
  PERFORM release_inventory_locks(p_match_id, 'TRADE_COMPLETED');

  RETURN json_build_object(
    'success',               true,
    'trade_id',              v_trade_id,
    'match_id',              p_match_id,
    'initiator_id',          p_initiator_id,
    'responder_id',          v_responder_id,
    'initiator_sticker_ids', p_initiator_sticker_ids,
    'responder_sticker_ids', p_responder_sticker_ids,
    'status',                'COMPLETED',
    'already_completed',     false
  );
END;
$$;

-- Permissions: service_role only
REVOKE ALL ON FUNCTION execute_trade(uuid, uuid, int[], int[], uuid) FROM public;
REVOKE ALL ON FUNCTION execute_trade(uuid, uuid, int[], int[], uuid) FROM anon;
REVOKE ALL ON FUNCTION execute_trade(uuid, uuid, int[], int[], uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION execute_trade(uuid, uuid, int[], int[], uuid) TO service_role;
