package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/api"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/db"
)

func main() {
	// Root context with signal-based cancellation
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// Load configuration
	ablyCfg := ably.Config{
		APIKey:         requireEnv("ABLY_API_KEY"),
		SupabaseURL:    requireEnv("SUPABASE_URL"),
		SupabaseSecret: requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
	}
	dbURL := requireEnv("SUPABASE_DB_URL")

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Initialize database pool
	pool, err := db.NewPool(ctx, dbURL)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer pool.Close()
	log.Println("Database pool connected")

	// Build handler dependencies
	tokenHandler := ably.NewTokenHandler(ablyCfg)

	router := api.NewRouter(api.RouterConfig{
		Pool:           pool,
		AblyHandler:    tokenHandler,
		SupabaseURL:    ablyCfg.SupabaseURL,
		SupabaseSecret: ablyCfg.SupabaseSecret,
	})

	// Start HTTP server
	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      router,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		log.Printf("Server starting on :%s", port)
		errCh <- srv.ListenAndServe()
	}()

	// Wait for shutdown signal or server error
	select {
	case <-ctx.Done():
		log.Println("Shutdown signal received, draining connections...")
	case err := <-errCh:
		if err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed: %v", err)
		}
	}

	// Graceful shutdown with 10-second deadline
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Fatalf("Graceful shutdown failed: %v", err)
	}
	log.Println("Server stopped gracefully")
}

func requireEnv(key string) string {
	val := os.Getenv(key)
	if val == "" {
		log.Fatalf("Required environment variable %s is not set", key)
	}
	return val
}
