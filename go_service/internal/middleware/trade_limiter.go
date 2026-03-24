package middleware

import (
	"fmt"
	"net/http"
	"sync"
	"time"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
)

// TradeLimiterConfig holds the rate limits for trade operations.
type TradeLimiterConfig struct {
	// NormalMaxTrades is the max trades per window for clean devices.
	NormalMaxTrades int
	// CompromisedMaxTrades is the max trades per window for compromised devices.
	CompromisedMaxTrades int
	// WindowMinutes is the time window in minutes for trade counting.
	WindowMinutes int
}

// DefaultTradeLimiterConfig returns sensible defaults.
// Normal: 20 trades/hour, Compromised: 5 trades/hour.
func DefaultTradeLimiterConfig() TradeLimiterConfig {
	return TradeLimiterConfig{
		NormalMaxTrades:      20,
		CompromisedMaxTrades: 5,
		WindowMinutes:        60,
	}
}

// TradeLimiter applies differentiated rate limits to trade operations
// based on device integrity status.
//
// Compromised devices (rooted/jailbroken) receive a lower trade limit
// as a defense-in-depth measure. This prevents automated trading bots
// that might pass attestation but still run on compromised devices.
//
// Requires ReadDeviceIntegrity and ValidateJWT to be earlier in the
// middleware chain (needs deviceCompromised and userID from context).
func TradeLimiter(cfg TradeLimiterConfig) func(http.Handler) http.Handler {
	type bucket struct {
		trades      int
		windowStart time.Time
		mu          sync.Mutex
	}

	var buckets sync.Map

	// Periodic cleanup of stale buckets (every 5 minutes)
	go func() {
		ticker := time.NewTicker(5 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			cutoff := time.Now().Add(-time.Duration(cfg.WindowMinutes*2) * time.Minute)
			buckets.Range(func(key, value interface{}) bool {
				b := value.(*bucket)
				b.mu.Lock()
				if b.windowStart.Before(cutoff) {
					buckets.Delete(key)
				}
				b.mu.Unlock()
				return true
			})
		}
	}()

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			userID, _ := r.Context().Value(ably.UserIDKey()).(string)
			if userID == "" {
				writeMiddlewareError(w, http.StatusUnauthorized, "AUTH_REQUIRED",
					"Authentication required for trades")
				return
			}

			compromised, _ := r.Context().Value(ably.DeviceCompromisedKey()).(bool)

			maxTrades := cfg.NormalMaxTrades
			if compromised {
				maxTrades = cfg.CompromisedMaxTrades
			}

			val, _ := buckets.LoadOrStore(userID, &bucket{
				trades:      0,
				windowStart: time.Now(),
			})
			b := val.(*bucket)

			b.mu.Lock()
			now := time.Now()
			windowDuration := time.Duration(cfg.WindowMinutes) * time.Minute

			// Reset window if expired
			if now.Sub(b.windowStart) > windowDuration {
				b.trades = 0
				b.windowStart = now
			}

			if b.trades >= maxTrades {
				b.mu.Unlock()
				w.Header().Set("Retry-After", fmt.Sprintf("%d", cfg.WindowMinutes*60))
				writeMiddlewareError(w, http.StatusTooManyRequests, "TRADE_LIMIT_EXCEEDED",
					fmt.Sprintf("Trade limit exceeded. Max %d trades per %d minutes.", maxTrades, cfg.WindowMinutes))
				return
			}

			b.trades++
			b.mu.Unlock()

			next.ServeHTTP(w, r)
		})
	}
}
