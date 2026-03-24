package middleware

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
)

func newTradeRequest(userID string, compromised bool) *http.Request {
	req := httptest.NewRequest("POST", "/api/v1/trades", nil)
	ctx := context.WithValue(req.Context(), ably.UserIDKey(), userID)
	ctx = context.WithValue(ctx, ably.DeviceCompromisedKey(), compromised)
	return req.WithContext(ctx)
}

func TestTradeLimiter_AllowsWithinNormalLimit(t *testing.T) {
	cfg := TradeLimiterConfig{
		NormalMaxTrades:      5,
		CompromisedMaxTrades: 2,
		WindowMinutes:        60,
	}
	handler := TradeLimiter(cfg)(okHandler())

	for i := 0; i < 5; i++ {
		req := newTradeRequest("user-clean", false)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("trade %d: expected 200, got %d", i+1, rec.Code)
		}
	}
}

func TestTradeLimiter_BlocksOverNormalLimit(t *testing.T) {
	cfg := TradeLimiterConfig{
		NormalMaxTrades:      3,
		CompromisedMaxTrades: 1,
		WindowMinutes:        60,
	}
	handler := TradeLimiter(cfg)(okHandler())

	// Exhaust normal limit
	for i := 0; i < 3; i++ {
		req := newTradeRequest("user-over", false)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
	}

	// 4th trade should be blocked
	req := newTradeRequest("user-over", false)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429, got %d", rec.Code)
	}
	assertErrorCode(t, rec, "TRADE_LIMIT_EXCEEDED")
}

func TestTradeLimiter_AllowsWithinCompromisedLimit(t *testing.T) {
	cfg := TradeLimiterConfig{
		NormalMaxTrades:      10,
		CompromisedMaxTrades: 3,
		WindowMinutes:        60,
	}
	handler := TradeLimiter(cfg)(okHandler())

	for i := 0; i < 3; i++ {
		req := newTradeRequest("user-rooted", true)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("trade %d: expected 200, got %d", i+1, rec.Code)
		}
	}
}

func TestTradeLimiter_BlocksOverCompromisedLimit(t *testing.T) {
	cfg := TradeLimiterConfig{
		NormalMaxTrades:      10,
		CompromisedMaxTrades: 2,
		WindowMinutes:        60,
	}
	handler := TradeLimiter(cfg)(okHandler())

	// Exhaust compromised limit
	for i := 0; i < 2; i++ {
		req := newTradeRequest("user-rooted-2", true)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
	}

	// 3rd trade should be blocked
	req := newTradeRequest("user-rooted-2", true)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429, got %d", rec.Code)
	}
	assertErrorCode(t, rec, "TRADE_LIMIT_EXCEEDED")
}

func TestTradeLimiter_RejectsUnauthenticated(t *testing.T) {
	cfg := DefaultTradeLimiterConfig()
	handler := TradeLimiter(cfg)(okHandler())

	// No user ID in context
	req := httptest.NewRequest("POST", "/api/v1/trades", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
	assertErrorCode(t, rec, "AUTH_REQUIRED")
}

func TestTradeLimiter_PerUserIsolation(t *testing.T) {
	cfg := TradeLimiterConfig{
		NormalMaxTrades:      2,
		CompromisedMaxTrades: 1,
		WindowMinutes:        60,
	}
	handler := TradeLimiter(cfg)(okHandler())

	// User A exhausts their limit
	for i := 0; i < 2; i++ {
		req := newTradeRequest("user-a", false)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
	}

	// User B should still have trades available
	req := newTradeRequest("user-b", false)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for different user, got %d", rec.Code)
	}
}

func TestTradeLimiter_RetryAfterHeader(t *testing.T) {
	cfg := TradeLimiterConfig{
		NormalMaxTrades:      1,
		CompromisedMaxTrades: 1,
		WindowMinutes:        60,
	}
	handler := TradeLimiter(cfg)(okHandler())

	// Exhaust limit
	req := newTradeRequest("user-retry", false)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	// Next request should have Retry-After
	req = newTradeRequest("user-retry", false)
	rec = httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429, got %d", rec.Code)
	}
	if rec.Header().Get("Retry-After") != "3600" {
		t.Fatalf("expected Retry-After: 3600, got %q", rec.Header().Get("Retry-After"))
	}
}
