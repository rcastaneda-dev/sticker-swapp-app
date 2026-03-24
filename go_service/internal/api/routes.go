package api

import (
	"github.com/go-chi/chi/v5"
	chiMiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/attestation"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/middleware"
)

// RouterConfig holds all dependencies needed to register routes.
type RouterConfig struct {
	Pool                 *pgxpool.Pool
	AblyHandler          *ably.TokenHandler
	SupabaseURL          string
	SupabaseSecret       string
	AttestationVerifier  attestation.IntegrityChecker
	AttestationDisabled  bool
}

// NewRouter constructs a Chi router with all routes and middleware.
func NewRouter(cfg RouterConfig) chi.Router {
	r := chi.NewRouter()

	// Global middleware
	r.Use(chiMiddleware.RequestID)
	r.Use(chiMiddleware.RealIP)
	r.Use(chiMiddleware.Logger)
	r.Use(chiMiddleware.Recoverer)

	// Health check — no auth, no rate limit
	health := NewHealthHandler(cfg.Pool)
	r.Get("/healthz", health.Check)

	// Ably token auth — with full middleware chain
	// Order: RateLimit → VerifyAttestation → ValidateJWT → ReadDeviceIntegrity → RequireAge13Plus
	r.Route("/api/v1", func(r chi.Router) {
		r.With(
			middleware.RateLimit(120, 60),
			middleware.VerifyAttestation(cfg.AttestationVerifier, cfg.AttestationDisabled),
			middleware.ValidateJWT(cfg.SupabaseURL, cfg.SupabaseSecret),
			middleware.ReadDeviceIntegrity(),
			middleware.RequireAge13Plus(),
		).Post("/ably/auth", cfg.AblyHandler.IssueToken)

		// Future trade endpoints (Phase 3):
		// r.With(
		//     middleware.RateLimit(120, 60),
		//     middleware.VerifyAttestation(cfg.AttestationVerifier, cfg.AttestationDisabled),
		//     middleware.ValidateJWT(cfg.SupabaseURL, cfg.SupabaseSecret),
		//     middleware.ReadDeviceIntegrity(),
		//     middleware.RequireAge13Plus(),
		//     middleware.TradeLimiter(middleware.DefaultTradeLimiterConfig()),
		// ).Post("/trades", tradeHandler.Execute)
	})

	return r
}
