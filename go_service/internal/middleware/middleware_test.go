package middleware

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
)

// --- ValidateJWT Tests ---

func TestValidateJWT_MissingHeader(t *testing.T) {
	handler := ValidateJWT("http://unused", "unused-key")(okHandler())

	req := httptest.NewRequest("GET", "/test", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
	assertErrorCode(t, rec, "AUTH_MISSING")
}

func TestValidateJWT_MalformedHeader(t *testing.T) {
	handler := ValidateJWT("http://unused", "unused-key")(okHandler())

	req := httptest.NewRequest("GET", "/test", nil)
	req.Header.Set("Authorization", "Token invalid-format")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
	assertErrorCode(t, rec, "AUTH_MISSING")
}

func TestValidateJWT_InvalidToken(t *testing.T) {
	// Mock Supabase returning 401 for invalid token
	supabase := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		w.Write([]byte(`{"error":"invalid_token"}`))
	}))
	defer supabase.Close()

	handler := ValidateJWT(supabase.URL, "service-key")(okHandler())

	req := httptest.NewRequest("GET", "/test", nil)
	req.Header.Set("Authorization", "Bearer expired-or-invalid-jwt")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
	assertErrorCode(t, rec, "AUTH_INVALID")
}

func TestValidateJWT_ValidToken(t *testing.T) {
	// Mock Supabase returning a valid user
	supabase := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer valid-jwt-token" {
			t.Error("token not forwarded correctly")
		}
		if r.Header.Get("apikey") != "test-service-key" {
			t.Error("apikey not forwarded correctly")
		}
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"id":            "user-abc-123",
			"user_metadata": map[string]interface{}{},
		})
	}))
	defer supabase.Close()

	var capturedUserID string
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedUserID, _ = r.Context().Value(ably.UserIDKey()).(string)
		w.WriteHeader(http.StatusOK)
	})

	handler := ValidateJWT(supabase.URL, "test-service-key")(inner)

	req := httptest.NewRequest("GET", "/test", nil)
	req.Header.Set("Authorization", "Bearer valid-jwt-token")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if capturedUserID != "user-abc-123" {
		t.Fatalf("expected user ID 'user-abc-123', got %q", capturedUserID)
	}
}

func TestValidateJWT_Under13Flag(t *testing.T) {
	supabase := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"id": "child-user-456",
			"user_metadata": map[string]interface{}{
				"is_under_13": true,
			},
		})
	}))
	defer supabase.Close()

	var capturedIsUnder13 bool
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedIsUnder13, _ = r.Context().Value(ably.IsUnder13Key()).(bool)
		w.WriteHeader(http.StatusOK)
	})

	handler := ValidateJWT(supabase.URL, "key")(inner)

	req := httptest.NewRequest("GET", "/test", nil)
	req.Header.Set("Authorization", "Bearer child-jwt")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if !capturedIsUnder13 {
		t.Fatal("expected is_under_13 to be true in context")
	}
}

// --- RequireAge13Plus Tests ---

func TestRequireAge13Plus_AllowsAdult(t *testing.T) {
	inner := okHandler()
	handler := RequireAge13Plus()(inner)

	req := httptest.NewRequest("GET", "/test", nil)
	ctx := context.WithValue(req.Context(), ably.IsUnder13Key(), false)
	req = req.WithContext(ctx)

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for adult user, got %d", rec.Code)
	}
}

func TestRequireAge13Plus_BlocksChild(t *testing.T) {
	inner := okHandler()
	handler := RequireAge13Plus()(inner)

	req := httptest.NewRequest("GET", "/test", nil)
	ctx := context.WithValue(req.Context(), ably.IsUnder13Key(), true)
	req = req.WithContext(ctx)

	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for under-13 user, got %d", rec.Code)
	}
	assertErrorCode(t, rec, "AGE_RESTRICTED")
}

// --- RateLimit Tests ---

func TestRateLimit_AllowsWithinLimit(t *testing.T) {
	handler := RateLimit(5, 5)(okHandler())

	for i := 0; i < 5; i++ {
		req := httptest.NewRequest("GET", "/test", nil)
		req.RemoteAddr = "192.168.1.1:1234"
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("request %d: expected 200, got %d", i+1, rec.Code)
		}
	}
}

func TestRateLimit_BlocksOverLimit(t *testing.T) {
	handler := RateLimit(3, 3)(okHandler())

	// Exhaust the bucket
	for i := 0; i < 3; i++ {
		req := httptest.NewRequest("GET", "/test", nil)
		req.RemoteAddr = "10.0.0.1:5678"
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
	}

	// This one should be rate limited
	req := httptest.NewRequest("GET", "/test", nil)
	req.RemoteAddr = "10.0.0.1:5678"
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("expected 429, got %d", rec.Code)
	}
	if rec.Header().Get("Retry-After") != "60" {
		t.Fatalf("expected Retry-After: 60, got %q", rec.Header().Get("Retry-After"))
	}
	assertErrorCode(t, rec, "RATE_LIMITED")
}

func TestRateLimit_PerUserIsolation(t *testing.T) {
	handler := RateLimit(2, 2)(okHandler())

	// User A exhausts their bucket
	for i := 0; i < 2; i++ {
		req := httptest.NewRequest("GET", "/test", nil)
		req.RemoteAddr = fmt.Sprintf("user-a:%d", i)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
	}

	// User B should still have tokens
	req := httptest.NewRequest("GET", "/test", nil)
	req.RemoteAddr = "user-b:1"
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for different user, got %d", rec.Code)
	}
}
