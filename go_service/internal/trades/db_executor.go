package trades

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

// DBTradeExecutor is the production implementation backed by pgx.
type DBTradeExecutor struct {
	pool *pgxpool.Pool
}

// NewTradeExecutor creates a DBTradeExecutor with the given pool.
func NewTradeExecutor(pool *pgxpool.Pool) *DBTradeExecutor {
	return &DBTradeExecutor{pool: pool}
}

// ExecuteTrade calls the execute_trade() RPC.
// This is a service_role-only call — no set_config needed since the Go
// service connects with the service role DB URL.
func (e *DBTradeExecutor) ExecuteTrade(ctx context.Context, callerID string, req TradeRequest) (*TradeResult, error) {
	var resultJSON []byte
	err := e.pool.QueryRow(ctx,
		"SELECT execute_trade($1, $2, $3, $4, $5)",
		req.MatchID,
		callerID,
		req.InitiatorStickerIDs,
		req.ResponderStickerIDs,
		req.IdempotencyKey,
	).Scan(&resultJSON)
	if err != nil {
		return nil, fmt.Errorf("execute_trade: %w", err)
	}

	var result TradeResult
	if err := json.Unmarshal(resultJSON, &result); err != nil {
		return nil, fmt.Errorf("unmarshal result: %w", err)
	}

	return &result, nil
}
