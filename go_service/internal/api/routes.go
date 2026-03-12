package api

import (
	"github.com/go-chi/chi/v5"
	chiMiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/middleware"
)

// RouterConfig holds all dependencies needed to register routes.
type RouterConfig struct {
	Pool           *pgxpool.Pool
	AblyHandler    *ably.TokenHandler
	SupabaseURL    string
	SupabaseSecret string
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
	r.Route("/api/v1", func(r chi.Router) {
		r.With(
			middleware.RateLimit(120, 60),
			middleware.ValidateJWT(cfg.SupabaseURL, cfg.SupabaseSecret),
			middleware.RequireAge13Plus(),
		).Post("/ably/auth", cfg.AblyHandler.IssueToken)
	})

	return r
}
