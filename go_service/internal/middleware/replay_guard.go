package middleware

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"log/slog"
	"net/http"
	"regexp"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// nonceRegex validates 32-character hexadecimal nonce format (16 random bytes).
var nonceRegex = regexp.MustCompile(`^[0-9a-fA-F]{32}$`)

// ---------------------------------------------------------------------------
// NonceStore interface
// ---------------------------------------------------------------------------

// NonceStore provides atomic check-and-store for replay nonces.
type NonceStore interface {
	// ConsumeNonce atomically checks if a nonce exists and stores it if new.
	// Returns true if the nonce was newly stored (first use).
	// Returns false if the nonce already existed (replay attempt).
	ConsumeNonce(ctx context.Context, nonce string, expiresAt time.Time) (bool, error)

	// CleanupExpired removes nonces whose expires_at is in the past.
	// Returns the number of deleted rows.
	CleanupExpired(ctx context.Context) (int64, error)
}

// ---------------------------------------------------------------------------
// PGNonceStore — PostgreSQL-backed implementation
// ---------------------------------------------------------------------------

// PGNonceStore stores consumed nonces in the replay_nonces table.
type PGNonceStore struct {
	pool *pgxpool.Pool
}

// NewPGNonceStore creates a nonce store backed by the given pgx pool.
func NewPGNonceStore(pool *pgxpool.Pool) *PGNonceStore {
	return &PGNonceStore{pool: pool}
}

// ConsumeNonce atomically inserts a nonce. Returns true if the nonce was
// freshly inserted, false if it already existed (replay).
func (s *PGNonceStore) ConsumeNonce(ctx context.Context, nonce string, expiresAt time.Time) (bool, error) {
	tag, err := s.pool.Exec(ctx,
		"INSERT INTO replay_nonces (nonce, expires_at) VALUES ($1, $2) ON CONFLICT DO NOTHING",
		nonce, expiresAt,
	)
	if err != nil {
		return false, fmt.Errorf("insert nonce: %w", err)
	}
	return tag.RowsAffected() == 1, nil
}

// CleanupExpired deletes all expired nonces and returns the count removed.
func (s *PGNonceStore) CleanupExpired(ctx context.Context) (int64, error) {
	tag, err := s.pool.Exec(ctx, "DELETE FROM replay_nonces WHERE expires_at < now()")
	if err != nil {
		return 0, fmt.Errorf("cleanup nonces: %w", err)
	}
	return tag.RowsAffected(), nil
}

// ---------------------------------------------------------------------------
// ReplayGuardConfig
// ---------------------------------------------------------------------------

// ReplayGuardConfig holds configuration for the replay guard middleware.
type ReplayGuardConfig struct {
	// HMACSecret is the shared key for HMAC-SHA256 signature verification.
	HMACSecret string
	// MaxClockSkew is the maximum allowed difference between the client
	// timestamp and server time. Default: 3 minutes.
	MaxClockSkew time.Duration
	// NonceTTL is how long consumed nonces are stored. Must be >= 2×MaxClockSkew
	// to prevent reuse after expiry. Default: 7 minutes.
	NonceTTL time.Duration
	// CleanupInterval is how often expired nonces are purged. Default: 5 minutes.
	CleanupInterval time.Duration
}

// DefaultReplayGuardConfig returns sensible defaults.
func DefaultReplayGuardConfig() ReplayGuardConfig {
	return ReplayGuardConfig{
		MaxClockSkew:    3 * time.Minute,
		NonceTTL:        7 * time.Minute,
		CleanupInterval: 5 * time.Minute,
	}
}

// ---------------------------------------------------------------------------
// ReplayGuard middleware
// ---------------------------------------------------------------------------

