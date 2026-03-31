package api

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

// DisplayNameLookup resolves a user's display name.
type DisplayNameLookup interface {
	LookupDisplayName(ctx context.Context, userID string) string
}

// DBDisplayNameLookup queries user_profiles for display names.
type DBDisplayNameLookup struct {
	Pool *pgxpool.Pool
}

// LookupDisplayName fetches the display name for a user, returning "Someone" on failure.
func (d *DBDisplayNameLookup) LookupDisplayName(ctx context.Context, userID string) string {
	var name *string
	err := d.Pool.QueryRow(ctx,
		"SELECT display_name FROM user_profiles WHERE user_id = $1", userID,
	).Scan(&name)
	if err != nil || name == nil {
		return "Someone"
	}
	return *name
}
