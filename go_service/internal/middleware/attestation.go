package middleware

import (
	"net/http"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/attestation"
)

// VerifyAttestation validates device attestation tokens from the client.
//
// It reads two headers from each request:
//   - X-Attestation-Token: the platform-specific attestation token
//   - X-Attestation-Platform: "android" or "ios"
//
// When disabled is true (development mode), all requests pass through
// without attestation checks. This allows local development without
// requiring real device attestation.
func VerifyAttestation(verifier attestation.IntegrityChecker, disabled bool) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if disabled {
				next.ServeHTTP(w, r)
				return
			}

			token := r.Header.Get("X-Attestation-Token")
			platform := r.Header.Get("X-Attestation-Platform")

			if token == "" || platform == "" {
				writeMiddlewareError(w, http.StatusForbidden, "ATTESTATION_MISSING",
					"Device attestation required")
				return
			}

			var err error
			switch platform {
			case "android":
				err = verifier.VerifyAndroid(r.Context(), token)
			case "ios":
				err = verifier.VerifyIOS(r.Context(), token)
			default:
				writeMiddlewareError(w, http.StatusForbidden, "ATTESTATION_INVALID_PLATFORM",
					"Unsupported attestation platform")
				return
			}

			if err != nil {
				writeMiddlewareError(w, http.StatusForbidden, "ATTESTATION_FAILED", err.Error())
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}
