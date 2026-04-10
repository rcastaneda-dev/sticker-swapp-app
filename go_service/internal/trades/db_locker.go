package trades

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// DBInventoryLocker is the production implementation backed by pgx.
type DBInventoryLocker struct {
	pool *pgxpool.Pool
}

// NewInventoryLocker creates a DBInventoryLocker with the given pool.
func NewInventoryLocker(pool *pgxpool.Pool) *DBInventoryLocker {
	return &DBInventoryLocker{pool: pool}
}

// LockForTrade calls the lock_inventory_for_trade() RPC via pgx transaction.
func (l *DBInventoryLocker) LockForTrade(ctx context.Context, callerID, matchID string) (*LockResult, error) {
	tx, err := l.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// Set the JWT claim for auth.uid() inside the RPC
	if _, err := tx.Exec(ctx, "SELECT set_config('request.jwt.claim.sub', $1, true)", callerID); err != nil {
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

	// Parse the JSON result from the RPC
	var raw struct {
		Success    bool    `json:"success"`
		StickerIDs []int   `json:"sticker_ids"`
		LockCount  int     `json:"lock_count"`
		ExpiresAt  *string `json:"expires_at"`
		Extended   bool    `json:"extended"`
		Error      *string `json:"error"`
	}
	if err := json.Unmarshal(resultJSON, &raw); err != nil {
		return nil, fmt.Errorf("unmarshal result: %w", err)
	}

	result := &LockResult{
		Success:    raw.Success,
		StickerIDs: raw.StickerIDs,
		LockCount:  raw.LockCount,
		Extended:   raw.Extended,
		Error:      raw.Error,
	}

	if raw.ExpiresAt != nil {
		t, err := time.Parse(time.RFC3339Nano, *raw.ExpiresAt)
		if err == nil {
			result.ExpiresAt = &t
		}
	}

	return result, nil
}

// ReleaseLocks calls the release_inventory_locks() RPC.
// This function is service_role only — no set_config needed since the Go
// service connects with the service role DB URL.
func (l *DBInventoryLocker) ReleaseLocks(ctx context.Context, matchID, reason string) (*ReleaseResult, error) {
	var resultJSON []byte
	err := l.pool.QueryRow(ctx,
		"SELECT release_inventory_locks($1, $2::lock_release_reason)", matchID, reason,
	).Scan(&resultJSON)
	if err != nil {
		return nil, fmt.Errorf("release_inventory_locks: %w", err)
	}

	var result ReleaseResult
	if err := json.Unmarshal(resultJSON, &result); err != nil {
		return nil, fmt.Errorf("unmarshal result: %w", err)
	}

	return &result, nil
}
