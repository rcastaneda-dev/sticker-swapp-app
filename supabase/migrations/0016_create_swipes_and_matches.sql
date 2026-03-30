-- 0016_create_swipes_and_matches.sql
-- Creates swipes table, matches table, and create_match_if_mutual() RPC
-- for the Tinder-style mutual-swipe matching system.

-- ============================================================
-- 1. match_status enum
-- ============================================================
CREATE TYPE match_status AS ENUM ('PENDING', 'ACCEPTED', 'COMPLETED', 'CANCELLED', 'EXPIRED');

-- ============================================================
-- 2. swipes table — records individual right-swipes
-- ============================================================
CREATE TABLE swipes (
  id          bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  swiper_id   uuid         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  target_id   uuid         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at  timestamptz  NOT NULL DEFAULT now(),

  CHECK (swiper_id <> target_id),
  UNIQUE (swiper_id, target_id)
);

CREATE INDEX idx_swipes_target ON swipes (target_id);
CREATE INDEX idx_swipes_created ON swipes (created_at);

ALTER TABLE swipes ENABLE ROW LEVEL SECURITY;

-- Users can read their own swipes only; writes go through RPC
CREATE POLICY "users_read_own_swipes"
  ON swipes FOR SELECT
  TO authenticated
  USING (auth.uid() = swiper_id);

-- ============================================================
-- 3. matches table — created when both users swipe right
-- ============================================================
CREATE TABLE matches (
  id          uuid         NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user1_id    uuid         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user2_id    uuid         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status      match_status NOT NULL DEFAULT 'PENDING',
  created_at  timestamptz  NOT NULL DEFAULT now(),
  updated_at  timestamptz  NOT NULL DEFAULT now(),

  -- Canonical ordering prevents duplicate A↔B matches
  CHECK (user1_id < user2_id),
  UNIQUE (user1_id, user2_id)
);

CREATE INDEX idx_matches_user1 ON matches (user1_id);
CREATE INDEX idx_matches_user2 ON matches (user2_id);
CREATE INDEX idx_matches_status ON matches (status);

ALTER TABLE matches ENABLE ROW LEVEL SECURITY;

-- Users can read matches they participate in
CREATE POLICY "users_read_own_matches"
  ON matches FOR SELECT
  TO authenticated
  USING (auth.uid() IN (user1_id, user2_id));

-- Auto-update updated_at on row change
CREATE OR REPLACE FUNCTION update_matches_timestamp()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_matches_before_update
  BEFORE UPDATE ON matches
  FOR EACH ROW
  EXECUTE FUNCTION update_matches_timestamp();

-- ============================================================
-- 4. create_match_if_mutual() — SECURITY DEFINER RPC
-- ============================================================
CREATE OR REPLACE FUNCTION create_match_if_mutual(p_target_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id  uuid;
  v_match_id   uuid;
  v_user1      uuid;
  v_user2      uuid;
  v_mutual     boolean;
BEGIN
  v_caller_id := auth.uid();

  -- Guard: caller must be authenticated
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Guard: cannot swipe on yourself
  IF v_caller_id = p_target_id THEN
    RETURN json_build_object('error', 'cannot_swipe_self');
  END IF;

  -- Guard: target must exist
  IF NOT EXISTS (SELECT 1 FROM user_profiles WHERE user_id = p_target_id) THEN
    RETURN json_build_object('error', 'target_not_found');
  END IF;

  -- Record the swipe (idempotent via ON CONFLICT DO NOTHING)
  INSERT INTO swipes (swiper_id, target_id)
  VALUES (v_caller_id, p_target_id)
  ON CONFLICT (swiper_id, target_id) DO NOTHING;

  -- Check if the target has already swiped right on the caller
  v_mutual := EXISTS (
    SELECT 1 FROM swipes
    WHERE swiper_id = p_target_id AND target_id = v_caller_id
  );

  IF NOT v_mutual THEN
    RETURN json_build_object(
      'matched', false,
      'swipe_recorded', true
    );
  END IF;

  -- Mutual swipe — create match with canonical user ordering
  v_user1 := LEAST(v_caller_id, p_target_id);
  v_user2 := GREATEST(v_caller_id, p_target_id);

  INSERT INTO matches (user1_id, user2_id, status)
  VALUES (v_user1, v_user2, 'PENDING')
  ON CONFLICT (user1_id, user2_id) DO NOTHING
  RETURNING id INTO v_match_id;

  -- If match already existed (concurrent call), fetch existing ID
  IF v_match_id IS NULL THEN
    SELECT id INTO v_match_id
    FROM matches
    WHERE user1_id = v_user1 AND user2_id = v_user2;
  END IF;

  RETURN json_build_object(
    'matched',    true,
    'match_id',   v_match_id,
    'user1_id',   v_user1,
    'user2_id',   v_user2,
    'status',     'PENDING',
    'created_at', now()
  );
END;
$$;

-- Grant to authenticated users only
REVOKE ALL ON FUNCTION create_match_if_mutual(uuid) FROM public;
REVOKE ALL ON FUNCTION create_match_if_mutual(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION create_match_if_mutual(uuid) TO authenticated;
