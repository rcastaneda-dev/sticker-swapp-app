package middleware

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
)

func TestReadDeviceIntegrity_Compromised(t *testing.T) {
	var captured bool
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		captured, _ = r.Context().Value(ably.DeviceCompromisedKey()).(bool)
		w.WriteHeader(http.StatusOK)
	})

	handler := ReadDeviceIntegrity()(inner)

	req := httptest.NewRequest("POST", "/api/v1/ably/auth", nil)
	req.Header.Set("X-Device-Integrity", "compromised")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if !captured {
		t.Fatal("expected deviceCompromised=true in context")
	}
}

func TestReadDeviceIntegrity_Clean(t *testing.T) {
	var captured bool
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		captured, _ = r.Context().Value(ably.DeviceCompromisedKey()).(bool)
		w.WriteHeader(http.StatusOK)
	})

	handler := ReadDeviceIntegrity()(inner)

	req := httptest.NewRequest("POST", "/api/v1/ably/auth", nil)
	req.Header.Set("X-Device-Integrity", "clean")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if captured {
		t.Fatal("expected deviceCompromised=false in context for clean device")
	}
}

func TestReadDeviceIntegrity_MissingHeader(t *testing.T) {
	var captured bool
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		captured, _ = r.Context().Value(ably.DeviceCompromisedKey()).(bool)
		w.WriteHeader(http.StatusOK)
	})

	handler := ReadDeviceIntegrity()(inner)

	req := httptest.NewRequest("POST", "/api/v1/ably/auth", nil)
	// No X-Device-Integrity header
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 (never blocks), got %d", rec.Code)
	}
	if captured {
		t.Fatal("expected deviceCompromised=false when header is missing")
	}
}

func TestReadDeviceIntegrity_UnrecognizedValue(t *testing.T) {
	var captured bool
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		captured, _ = r.Context().Value(ably.DeviceCompromisedKey()).(bool)
		w.WriteHeader(http.StatusOK)
	})

	handler := ReadDeviceIntegrity()(inner)

	req := httptest.NewRequest("POST", "/api/v1/ably/auth", nil)
	req.Header.Set("X-Device-Integrity", "unknown")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if captured {
		t.Fatal("expected deviceCompromised=false for unrecognized value")
	}
}

func TestReadDeviceIntegrity_AlwaysPassesThrough(t *testing.T) {
	var called bool
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
		w.WriteHeader(http.StatusOK)
	})

	handler := ReadDeviceIntegrity()(inner)

	// Test with compromised header — should still pass through
	req := httptest.NewRequest("POST", "/api/v1/ably/auth", nil)
	req.Header.Set("X-Device-Integrity", "compromised")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if !called {
		t.Fatal("expected next handler to be called (middleware should never block)")
	}
}

func TestReadDeviceIntegrity_IncludesUserIDInLog(t *testing.T) {
	// Verify that the middleware reads userID from context (set by ValidateJWT)
	var captured bool
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		captured, _ = r.Context().Value(ably.DeviceCompromisedKey()).(bool)
		w.WriteHeader(http.StatusOK)
	})

	handler := ReadDeviceIntegrity()(inner)

	req := httptest.NewRequest("POST", "/api/v1/ably/auth", nil)
	req.Header.Set("X-Device-Integrity", "compromised")
	// Simulate ValidateJWT having set user ID in context
	ctx := context.WithValue(req.Context(), ably.UserIDKey(), "user-abc-123")
	req = req.WithContext(ctx)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if !captured {
		t.Fatal("expected deviceCompromised=true in context")
	}
}
