-- Migration 0020: Trade item state machine (AVAILABLE → RESERVED → TRADED)
--
-- Adds a trade_status column to user_inventory that tracks each sticker row's
-- trade lifecycle. A BEFORE UPDATE trigger enforces valid transitions:
--   AVAILABLE → RESERVED  (lock for trade)
--   RESERVED  → AVAILABLE (release lock)
--   RESERVED  → TRADED    (trade executed)
--   TRADED    → AVAILABLE (post-trade reset for remaining copies)
--   AVAILABLE → TRADED    is BLOCKED (must reserve first)
--
-- Also updates lock_inventory_for_trade(), release_inventory_locks(), and
-- execute_trade() RPCs to maintain the new column.

-- 1. Enum type for trade item status
CREATE TYPE trade_item_status AS ENUM ('AVAILABLE', 'RESERVED', 'TRADED');

-- 2. Add column with default (all existing rows become AVAILABLE)
ALTER TABLE user_inventory
  ADD COLUMN trade_status trade_item_status NOT NULL DEFAULT 'AVAILABLE';

-- 3. CHECK constraint (documents intent; enum already restricts values)
ALTER TABLE user_inventory
  ADD CONSTRAINT chk_trade_status_valid
  CHECK (trade_status IN ('AVAILABLE', 'RESERVED', 'TRADED'));

-- 4. Partial index for lock queries: find DUPLICATE + AVAILABLE stickers fast
CREATE INDEX idx_user_inventory_trade_status
  ON user_inventory (user_id, status, trade_status)
  WHERE status = 'DUPLICATE' AND trade_status = 'AVAILABLE';

-- 5. Trigger: enforce valid state transitions
CREATE OR REPLACE FUNCTION enforce_trade_status_transition()
RETURNS trigger AS $$
BEGIN
  -- Allow no-ops (same status → same status)
  IF OLD.trade_status = NEW.trade_status THEN
    RETURN NEW;
  END IF;

  -- Block AVAILABLE → TRADED (must reserve first)
  IF OLD.trade_status = 'AVAILABLE' AND NEW.trade_status = 'TRADED' THEN
    RAISE EXCEPTION 'Invalid trade status transition: AVAILABLE → TRADED. Sticker must be RESERVED before trading.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- All other transitions are valid:
  --   AVAILABLE → RESERVED  (lock)
  --   RESERVED  → AVAILABLE (release)
  --   RESERVED  → TRADED    (trade execute)
  --   TRADED    → AVAILABLE (post-trade reset)
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_enforce_trade_status
  BEFORE UPDATE ON user_inventory
  FOR EACH ROW
  WHEN (OLD.trade_status IS DISTINCT FROM NEW.trade_status)
  EXECUTE FUNCTION enforce_trade_status_transition();

-- =============================================================================
-- 6. Updated RPC: lock_inventory_for_trade(p_match_id uuid)
--
-- Changes from migration 0018:
--   - Filters DUPLICATE stickers by trade_status = 'AVAILABLE'
--   - Sets trade_status = 'RESERVED' on locked stickers
--   - Returns STICKERS_NOT_AVAILABLE when all duplicates are already reserved
-- =============================================================================
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

  -- Gather caller's DUPLICATE sticker IDs that are AVAILABLE, with row-level lock
  SELECT array_agg(sticker_id ORDER BY sticker_id)
    INTO v_duplicate_ids
    FROM user_inventory
   WHERE user_id = v_caller_id
     AND status = 'DUPLICATE'
     AND trade_status = 'AVAILABLE'
     FOR UPDATE;

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

