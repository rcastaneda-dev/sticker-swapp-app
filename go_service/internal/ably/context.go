package ably

// contextKey is an unexported type to avoid context key collisions.
type contextKey string

const (
	userIDCtxKey    contextKey = "userID"
	isUnder13CtxKey contextKey = "isUnder13"
)

// UserIDKey returns the context key for the authenticated user ID.
func UserIDKey() contextKey { return userIDCtxKey }

// IsUnder13Key returns the context key for the under-13 flag.
func IsUnder13Key() contextKey { return isUnder13CtxKey }
