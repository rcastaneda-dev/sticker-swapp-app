-- 0017_add_wishlist_shares.sql
-- Creates wishlist_shares table and RPCs for shareable under-13 wishlists.

-- ============================================================
-- 1. wishlist_shares table — tracks shareable wishlist links
-- ============================================================
CREATE TABLE wishlist_shares (
  id            bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  token         text         NOT NULL UNIQUE,
  user_id       uuid         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name  text,
  expires_at    timestamptz  NOT NULL,
  created_at    timestamptz  NOT NULL DEFAULT now()
);

CREATE INDEX idx_wishlist_shares_token ON wishlist_shares (token)
  WHERE expires_at > now();

CREATE INDEX idx_wishlist_shares_user ON wishlist_shares (user_id);

ALTER TABLE wishlist_shares ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_read_own_wishlist_shares"
  ON wishlist_shares FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- ============================================================
-- 2. create_wishlist_share() — generate a shareable token
-- ============================================================
CREATE OR REPLACE FUNCTION create_wishlist_share()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id      uuid;
  v_display_name text;
  v_token        text;
  v_existing     record;
BEGIN
  v_user_id := auth.uid();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  -- Snapshot display name from user metadata
  SELECT COALESCE(
    raw_user_meta_data->>'display_name',
    raw_user_meta_data->>'full_name',
    'Collector'
  ) INTO v_display_name
  FROM auth.users
  WHERE id = v_user_id;

  -- Reuse existing non-expired share
  SELECT * INTO v_existing
  FROM wishlist_shares
  WHERE user_id = v_user_id
    AND expires_at > now()
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RETURN json_build_object(
      'success', true,
      'token',   v_existing.token,
      'already_exists', true
    );
  END IF;

  -- Generate new 64-char hex token (32 random bytes)
  v_token := encode(gen_random_bytes(32), 'hex');

  INSERT INTO wishlist_shares (token, user_id, display_name, expires_at)
  VALUES (v_token, v_user_id, v_display_name, now() + interval '30 days');

  RETURN json_build_object(
    'success', true,
    'token',   v_token,
    'already_exists', false
  );
END;
$$;

REVOKE ALL ON FUNCTION create_wishlist_share() FROM public;
REVOKE ALL ON FUNCTION create_wishlist_share() FROM anon;
GRANT EXECUTE ON FUNCTION create_wishlist_share() TO authenticated;

-- ============================================================
-- 3. get_shared_wishlist(token) — public wishlist lookup
-- ============================================================
CREATE OR REPLACE FUNCTION get_shared_wishlist(p_token text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_share    record;
  v_wishlist json;
  v_count    int;
BEGIN
  SELECT * INTO v_share
  FROM wishlist_shares
  WHERE token = p_token;

  IF v_share IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'invalid_token');
  END IF;

  IF v_share.expires_at < now() THEN
    RETURN json_build_object('success', false, 'error', 'expired');
  END IF;

  -- Needed = all stickers not in user's OWNED or DUPLICATE inventory
  SELECT json_agg(row_to_json(t) ORDER BY t.team NULLS LAST, t.sticker_number)
  INTO v_wishlist
  FROM (
    SELECT s.sticker_number, s.title, s.team, s.type, s.image_url
    FROM stickers s
    WHERE s.id NOT IN (
      SELECT ui.sticker_id
      FROM user_inventory ui
      WHERE ui.user_id = v_share.user_id
        AND ui.status IN ('OWNED', 'DUPLICATE')
    )
  ) t;

  v_count := COALESCE(json_array_length(v_wishlist), 0);

  RETURN json_build_object(
    'success',       true,
    'display_name',  v_share.display_name,
    'sticker_count', v_count,
    'stickers',      COALESCE(v_wishlist, '[]'::json)
  );
END;
$$;

-- Only service_role can call (Edge Function)
REVOKE ALL ON FUNCTION get_shared_wishlist(text) FROM public;
REVOKE ALL ON FUNCTION get_shared_wishlist(text) FROM anon;
REVOKE ALL ON FUNCTION get_shared_wishlist(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION get_shared_wishlist(text) TO service_role;
