package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/api"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/attestation"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/db"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/matches"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/matchmaking"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/onesignal"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/trades"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ws"
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
	participantChecker := matches.NewParticipantChecker(pool)
	tokenHandler := ably.NewTokenHandler(ablyCfg, participantChecker)

	// Attestation verifier — optional env vars for dev flexibility
	googleProjectNumber := os.Getenv("GOOGLE_CLOUD_PROJECT_NUMBER")
	appleAppID := os.Getenv("APPLE_APP_ID")
	attestationDisabled := strings.EqualFold(os.Getenv("ATTESTATION_DISABLED"), "true")
	if attestationDisabled {
		log.Println("WARNING: Attestation verification is DISABLED (dev mode)")
	}
	attVerifier := attestation.NewVerifier(googleProjectNumber, appleAppID)

	// Initialize matchmaking engine
	matchScorer := matchmaking.NewScorer(pool, matchmaking.DefaultConfig())
	matchCache := matchmaking.NewCache(matchmaking.DefaultCacheConfig())
	defer matchCache.Stop()

	// Initialize match creator
	matchCreator := matches.NewMatchCreator(pool)

	// Initialize inventory locker
	inventoryLocker := trades.NewInventoryLocker(pool)

	// Initialize push notifications — optional (NoopNotifier if credentials missing)
	var pushNotifier onesignal.Notifier
	onesignalAppID := os.Getenv("ONESIGNAL_APP_ID")
	onesignalAPIKey := os.Getenv("ONESIGNAL_REST_API_KEY")
	if onesignalAppID != "" && onesignalAPIKey != "" {
		pushNotifier = onesignal.NewPushNotifier(onesignal.Config{
			AppID:      onesignalAppID,
			RestAPIKey: onesignalAPIKey,
		})
		log.Println("OneSignal push notifications enabled")
	} else {
		pushNotifier = &onesignal.NoopNotifier{}
		log.Println("OneSignal push notifications DISABLED (missing credentials)")
	}

	// Initialize Ably REST publisher for server-side channel events
	var ablyPublisher ably.Publisher
	ablyPub, err := ably.NewRESTPublisher(ablyCfg.APIKey)
	if err != nil {
		log.Printf("WARNING: Ably REST publisher init failed: %v (using noop)", err)
		ablyPublisher = &ably.NoopPublisher{}
	} else {
		ablyPublisher = ablyPub
		log.Println("Ably REST publisher enabled")
	}

	// Initialize WebSocket connection manager
	wsCfg := ws.DefaultConfig()
	wsManager := ws.NewManager(wsCfg)
	wsHandler := ws.NewHandler(wsManager, wsCfg, ctx)

	router := api.NewRouter(api.RouterConfig{
		Pool:                pool,
		AblyHandler:         tokenHandler,
		SupabaseURL:         ablyCfg.SupabaseURL,
		SupabaseSecret:      ablyCfg.SupabaseSecret,
		AttestationVerifier: attVerifier,
		AttestationDisabled: attestationDisabled,
		Scorer:              matchScorer,
		MatchCache:          matchCache,
		WSHandler:           wsHandler,
		MatchCreator:        matchCreator,
		PushNotifier:        pushNotifier,
		DisplayNames:        &api.DBDisplayNameLookup{Pool: pool},
		AblyPublisher:       ablyPublisher,
		InventoryLocker:     inventoryLocker,
	})

	// Start HTTP server
	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      router,
		ReadTimeout: 10 * time.Second,
		// WriteTimeout disabled (0) to support WebSocket connections.
		// REST handler writes complete quickly; WS writes use per-op timeouts.
		IdleTimeout: 60 * time.Second,
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

	// Shut down WebSocket connections first (while HTTP server still running)
	wsShutdownCtx, wsCancel := context.WithTimeout(context.Background(), wsCfg.ShutdownGracePeriod)
	wsManager.Shutdown(wsShutdownCtx)
	wsCancel()

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
