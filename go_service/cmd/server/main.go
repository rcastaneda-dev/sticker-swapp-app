package main

import (
	"log"
	"net/http"
	"os"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/middleware"
)

func main() {
	// Load configuration from environment
	cfg := ably.Config{
		APIKey:     requireEnv("ABLY_API_KEY"),      // e.g. "appId.keyId:keySecret"
		SupabaseURL:    requireEnv("SUPABASE_URL"),
		SupabaseSecret: requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
	}

	tokenHandler := ably.NewTokenHandler(cfg)

	mux := http.NewServeMux()

	// Token auth endpoint — called by Flutter client to obtain Ably tokens
	mux.Handle("POST /api/v1/ably/auth",
		middleware.Chain(
			middleware.RateLimit(120, 60), // 120 req/min for authenticated users (PRD §6.2)
			middleware.ValidateJWT(cfg.SupabaseURL, cfg.SupabaseSecret),
			middleware.RequireAge13Plus(),  // Under-13 users cannot access chat (PRD §7.3)
		)(http.HandlerFunc(tokenHandler.IssueToken)),
	)

	// Health check for Cloud Run
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"ok"}`))
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Ably token auth service starting on :%s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

func requireEnv(key string) string {
	val := os.Getenv(key)
	if val == "" {
		log.Fatalf("Required environment variable %s is not set", key)
	}
	return val
}