-- Permissions unchanged: authenticated only
REVOKE ALL ON FUNCTION lock_inventory_for_trade(uuid) FROM public;
REVOKE ALL ON FUNCTION lock_inventory_for_trade(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION lock_inventory_for_trade(uuid) TO authenticated;

-- =============================================================================
-- 7. Updated RPC: release_inventory_locks(p_match_id, p_reason)
--
-- Changes from migration 0018:
--   - Captures sticker_ids from released lock rows
--   - Resets trade_status to AVAILABLE on those stickers
-- =============================================================================
CREATE OR REPLACE FUNCTION release_inventory_locks(
  p_match_id uuid,
  p_reason   lock_release_reason
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_released_count int;
  v_lock_record    record;
BEGIN
  -- Release active locks and reset trade_status for each released lock's stickers
  FOR v_lock_record IN
    UPDATE inventory_locks
       SET released_at = now(),
           release_reason = p_reason
     WHERE match_id = p_match_id
       AND released_at IS NULL
    RETURNING user_id, sticker_ids
  LOOP
    -- Reset trade_status on released stickers (RESERVED/TRADED → AVAILABLE)
    UPDATE user_inventory
       SET trade_status = 'AVAILABLE'
     WHERE user_id = v_lock_record.user_id
       AND sticker_id = ANY(v_lock_record.sticker_ids)
       AND trade_status IN ('RESERVED', 'TRADED');
  END LOOP;

  GET DIAGNOSTICS v_released_count = ROW_COUNT;

  RETURN json_build_object(
    'success',        true,
    'released_count', v_released_count
  );
END;
$$;

-- Permissions unchanged: service_role only
REVOKE ALL ON FUNCTION release_inventory_locks(uuid, lock_release_reason) FROM public;
REVOKE ALL ON FUNCTION release_inventory_locks(uuid, lock_release_reason) FROM anon;
REVOKE ALL ON FUNCTION release_inventory_locks(uuid, lock_release_reason) FROM authenticated;
GRANT EXECUTE ON FUNCTION release_inventory_locks(uuid, lock_release_reason) TO service_role;

-- =============================================================================
-- 8. Updated RPC: execute_trade()
--
-- Changes from migration 0019:
--   - Adds trade_status = 'RESERVED' filter to row-level lock
--   - Verifies all offered stickers are RESERVED (STICKERS_NOT_RESERVED error)
--   - Sets trade_status = 'TRADED' on sender rows during transfer
--   - Resets trade_status = 'AVAILABLE' on sender rows that remain DUPLICATE
--   - Recipient upsert sets trade_status = 'AVAILABLE'
--   - release_inventory_locks at end handles final reset for any remaining
-- =============================================================================
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
  v_existing_trade_id   uuid;
  v_sticker             int;
  v_not_reserved_count  int;
BEGIN
  -- 0. Idempotency check: if trade already recorded, return existing trade_id
  SELECT trade_id INTO v_existing_trade_id
    FROM trade_audit_log
   WHERE idempotency_key = p_idempotency_key;

  IF v_existing_trade_id IS NOT NULL THEN
    RETURN json_build_object(
      'success',            true,
      'trade_id',           v_existing_trade_id,
      'already_completed',  true
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
    -- Decrement/downgrade sender and mark as TRADED (RESERVED → TRADED)
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

    -- Upsert recipient (new stickers are AVAILABLE)
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
    -- Decrement/downgrade sender and mark as TRADED (RESERVED → TRADED)
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

    -- Upsert recipient (new stickers are AVAILABLE)
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

  -- 8. Record trade in audit log (reuses existing record_trade function)
  v_trade_id := record_trade(
    p_initiator_id,
    v_responder_id,
    p_initiator_sticker_ids,
    p_responder_sticker_ids,
    'COMPLETED'::trade_status,
    p_idempotency_key
  );

  -- 9. Update match status to COMPLETED
  UPDATE matches SET status = 'COMPLETED' WHERE id = p_match_id;

  -- 10. Release inventory locks for both participants
  --     (also resets trade_status TRADED → AVAILABLE for remaining copies)
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

-- Permissions unchanged: service_role only
REVOKE ALL ON FUNCTION execute_trade(uuid, uuid, int[], int[], uuid) FROM public;
REVOKE ALL ON FUNCTION execute_trade(uuid, uuid, int[], int[], uuid) FROM anon;
REVOKE ALL ON FUNCTION execute_trade(uuid, uuid, int[], int[], uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION execute_trade(uuid, uuid, int[], int[], uuid) TO service_role;
