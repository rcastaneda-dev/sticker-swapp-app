-- Migration 0019: Atomic trade execution
--
-- Executes a sticker trade atomically: verify locks → transfer stickers →
-- record audit → update match status → release locks. Idempotent by
-- idempotency_key. Called by the Go service via service_role connection.

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

  -- 5. Row-level lock on affected inventory rows
  PERFORM 1 FROM user_inventory
   WHERE user_id IN (p_initiator_id, v_responder_id)
     AND sticker_id = ANY(p_initiator_sticker_ids || p_responder_sticker_ids)
     FOR UPDATE;

  -- 6. Transfer stickers: initiator → responder
  FOREACH v_sticker IN ARRAY p_initiator_sticker_ids
  LOOP
    -- Decrement/downgrade sender
    UPDATE user_inventory
       SET status   = CASE WHEN quantity > 1 THEN 'DUPLICATE'::inventory_status
                                              ELSE 'OWNED'::inventory_status END,
           quantity = CASE WHEN quantity > 1 THEN quantity - 1 ELSE 1 END,
           updated_at = now()
     WHERE user_id = p_initiator_id
       AND sticker_id = v_sticker
       AND status = 'DUPLICATE';

    -- Upsert recipient
    INSERT INTO user_inventory (user_id, sticker_id, status, quantity)
    VALUES (v_responder_id, v_sticker, 'OWNED', 1)
    ON CONFLICT (user_id, sticker_id) DO UPDATE
      SET status   = CASE
            WHEN user_inventory.status IN ('OWNED', 'DUPLICATE')
              THEN 'DUPLICATE'::inventory_status
            ELSE 'OWNED'::inventory_status
          END,
          quantity = CASE
            WHEN user_inventory.status IN ('OWNED', 'DUPLICATE')
              THEN user_inventory.quantity + 1
            ELSE 1
          END,
          updated_at = now();
  END LOOP;

  -- 7. Transfer stickers: responder → initiator
  FOREACH v_sticker IN ARRAY p_responder_sticker_ids
  LOOP
    -- Decrement/downgrade sender
    UPDATE user_inventory
       SET status   = CASE WHEN quantity > 1 THEN 'DUPLICATE'::inventory_status
                                              ELSE 'OWNED'::inventory_status END,
           quantity = CASE WHEN quantity > 1 THEN quantity - 1 ELSE 1 END,
           updated_at = now()
     WHERE user_id = v_responder_id
       AND sticker_id = v_sticker
       AND status = 'DUPLICATE';

    -- Upsert recipient
    INSERT INTO user_inventory (user_id, sticker_id, status, quantity)
    VALUES (p_initiator_id, v_sticker, 'OWNED', 1)
    ON CONFLICT (user_id, sticker_id) DO UPDATE
      SET status   = CASE
            WHEN user_inventory.status IN ('OWNED', 'DUPLICATE')
              THEN 'DUPLICATE'::inventory_status
            ELSE 'OWNED'::inventory_status
          END,
          quantity = CASE
            WHEN user_inventory.status IN ('OWNED', 'DUPLICATE')
              THEN user_inventory.quantity + 1
            ELSE 1
          END,
          updated_at = now();
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

-- Permissions: service_role only (Go backend calls this)
REVOKE ALL ON FUNCTION execute_trade(uuid, uuid, int[], int[], uuid) FROM public;
REVOKE ALL ON FUNCTION execute_trade(uuid, uuid, int[], int[], uuid) FROM anon;
REVOKE ALL ON FUNCTION execute_trade(uuid, uuid, int[], int[], uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION execute_trade(uuid, uuid, int[], int[], uuid) TO service_role;
