package trades

import "context"

// ConfirmResult holds the outcome of a trade confirmation.
type ConfirmResult struct {
	Success         bool    `json:"success"`
	CallerConfirmed bool    `json:"caller_confirmed"`
	OtherConfirmed  bool    `json:"other_confirmed"`
	BothConfirmed   bool    `json:"both_confirmed"`
	MatchStatus     string  `json:"match_status,omitempty"`
	Error           *string `json:"error,omitempty"`
}

// TradeConfirmer records and queries trade confirmations.
type TradeConfirmer interface {
	// ConfirmTrade records the caller's confirmation for a match.
	ConfirmTrade(ctx context.Context, callerID, matchID string) (*ConfirmResult, error)
	// GetConfirmationState returns the current confirmation state for a match.
	GetConfirmationState(ctx context.Context, callerID, matchID string) (*ConfirmResult, error)
}
