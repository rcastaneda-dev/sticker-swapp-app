-- Migration 0022: Enrich trade idempotency response
--
-- Problem: When execute_trade() detects a duplicate idempotency_key, it
-- returns only {success, trade_id, already_completed}. The client gets a
-- sparse response missing match_id, participant IDs, sticker arrays, and
-- status — breaking the "same key → same response" contract.
--
-- Fix:
--   1. Add match_id to trade_audit_log (needed for full replay response)
--   2. Update record_trade() to accept and store match_id
--   3. Update execute_trade() idempotency check to return the full response

-- 1. Add match_id column (nullable for any existing rows)
ALTER TABLE trade_audit_log
  ADD COLUMN match_id uuid REFERENCES matches(id);

CREATE INDEX idx_trade_audit_match ON trade_audit_log (match_id);

-- 2. Update record_trade() to accept match_id
CREATE OR REPLACE FUNCTION record_trade(
  p_initiator_id         uuid,
  p_responder_id         uuid,
  p_initiator_sticker_ids int[],
  p_responder_sticker_ids int[],
  p_status               trade_status,
  p_idempotency_key      uuid,
  p_match_id             uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_trade_id uuid;
BEGIN
  INSERT INTO trade_audit_log (
    initiator_id,
    responder_id,
    initiator_sticker_ids,
    responder_sticker_ids,
    status,
    idempotency_key,
    match_id
  )
  VALUES (
    p_initiator_id,
    p_responder_id,
    p_initiator_sticker_ids,
    p_responder_sticker_ids,
    p_status,
    p_idempotency_key,
    p_match_id
  )
  ON CONFLICT (idempotency_key) DO NOTHING
  RETURNING trade_id INTO v_trade_id;

  RETURN v_trade_id;
END;
$$;

-- Permissions unchanged
REVOKE EXECUTE ON FUNCTION record_trade FROM public;
REVOKE EXECUTE ON FUNCTION record_trade FROM anon;
REVOKE EXECUTE ON FUNCTION record_trade FROM authenticated;
GRANT EXECUTE ON FUNCTION record_trade TO service_role;

-- 3. Update execute_trade() with enriched idempotency response
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
   WHERE user_id IN (p_initiator_id, v_responder_id)
     AND sticker_id = ANY(p_initiator_sticker_ids || p_responder_sticker_ids)
     AND trade_status = 'RESERVED'
     FOR UPDATE;

  -- Verify all offered stickers are actually RESERVED
  SELECT count(*) INTO v_not_reserved_count
    FROM user_inventory
   WHERE user_id IN (p_initiator_id, v_responder_id)
     AND sticker_id = ANY(p_initiator_sticker_ids || p_responder_sticker_ids)
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
          updated_at   = now();
  END LOOP;

  -- 7. Transfer stickers: responder → initiator
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
          updated_at   = now();
  END LOOP;

  -- 8. Record trade in audit log (now includes match_id)
  v_trade_id := record_trade(
    p_initiator_id,
    v_responder_id,
    p_initiator_sticker_ids,
    p_responder_sticker_ids,
    'COMPLETED'::trade_status,
    p_idempotency_key,
    p_match_id
  );

  -- 9. Update match status to COMPLETED
  UPDATE matches SET status = 'COMPLETED' WHERE id = p_match_id;

  -- 10. Release inventory locks for both participants
  PERFORM release_inventory_locks(p_match_id, 'TRADE_COMPLETED'::lock_release_reason);

  -- 11. Return success
  RETURN json_build_object(
    'success',               true,
    'trade_id',              v_trade_id,
    'match_id',              p_match_id,
    'initiator_id',          p_initiator_id,
    'responder_id',          v_responder_id,
    'initiator_sticker_ids', p_initiator_sticker_ids,
    'responder_sticker_ids', p_responder_sticker_ids,
    'status',                'COMPLETED'
  );
END;
$$;

-- Permissions unchanged
REVOKE ALL ON FUNCTION execute_trade(uuid, uuid, int[], int[], uuid) FROM public;
REVOKE ALL ON FUNCTION execute_trade(uuid, uuid, int[], int[], uuid) FROM anon;
REVOKE ALL ON FUNCTION execute_trade(uuid, uuid, int[], int[], uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION execute_trade(uuid, uuid, int[], int[], uuid) TO service_role;
