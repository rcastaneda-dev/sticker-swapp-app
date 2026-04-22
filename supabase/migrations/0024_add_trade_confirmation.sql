-- Migration 0024: Add trade confirmation columns and RPCs
--
-- Both users in a match must "Mark as Done" to confirm a physical sticker
-- trade occurred. When both confirm, the match status transitions to COMPLETED.

-- ── 1. Add confirmation columns to matches ──────────────────────────────

ALTER TABLE matches
  ADD COLUMN user1_confirmed_at timestamptz,
  ADD COLUMN user2_confirmed_at timestamptz;

COMMENT ON COLUMN matches.user1_confirmed_at IS 'Timestamp when user1 confirmed the trade happened';
COMMENT ON COLUMN matches.user2_confirmed_at IS 'Timestamp when user2 confirmed the trade happened';

-- ── 2. confirm_trade_completion RPC ─────────────────────────────────────

CREATE OR REPLACE FUNCTION confirm_trade_completion(p_match_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_match        RECORD;
  v_caller_id    uuid := auth.uid();
  v_is_user1     boolean;
  v_both_done    boolean;
  v_caller_done  boolean;
  v_other_done   boolean;
  v_status       text;
BEGIN
  -- 1. Auth check
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  -- 2. Fetch match with row lock
  SELECT * INTO v_match
  FROM matches
  WHERE id = p_match_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'MATCH_NOT_FOUND');
  END IF;

  -- 3. Verify caller is participant
  IF v_caller_id NOT IN (v_match.user1_id, v_match.user2_id) THEN
    RETURN json_build_object('success', false, 'error', 'NOT_PARTICIPANT');
  END IF;

  -- 4. Verify match is PENDING
  IF v_match.status <> 'PENDING' THEN
    RETURN json_build_object('success', false, 'error', 'MATCH_NOT_PENDING');
  END IF;

  -- 5. Set caller's confirmation (idempotent via COALESCE)
  v_is_user1 := (v_caller_id = v_match.user1_id);

  IF v_is_user1 THEN
    UPDATE matches
    SET user1_confirmed_at = COALESCE(user1_confirmed_at, now()),
        updated_at = now()
    WHERE id = p_match_id;
  ELSE
    UPDATE matches
    SET user2_confirmed_at = COALESCE(user2_confirmed_at, now()),
        updated_at = now()
    WHERE id = p_match_id;
  END IF;

  -- 6. Re-read to check both confirmed
  SELECT
    user1_confirmed_at IS NOT NULL AND user2_confirmed_at IS NOT NULL,
    CASE WHEN v_is_user1 THEN user1_confirmed_at IS NOT NULL ELSE user2_confirmed_at IS NOT NULL END,
    CASE WHEN v_is_user1 THEN user2_confirmed_at IS NOT NULL ELSE user1_confirmed_at IS NOT NULL END,
    status::text
  INTO v_both_done, v_caller_done, v_other_done, v_status
  FROM matches WHERE id = p_match_id;

  -- 7. If both confirmed, transition to COMPLETED
  IF v_both_done THEN
    UPDATE matches SET status = 'COMPLETED', updated_at = now()
    WHERE id = p_match_id;
    v_status := 'COMPLETED';
  END IF;

  RETURN json_build_object(
    'success',          true,
    'caller_confirmed', v_caller_done,
    'other_confirmed',  v_other_done,
    'both_confirmed',   v_both_done,
    'match_status',     v_status
  );
END;
$$;

REVOKE ALL ON FUNCTION confirm_trade_completion(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION confirm_trade_completion(uuid) TO authenticated;

-- ── 3. get_trade_confirmation_state RPC (read-only) ─────────────────────

CREATE OR REPLACE FUNCTION get_trade_confirmation_state(p_match_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_match       RECORD;
  v_caller_id   uuid := auth.uid();
  v_is_user1    boolean;
BEGIN
  IF v_caller_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'AUTH_REQUIRED');
  END IF;

  SELECT id, user1_id, user2_id, status::text AS status,
         user1_confirmed_at IS NOT NULL AS user1_confirmed,
         user2_confirmed_at IS NOT NULL AS user2_confirmed
  INTO v_match
  FROM matches WHERE id = p_match_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'MATCH_NOT_FOUND');
  END IF;

  IF v_caller_id NOT IN (v_match.user1_id, v_match.user2_id) THEN
    RETURN json_build_object('success', false, 'error', 'NOT_PARTICIPANT');
  END IF;

  v_is_user1 := (v_caller_id = v_match.user1_id);

  RETURN json_build_object(
    'success',          true,
    'caller_confirmed', CASE WHEN v_is_user1 THEN v_match.user1_confirmed ELSE v_match.user2_confirmed END,
    'other_confirmed',  CASE WHEN v_is_user1 THEN v_match.user2_confirmed ELSE v_match.user1_confirmed END,
    'both_confirmed',   v_match.user1_confirmed AND v_match.user2_confirmed,
    'match_status',     v_match.status
  );
END;
$$;

REVOKE ALL ON FUNCTION get_trade_confirmation_state(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION get_trade_confirmation_state(uuid) TO authenticated;
