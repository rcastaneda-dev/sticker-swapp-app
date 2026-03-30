package matches

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// DBMatchCreator is the production implementation backed by pgx.
type DBMatchCreator struct {
	pool *pgxpool.Pool
}

// NewMatchCreator creates a DBMatchCreator with the given pool.
func NewMatchCreator(pool *pgxpool.Pool) *DBMatchCreator {
	return &DBMatchCreator{pool: pool}
}

// CreateMatchIfMutual calls the create_match_if_mutual() RPC via pgx transaction.
func (m *DBMatchCreator) CreateMatchIfMutual(ctx context.Context, callerID, targetID string) (*CreateMatchResult, error) {
	tx, err := m.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// Set the JWT claim for auth.uid() inside the RPC
	if _, err := tx.Exec(ctx, "SELECT set_config('request.jwt.claim.sub', $1, true)", callerID); err != nil {
		return nil, fmt.Errorf("set_config: %w", err)
	}

	var resultJSON []byte
	err = tx.QueryRow(ctx, "SELECT create_match_if_mutual($1)", targetID).Scan(&resultJSON)
	if err != nil {
		return nil, fmt.Errorf("create_match_if_mutual: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("commit: %w", err)
	}

	// Parse the JSON result from the RPC
	var raw struct {
		Error         *string `json:"error"`
		Matched       bool    `json:"matched"`
		SwipeRecorded bool    `json:"swipe_recorded"`
		MatchID       *string `json:"match_id"`
		User1ID       *string `json:"user1_id"`
		User2ID       *string `json:"user2_id"`
		Status        *string `json:"status"`
		CreatedAt     *string `json:"created_at"`
	}
	if err := json.Unmarshal(resultJSON, &raw); err != nil {
		return nil, fmt.Errorf("unmarshal result: %w", err)
	}

	// If the RPC returned an application-level error, bubble it up
	if raw.Error != nil {
		return nil, fmt.Errorf("rpc error: %s", *raw.Error)
	}

	result := &CreateMatchResult{
		Matched:       raw.Matched,
		SwipeRecorded: raw.SwipeRecorded,
		MatchID:       raw.MatchID,
		User1ID:       raw.User1ID,
		User2ID:       raw.User2ID,
		Status:        raw.Status,
	}

	if raw.CreatedAt != nil {
		t, err := time.Parse(time.RFC3339Nano, *raw.CreatedAt)
		if err == nil {
			result.CreatedAt = &t
		}
	}

	return result, nil
}
