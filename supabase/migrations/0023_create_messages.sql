-- Migration 0023: Chat message persistence for Ably webhook audit
--
-- Stores chat messages published on match:{matchId} Ably channels.
-- Written exclusively by the ably-webhook Edge Function via service_role.
-- Idempotent: ably_message_id UNIQUE constraint + ON CONFLICT DO NOTHING
-- handles Ably's at-least-once webhook delivery.

-- =============================================================================
-- Table: messages
-- =============================================================================
CREATE TABLE messages (
  id                bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ably_message_id   text         NOT NULL UNIQUE,
  match_id          uuid         NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  sender_id         uuid         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content           text         NOT NULL CHECK (char_length(content) > 0 AND char_length(content) <= 4000),
  event_name        text         NOT NULL DEFAULT 'chat.message',
  ably_timestamp    timestamptz  NOT NULL,
  created_at        timestamptz  NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_messages_match_id  ON messages (match_id, ably_timestamp);
CREATE INDEX idx_messages_sender_id ON messages (sender_id);

-- =============================================================================
-- RLS
-- =============================================================================
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Participants of the match can read messages
CREATE POLICY "match_participants_read_messages"
  ON messages FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM matches
      WHERE matches.id = messages.match_id
        AND auth.uid() IN (matches.user1_id, matches.user2_id)
    )
  );

-- No INSERT/UPDATE/DELETE policies for client roles.
-- All writes go through the insert_message() SECURITY DEFINER RPC
-- called by the Edge Function using service_role.

-- =============================================================================
-- RPC: insert_message()
--
-- Called by the ably-webhook Edge Function via service_role.
-- Idempotent: ON CONFLICT (ably_message_id) DO NOTHING.
-- Returns JSON with success status and whether the message was a duplicate.
-- =============================================================================
CREATE FUNCTION insert_message(
  p_ably_message_id   text,
  p_match_id          uuid,
  p_sender_id         uuid,
  p_content           text,
  p_event_name        text,
  p_ably_timestamp    timestamptz
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id bigint;
BEGIN
  -- Validate match exists and sender is a participant
  IF NOT EXISTS (
    SELECT 1 FROM matches
    WHERE id = p_match_id
      AND p_sender_id IN (user1_id, user2_id)
  ) THEN
    RETURN json_build_object(
      'success', false,
      'error', 'INVALID_MATCH_OR_SENDER'
    );
  END IF;

  INSERT INTO messages (
    ably_message_id,
    match_id,
    sender_id,
    content,
    event_name,
    ably_timestamp
  )
  VALUES (
    p_ably_message_id,
    p_match_id,
    p_sender_id,
    p_content,
    p_event_name,
    p_ably_timestamp
  )
  ON CONFLICT (ably_message_id) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    -- Duplicate: already persisted (idempotent success)
    RETURN json_build_object(
      'success', true,
      'duplicate', true
    );
  END IF;

  RETURN json_build_object(
    'success', true,
    'duplicate', false,
    'message_id', v_id
  );
END;
$$;

-- Permissions: service_role only (Edge Function calls with service_role key)
REVOKE ALL ON FUNCTION insert_message(text, uuid, uuid, text, text, timestamptz) FROM public;
REVOKE ALL ON FUNCTION insert_message(text, uuid, uuid, text, text, timestamptz) FROM anon;
REVOKE ALL ON FUNCTION insert_message(text, uuid, uuid, text, text, timestamptz) FROM authenticated;
GRANT EXECUTE ON FUNCTION insert_message(text, uuid, uuid, text, text, timestamptz) TO service_role;
