-- Migration 0021: Replay attack prevention nonce storage
--
-- Stores consumed request nonces with expiry for replay detection.
-- INSERT ON CONFLICT DO NOTHING provides atomic check-and-store semantics.
-- The Go service connects via SUPABASE_DB_URL (direct PG connection),
-- so RLS does not affect its queries. We enable RLS with no policies
-- to satisfy the migration 0007 audit.

CREATE TABLE replay_nonces (
  nonce       text        PRIMARY KEY,
  created_at  timestamptz NOT NULL DEFAULT now(),
  expires_at  timestamptz NOT NULL
);

-- Index for efficient cleanup: DELETE WHERE expires_at < now()
CREATE INDEX idx_replay_nonces_expires ON replay_nonces (expires_at);

-- Enable RLS (required by migration 0007 audit).
-- No policies needed — only accessed by Go service via direct PG connection.
ALTER TABLE replay_nonces ENABLE ROW LEVEL SECURITY;
