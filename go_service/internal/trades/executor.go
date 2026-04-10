package trades

import "context"

// TradeRequest holds the parameters for executing a trade.
type TradeRequest struct {
	MatchID             string `json:"match_id"`
	InitiatorStickerIDs []int  `json:"initiator_sticker_ids"`
	ResponderStickerIDs []int  `json:"responder_sticker_ids"`
	IdempotencyKey      string `json:"idempotency_key"`
}

// TradeResult holds the outcome of a trade execution.
type TradeResult struct {
	Success             bool    `json:"success"`
	TradeID             *string `json:"trade_id,omitempty"`
	MatchID             *string `json:"match_id,omitempty"`
	InitiatorID         *string `json:"initiator_id,omitempty"`
	ResponderID         *string `json:"responder_id,omitempty"`
	InitiatorStickerIDs []int   `json:"initiator_sticker_ids,omitempty"`
	ResponderStickerIDs []int   `json:"responder_sticker_ids,omitempty"`
	Status              *string `json:"status,omitempty"`
	AlreadyCompleted    bool    `json:"already_completed,omitempty"`
	Error               *string `json:"error,omitempty"`
}

// TradeExecutor executes an atomic sticker trade.
type TradeExecutor interface {
	// ExecuteTrade atomically verifies locks, transfers stickers, records the
	// audit entry, updates the match status, and releases inventory locks.
	// callerID comes from the JWT context (the trade initiator).
	// Idempotent by TradeRequest.IdempotencyKey.
	ExecuteTrade(ctx context.Context, callerID string, req TradeRequest) (*TradeResult, error)
}
