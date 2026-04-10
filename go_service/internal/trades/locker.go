package trades

import (
	"context"
	"time"
)

// LockResult holds the outcome of an inventory lock attempt.
type LockResult struct {
	Success    bool       `json:"success"`
	StickerIDs []int      `json:"sticker_ids,omitempty"`
	LockCount  int        `json:"lock_count"`
	ExpiresAt  *time.Time `json:"expires_at,omitempty"`
	Extended   bool       `json:"extended"`
	Error      *string    `json:"error,omitempty"`
}

// ReleaseResult holds the outcome of a lock release.
type ReleaseResult struct {
	Success       bool `json:"success"`
	ReleasedCount int  `json:"released_count"`
}

// InventoryLocker manages soft-locks on user inventory for trades.
type InventoryLocker interface {
	// LockForTrade locks the caller's DUPLICATE stickers for the given match.
	// Returns the locked sticker IDs, expiry time, and whether this was an extension.
	LockForTrade(ctx context.Context, callerID, matchID string) (*LockResult, error)

	// ReleaseLocks releases all active locks for a match (both participants).
	// Reason should be one of: MANUAL_RELEASE, TRADE_COMPLETED, TRADE_CANCELLED.
	ReleaseLocks(ctx context.Context, matchID, reason string) (*ReleaseResult, error)
}
