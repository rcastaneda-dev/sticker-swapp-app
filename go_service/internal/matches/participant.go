package matches

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ParticipantChecker verifies if a user is a participant in a match.
type ParticipantChecker interface {
	IsParticipant(ctx context.Context, userID, matchID string) (bool, error)
}

// DBParticipantChecker is the production implementation backed by pgx.
type DBParticipantChecker struct {
	pool *pgxpool.Pool
}

// NewParticipantChecker creates a DBParticipantChecker with the given pool.
func NewParticipantChecker(pool *pgxpool.Pool) *DBParticipantChecker {
	return &DBParticipantChecker{pool: pool}
}

// IsParticipant checks if the user is user1 or user2 in the match.
func (c *DBParticipantChecker) IsParticipant(ctx context.Context, userID, matchID string) (bool, error) {
	var exists bool
	err := c.pool.QueryRow(ctx,
		"SELECT EXISTS(SELECT 1 FROM matches WHERE id = $1 AND (user1_id = $2 OR user2_id = $2))",
		matchID, userID,
	).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("check match participant: %w", err)
	}
	return exists, nil
}
