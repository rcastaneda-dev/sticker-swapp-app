package middleware

import (
	"context"
	"log/slog"
	"net/http"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
)

// ReadDeviceIntegrity reads the X-Device-Integrity header from the client
// and sets a boolean context flag for downstream handlers.
//
// This is an untrusted client-side signal used for defense-in-depth
// alongside attestation. It does NOT block requests — it only sets
// context that downstream rate limiters and trade handlers can read.
//
// Header values:
//   - "compromised": device reported as rooted/jailbroken → context true
//   - "clean": device reported as clean → context false
//   - missing/other: unknown → context false (fail open)
func ReadDeviceIntegrity() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			header := r.Header.Get("X-Device-Integrity")
			compromised := header == "compromised"

			if compromised {
				userID, _ := r.Context().Value(ably.UserIDKey()).(string)
				slog.Warn("compromised device detected",
					"user_id", userID,
					"remote_addr", r.RemoteAddr,
					"path", r.URL.Path,
					"method", r.Method,
				)
			}

			ctx := context.WithValue(r.Context(), ably.DeviceCompromisedKey(), compromised)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}
