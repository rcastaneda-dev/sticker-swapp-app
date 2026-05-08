// Package testutil provides reusable helpers for integration tests
// that require a real PostgreSQL database (local Supabase instance).
package testutil

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"os"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// InventoryItem represents a sticker in a user's inventory for test seeding.
type InventoryItem struct {
	StickerID int
	Status    string // "OWNED" or "DUPLICATE"
	Quantity  int
}

// MustPool creates a pgxpool connected to the test database.
// Skips the test if no database URL is configured.
// Registers t.Cleanup to close the pool when the test finishes.
func MustPool(t *testing.T, maxConns int) *pgxpool.Pool {
	t.Helper()

	dbURL := os.Getenv("TEST_DATABASE_URL")
	if dbURL == "" {
		dbURL = os.Getenv("SUPABASE_DB_URL")
	}
	if dbURL == "" {
		t.Skip("no TEST_DATABASE_URL or SUPABASE_DB_URL set; skipping integration test")
	}

	config, err := pgxpool.ParseConfig(dbURL)
	if err != nil {
		t.Fatalf("parse database config: %v", err)
	}
	// Disable prepared statement caching — required for Supabase transaction pooler (PgBouncer).
	config.ConnConfig.DefaultQueryExecMode = pgx.QueryExecModeSimpleProtocol
	if maxConns > 0 {
		config.MaxConns = int32(maxConns)
	}

	pool, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		t.Fatalf("create pool: %v", err)
	}

	if err := pool.Ping(context.Background()); err != nil {
		pool.Close()
		t.Fatalf("ping database: %v", err)
	}

	t.Cleanup(pool.Close)
	return pool
}

// CreateTestUser inserts a row into auth.users with the given email.
// The migration 0008 trigger auto-creates a user_profiles row.
// Returns the generated user ID.
func CreateTestUser(ctx context.Context, pool *pgxpool.Pool, email string) (string, error) {
	var userID string
	err := pool.QueryRow(ctx, `
		INSERT INTO auth.users (
			instance_id, id, aud, role, email,
			encrypted_password, email_confirmed_at,
			created_at, updated_at, confirmation_token,
			raw_app_meta_data, raw_user_meta_data
		) VALUES (
			'00000000-0000-0000-0000-000000000000',
			gen_random_uuid(), 'authenticated', 'authenticated', $1::text,
			crypt('testpassword123', gen_salt('bf')),
			now(), now(), now(), '',
			'{"provider":"email","providers":["email"]}'::jsonb,
			jsonb_build_object('display_name', split_part($1::text, '@', 1))
		) RETURNING id::text
	`, email).Scan(&userID)
	if err != nil {
		return "", fmt.Errorf("create test user %s: %w", email, err)
	}
	return userID, nil
}

// SeedInventory inserts sticker inventory rows for a user.
// Uses ON CONFLICT to allow re-seeding without error.
func SeedInventory(ctx context.Context, pool *pgxpool.Pool, userID string, items []InventoryItem) error {
	for _, item := range items {
		_, err := pool.Exec(ctx, `
			INSERT INTO user_inventory (user_id, sticker_id, status, quantity, trade_status)
			VALUES ($1::uuid, $2, $3::inventory_status, $4, 'AVAILABLE'::trade_item_status)
			ON CONFLICT (user_id, sticker_id) DO UPDATE
			SET status = EXCLUDED.status, quantity = EXCLUDED.quantity,
			    trade_status = 'AVAILABLE'::trade_item_status
		`, userID, item.StickerID, item.Status, item.Quantity)
		if err != nil {
			return fmt.Errorf("seed inventory sticker %d for user %s: %w", item.StickerID, userID, err)
		}
	}
	return nil
}

// CreateMatch inserts a PENDING match between two users with canonical ordering.
// Returns the match UUID.
func CreateMatch(ctx context.Context, pool *pgxpool.Pool, user1ID, user2ID string) (string, error) {
	var matchID string
	err := pool.QueryRow(ctx, `
		INSERT INTO matches (user1_id, user2_id, status)
		VALUES (LEAST($1::uuid, $2::uuid), GREATEST($1::uuid, $2::uuid), 'PENDING')
		RETURNING id::text
	`, user1ID, user2ID).Scan(&matchID)
	if err != nil {
		return "", fmt.Errorf("create match between %s and %s: %w", user1ID, user2ID, err)
	}
	return matchID, nil
}

