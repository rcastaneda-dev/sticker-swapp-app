package trades

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

// DBTradeConfirmer is the production implementation backed by pgx.
type DBTradeConfirmer struct {
	pool *pgxpool.Pool
}

// NewTradeConfirmer creates a DBTradeConfirmer with the given pool.
func NewTradeConfirmer(pool *pgxpool.Pool) *DBTradeConfirmer {
	return &DBTradeConfirmer{pool: pool}
}

// ConfirmTrade calls the confirm_trade_completion() RPC via pgx transaction.
func (c *DBTradeConfirmer) ConfirmTrade(ctx context.Context, callerID, matchID string) (*ConfirmResult, error) {
	tx, err := c.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// Set the JWT claim for auth.uid() inside the RPC
	if _, err := tx.Exec(ctx, "SELECT set_config('request.jwt.claim.sub', $1, true)", callerID); err != nil {
		return nil, fmt.Errorf("set_config: %w", err)
	}

	var resultJSON []byte
	err = tx.QueryRow(ctx, "SELECT confirm_trade_completion($1)", matchID).Scan(&resultJSON)
	if err != nil {
		return nil, fmt.Errorf("confirm_trade_completion: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("commit: %w", err)
	}

	var result ConfirmResult
	if err := json.Unmarshal(resultJSON, &result); err != nil {
		return nil, fmt.Errorf("unmarshal result: %w", err)
	}

	return &result, nil
}

// GetConfirmationState calls the get_trade_confirmation_state() RPC via pgx transaction.
func (c *DBTradeConfirmer) GetConfirmationState(ctx context.Context, callerID, matchID string) (*ConfirmResult, error) {
	tx, err := c.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, "SELECT set_config('request.jwt.claim.sub', $1, true)", callerID); err != nil {
		return nil, fmt.Errorf("set_config: %w", err)
	}

	var resultJSON []byte
	err = tx.QueryRow(ctx, "SELECT get_trade_confirmation_state($1)", matchID).Scan(&resultJSON)
	if err != nil {
		return nil, fmt.Errorf("get_trade_confirmation_state: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("commit: %w", err)
	}

	var result ConfirmResult
	if err := json.Unmarshal(resultJSON, &result); err != nil {
		return nil, fmt.Errorf("unmarshal result: %w", err)
	}

	return &result, nil
}
