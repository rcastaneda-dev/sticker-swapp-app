-- Migration 0018: Inventory soft-lock system for trades
--
-- Locks a user's DUPLICATE stickers for a specific match when the chat screen
-- opens. Prevents the same stickers from being offered in multiple concurrent
-- trades. Rows are never deleted — the table is the audit trail.

-- Enum: why a lock was released
CREATE TYPE lock_release_reason AS ENUM (
  'EXPIRED',
  'TRADE_COMPLETED',
  'TRADE_CANCELLED',
  'MANUAL_RELEASE'
);

-- Table: one lock row per user per match
CREATE TABLE inventory_locks (
  id              bigint               GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  match_id        uuid                 NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  user_id         uuid                 NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sticker_ids     int[]                NOT NULL CHECK (array_length(sticker_ids, 1) >= 1),
  locked_at       timestamptz          NOT NULL DEFAULT now(),
  expires_at      timestamptz          NOT NULL,
  released_at     timestamptz,
  release_reason  lock_release_reason,

  UNIQUE (match_id, user_id)
);

-- Indexes
CREATE INDEX idx_inventory_locks_match  ON inventory_locks (match_id);
CREATE INDEX idx_inventory_locks_user   ON inventory_locks (user_id);
CREATE INDEX idx_inventory_locks_active ON inventory_locks (user_id)
  WHERE released_at IS NULL;

-- RLS
ALTER TABLE inventory_locks ENABLE ROW LEVEL SECURITY;

-- Participants can read locks for matches they are in
CREATE POLICY "participants_read_locks"
  ON inventory_locks FOR SELECT
  TO authenticated
  USING (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1 FROM matches
      WHERE matches.id = inventory_locks.match_id
        AND auth.uid() IN (matches.user1_id, matches.user2_id)
    )
  );

-- No INSERT/UPDATE/DELETE policies — all writes go through SECURITY DEFINER RPCs

-- =============================================================================
-- RPC: lock_inventory_for_trade(p_match_id uuid)
--
-- Called by authenticated users (via Go service with set_config).
-- Locks the caller's DUPLICATE stickers for the given match.
-- Uses pg_advisory_xact_lock to serialize concurrent lock attempts on the same
-- match. Uses SELECT FOR UPDATE on user_inventory rows to prevent concurrent
-- inventory mutations during lock acquisition.
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

  -- Gather caller's DUPLICATE sticker IDs with row-level lock
  SELECT array_agg(sticker_id ORDER BY sticker_id)
    INTO v_duplicate_ids
    FROM user_inventory
   WHERE user_id = v_caller_id
     AND status = 'DUPLICATE'
     FOR UPDATE;

  IF v_duplicate_ids IS NULL OR array_length(v_duplicate_ids, 1) IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'NO_DUPLICATES');
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

  RETURN json_build_object(
    'success',     true,
    'sticker_ids', v_duplicate_ids,
    'lock_count',  array_length(v_duplicate_ids, 1),
    'expires_at',  v_new_expires,
    'extended',    false
  );
END;
$$;

-- Permissions: authenticated only
REVOKE ALL ON FUNCTION lock_inventory_for_trade(uuid) FROM public;
REVOKE ALL ON FUNCTION lock_inventory_for_trade(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION lock_inventory_for_trade(uuid) TO authenticated;

-- =============================================================================
-- RPC: release_inventory_locks(p_match_id uuid, p_reason lock_release_reason)
--
-- Called by the Go service (service_role) when a trade completes, is cancelled,
-- or a user manually releases locks. Releases all active locks for both
-- participants of the given match.
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
BEGIN
  UPDATE inventory_locks
     SET released_at = now(),
         release_reason = p_reason
   WHERE match_id = p_match_id
     AND released_at IS NULL;

  GET DIAGNOSTICS v_released_count = ROW_COUNT;

  RETURN json_build_object(
    'success',        true,
    'released_count', v_released_count
  );
END;
$$;

-- Permissions: service_role only
REVOKE ALL ON FUNCTION release_inventory_locks(uuid, lock_release_reason) FROM public;
REVOKE ALL ON FUNCTION release_inventory_locks(uuid, lock_release_reason) FROM anon;
REVOKE ALL ON FUNCTION release_inventory_locks(uuid, lock_release_reason) FROM authenticated;
GRANT EXECUTE ON FUNCTION release_inventory_locks(uuid, lock_release_reason) TO service_role;
