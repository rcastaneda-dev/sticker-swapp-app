-- 0026_fix_lock_inventory_aggregate_for_update.sql
-- Fixes: "FOR UPDATE is not allowed with aggregate functions" in lock_inventory_for_trade()
--
-- PostgreSQL does not allow FOR UPDATE combined with aggregate functions (array_agg).
-- The fix separates the row-level lock (PERFORM ... FOR UPDATE) from the aggregation
-- (SELECT array_agg(...) without FOR UPDATE), executed in sequence within the same
-- transaction so the locks are held until commit.

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

  -- Mark any expired locks for this user+match as released
  UPDATE inventory_locks
     SET released_at = now(), release_reason = 'EXPIRED'
   WHERE match_id = p_match_id
     AND user_id = v_caller_id
     AND released_at IS NULL
     AND expires_at <= now();

  -- Reset trade_status on stickers from expired locks
  UPDATE user_inventory
     SET trade_status = 'AVAILABLE'
   WHERE user_id = v_caller_id
     AND trade_status = 'RESERVED';

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

  -- Acquire row-level locks on caller's AVAILABLE DUPLICATE stickers (separate from aggregation)
  PERFORM 1
    FROM user_inventory
   WHERE user_id = v_caller_id
     AND status = 'DUPLICATE'
     AND trade_status = 'AVAILABLE'
     FOR UPDATE;

  -- Now aggregate the locked sticker IDs (no FOR UPDATE here — rows are already locked above)
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
