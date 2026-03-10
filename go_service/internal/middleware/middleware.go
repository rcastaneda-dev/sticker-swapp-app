package middleware

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
)

// Chain composes middleware in order: Chain(a, b, c)(handler) = a(b(c(handler)))
func Chain(middlewares ...func(http.Handler) http.Handler) func(http.Handler) http.Handler {
	return func(final http.Handler) http.Handler {
		for i := len(middlewares) - 1; i >= 0; i-- {
			final = middlewares[i](final)
		}
		return final
	}
}

// ValidateJWT verifies the Supabase JWT from the Authorization header.
//
// It calls the Supabase Auth `/auth/v1/user` endpoint with the bearer
// token to validate it server-side. This avoids needing to manage JWT
// signing keys locally and ensures tokens respect Supabase's 15-minute
// expiry and refresh token rotation (PRD §6.2).
//
// On success, it sets the user ID and under-13 flag in the request context.
func ValidateJWT(supabaseURL, supabaseServiceKey string) func(http.Handler) http.Handler {
	client := &http.Client{Timeout: 5 * time.Second}

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authHeader := r.Header.Get("Authorization")
			if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
				writeMiddlewareError(w, http.StatusUnauthorized, "AUTH_MISSING", "Authorization header required")
				return
			}
			token := strings.TrimPrefix(authHeader, "Bearer ")

			// Validate token against Supabase Auth
			req, err := http.NewRequestWithContext(r.Context(), "GET", supabaseURL+"/auth/v1/user", nil)
			if err != nil {
				writeMiddlewareError(w, http.StatusInternalServerError, "AUTH_ERROR", "Failed to build auth request")
				return
			}
			req.Header.Set("Authorization", "Bearer "+token)
			req.Header.Set("apikey", supabaseServiceKey)

			resp, err := client.Do(req)
			if err != nil {
				writeMiddlewareError(w, http.StatusBadGateway, "AUTH_UPSTREAM", "Auth service unavailable")
				return
			}
			defer resp.Body.Close()

			if resp.StatusCode != http.StatusOK {
				writeMiddlewareError(w, http.StatusUnauthorized, "AUTH_INVALID", "Invalid or expired token")
				return
			}

			body, err := io.ReadAll(resp.Body)
			if err != nil {
				writeMiddlewareError(w, http.StatusInternalServerError, "AUTH_READ", "Failed to read auth response")
				return
			}

			var user struct {
				ID          string                 `json:"id"`
				UserMetadata map[string]interface{} `json:"user_metadata"`
			}
			if err := json.Unmarshal(body, &user); err != nil || user.ID == "" {
				writeMiddlewareError(w, http.StatusUnauthorized, "AUTH_PARSE", "Invalid user data")
				return
			}

			// Extract under-13 flag from user metadata
			isUnder13 := false
			if val, ok := user.UserMetadata["is_under_13"].(bool); ok {
				isUnder13 = val
			}

			// Set user context for downstream handlers
			ctx := context.WithValue(r.Context(), ably.UserIDKey(), user.ID)
			ctx = context.WithValue(ctx, ably.IsUnder13Key(), isUnder13)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// RequireAge13Plus blocks under-13 users from accessing chat features.
// Per PRD §7.3, chat is disabled entirely for the under-13 user flow.
func RequireAge13Plus() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			isUnder13, _ := r.Context().Value(ably.IsUnder13Key()).(bool)
			if isUnder13 {
				writeMiddlewareError(w, http.StatusForbidden, "AGE_RESTRICTED",
					"Chat features are not available for users under 13")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// RateLimit implements a token bucket rate limiter per user.
// PRD §6.2: authenticated users get 120 req/min, guests 30 req/min.
func RateLimit(maxTokens int, refillPerMinute int) func(http.Handler) http.Handler {
	type bucket struct {
		tokens    float64
		lastCheck time.Time
		mu        sync.Mutex
	}

	var (
		buckets sync.Map
	)

	// Periodic cleanup of stale buckets (every 5 minutes)
	go func() {
		ticker := time.NewTicker(5 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			cutoff := time.Now().Add(-10 * time.Minute)
			buckets.Range(func(key, value interface{}) bool {
				b := value.(*bucket)
				b.mu.Lock()
				if b.lastCheck.Before(cutoff) {
					buckets.Delete(key)
				}
				b.mu.Unlock()
				return true
			})
		}
	}()

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Use user ID if available, fall back to IP
			key := r.RemoteAddr
			if uid, ok := r.Context().Value(ably.UserIDKey()).(string); ok && uid != "" {
				key = uid
			}

			val, _ := buckets.LoadOrStore(key, &bucket{
				tokens:    float64(maxTokens),
				lastCheck: time.Now(),
			})
			b := val.(*bucket)

			b.mu.Lock()
			now := time.Now()
			elapsed := now.Sub(b.lastCheck).Minutes()
			b.tokens += elapsed * float64(refillPerMinute)
			if b.tokens > float64(maxTokens) {
				b.tokens = float64(maxTokens)
			}
			b.lastCheck = now

			if b.tokens < 1 {
				b.mu.Unlock()
				w.Header().Set("Retry-After", "60")
				writeMiddlewareError(w, http.StatusTooManyRequests, "RATE_LIMITED",
					fmt.Sprintf("Rate limit exceeded. Max %d requests per minute.", maxTokens))
				return
			}
			b.tokens--
			b.mu.Unlock()

			next.ServeHTTP(w, r)
		})
	}
}

func writeMiddlewareError(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]string{
		"error": message,
		"code":  code,
	})
}