// LockInventory calls lock_inventory_for_trade() RPC for a user on a match.
// This simulates what DBInventoryLocker.LockForTrade does.
// Returns the locked sticker IDs.
func LockInventory(ctx context.Context, pool *pgxpool.Pool, userID, matchID string) ([]int, error) {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, "SELECT set_config('request.jwt.claim.sub', $1, true)", userID); err != nil {
		return nil, fmt.Errorf("set_config: %w", err)
	}

	var resultJSON []byte
	err = tx.QueryRow(ctx, "SELECT lock_inventory_for_trade($1)", matchID).Scan(&resultJSON)
	if err != nil {
		return nil, fmt.Errorf("lock_inventory_for_trade: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("commit: %w", err)
	}

	var resp struct {
		Success    bool    `json:"success"`
		StickerIDs []int   `json:"sticker_ids"`
		Error      *string `json:"error"`
	}
	if err := json.Unmarshal(resultJSON, &resp); err != nil {
		return nil, fmt.Errorf("unmarshal lock result: %w", err)
	}
	if !resp.Success {
		errMsg := "unknown"
		if resp.Error != nil {
			errMsg = *resp.Error
		}
		return nil, fmt.Errorf("lock failed: %s", errMsg)
	}
	return resp.StickerIDs, nil
}

// LockInventoryRaw is like LockInventory but returns the raw JSON response
// instead of erroring on failure. Useful for testing expected lock failures.
func LockInventoryRaw(ctx context.Context, pool *pgxpool.Pool, userID, matchID string) (success bool, errCode string, err error) {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return false, "", fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, "SELECT set_config('request.jwt.claim.sub', $1, true)", userID); err != nil {
		return false, "", fmt.Errorf("set_config: %w", err)
	}

	var resultJSON []byte
	err = tx.QueryRow(ctx, "SELECT lock_inventory_for_trade($1)", matchID).Scan(&resultJSON)
	if err != nil {
		return false, "", fmt.Errorf("lock_inventory_for_trade: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return false, "", fmt.Errorf("commit: %w", err)
	}

	var resp struct {
		Success bool    `json:"success"`
		Error   *string `json:"error"`
	}
	if err := json.Unmarshal(resultJSON, &resp); err != nil {
		return false, "", fmt.Errorf("unmarshal: %w", err)
	}
	code := ""
	if resp.Error != nil {
		code = *resp.Error
	}
	return resp.Success, code, nil
}

// Cleanup removes all test data for the given user IDs in reverse FK order.
// Safe to call even if some data doesn't exist.
func Cleanup(ctx context.Context, pool *pgxpool.Pool, userIDs []string) error {
	if len(userIDs) == 0 {
		return nil
	}

	queries := []string{
		"DELETE FROM inventory_locks WHERE user_id = ANY($1::uuid[])",
		"DELETE FROM trade_audit_log WHERE initiator_id = ANY($1::uuid[]) OR responder_id = ANY($1::uuid[])",
		"DELETE FROM user_inventory WHERE user_id = ANY($1::uuid[])",
		"DELETE FROM matches WHERE user1_id = ANY($1::uuid[]) OR user2_id = ANY($1::uuid[])",
		"DELETE FROM swipes WHERE swiper_id = ANY($1::uuid[]) OR target_id = ANY($1::uuid[])",
		"DELETE FROM user_profiles WHERE user_id = ANY($1::uuid[])",
		"DELETE FROM auth.users WHERE id = ANY($1::uuid[])",
	}

	for _, q := range queries {
		if _, err := pool.Exec(ctx, q, userIDs); err != nil {
			return fmt.Errorf("cleanup query %q: %w", q, err)
		}
	}
	return nil
}

// NewUUID generates a random UUID v4 string without external dependencies.
func NewUUID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	b[6] = (b[6] & 0x0f) | 0x40 // version 4
	b[8] = (b[8] & 0x3f) | 0x80 // variant 2
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}