// ReplayGuard validates nonce + timestamp + HMAC-SHA256 signature on requests.
//
// Required headers:
//   - X-Nonce: 32-char hex string (16 random bytes)
//   - X-Timestamp: Unix epoch seconds
//   - X-Signature: hex-encoded HMAC-SHA256 of "METHOD:PATH:TIMESTAMP:NONCE"
//
// When disabled is true, all requests pass through without checks
// (for local development with REPLAY_GUARD_DISABLED=true).
func ReplayGuard(store NonceStore, cfg ReplayGuardConfig, disabled bool) func(http.Handler) http.Handler {
	// Background cleanup of expired nonces (follows RateLimit pattern).
	if !disabled && store != nil {
		go func() {
			ticker := time.NewTicker(cfg.CleanupInterval)
			defer ticker.Stop()
			for range ticker.C {
				deleted, err := store.CleanupExpired(context.Background())
				if err != nil {
					slog.Error("replay nonce cleanup failed", "error", err)
				} else if deleted > 0 {
					slog.Info("replay nonces cleaned up", "deleted", deleted)
				}
			}
		}()
	}

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if disabled {
				next.ServeHTTP(w, r)
				return
			}

			// 1. Extract headers
			nonce := r.Header.Get("X-Nonce")
			timestampStr := r.Header.Get("X-Timestamp")
			signature := r.Header.Get("X-Signature")

			if nonce == "" || timestampStr == "" || signature == "" {
				writeMiddlewareError(w, http.StatusBadRequest, "REPLAY_HEADERS_MISSING",
					"X-Nonce, X-Timestamp, and X-Signature headers are required")
				return
			}

			// 2. Validate nonce format (32-char hex)
			if !nonceRegex.MatchString(nonce) {
				writeMiddlewareError(w, http.StatusBadRequest, "REPLAY_INVALID_NONCE",
					"X-Nonce must be a 32-character hex string")
				return
			}

			// 3. Parse and validate timestamp
			timestampSec, err := strconv.ParseInt(timestampStr, 10, 64)
			if err != nil {
				writeMiddlewareError(w, http.StatusBadRequest, "REPLAY_INVALID_TIMESTAMP",
					"X-Timestamp must be a Unix epoch seconds integer")
				return
			}

			requestTime := time.Unix(timestampSec, 0)
			skew := time.Since(requestTime)
			if skew < 0 {
				skew = -skew
			}
			if skew > cfg.MaxClockSkew {
				writeMiddlewareError(w, http.StatusConflict, "REPLAY_TIMESTAMP_EXPIRED",
					fmt.Sprintf("Request timestamp outside allowed window (±%s)", cfg.MaxClockSkew))
				return
			}

			// 4. Verify HMAC-SHA256 signature
			// Signing string: "METHOD:PATH:TIMESTAMP:NONCE"
			signingString := fmt.Sprintf("%s:%s:%s:%s", r.Method, r.URL.Path, timestampStr, nonce)
			mac := hmac.New(sha256.New, []byte(cfg.HMACSecret))
			mac.Write([]byte(signingString))
			expectedSig := hex.EncodeToString(mac.Sum(nil))

			if !hmac.Equal([]byte(signature), []byte(expectedSig)) {
				writeMiddlewareError(w, http.StatusConflict, "REPLAY_INVALID_SIGNATURE",
					"Request signature verification failed")
				return
			}

			// 5. Atomic nonce consume (check + store)
			expiresAt := time.Now().Add(cfg.NonceTTL)
			consumed, err := store.ConsumeNonce(r.Context(), nonce, expiresAt)
			if err != nil {
				slog.Error("replay nonce store error",
					"error", err,
					"nonce", nonce,
					"path", r.URL.Path,
				)
				writeMiddlewareError(w, http.StatusInternalServerError, "REPLAY_STORE_ERROR",
					"Failed to verify request uniqueness")
				return
			}

			if !consumed {
				slog.Warn("replay attack blocked",
					"nonce", nonce,
					"path", r.URL.Path,
					"method", r.Method,
					"remote_addr", r.RemoteAddr,
				)
				writeMiddlewareError(w, http.StatusConflict, "REPLAY_DETECTED",
					"This request has already been processed")
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}
