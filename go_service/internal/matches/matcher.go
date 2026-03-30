package matches

import (
	"context"
	"time"
)

// CreateMatchResult holds the outcome of a swipe/match attempt.
type CreateMatchResult struct {
	Matched       bool       `json:"matched"`
	SwipeRecorded bool       `json:"swipe_recorded,omitempty"`
	MatchID       *string    `json:"match_id,omitempty"`
	User1ID       *string    `json:"user1_id,omitempty"`
	User2ID       *string    `json:"user2_id,omitempty"`
	Status        *string    `json:"status,omitempty"`
	CreatedAt     *time.Time `json:"created_at,omitempty"`
}

// MatchCreator records a swipe and creates a match if mutual.
type MatchCreator interface {
	CreateMatchIfMutual(ctx context.Context, callerID, targetID string) (*CreateMatchResult, error)
}
