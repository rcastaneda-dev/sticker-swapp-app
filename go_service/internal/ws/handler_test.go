package ws

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"nhooyr.io/websocket"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
)

func TestHandler_Upgrade_Success(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cfg := testConfig()
	m := NewManager(cfg)
	h := NewHandler(m, cfg, ctx)

	// Create a test server with the handler
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Simulate middleware: set userID in context
		rctx := context.WithValue(r.Context(), ably.UserIDKey(), "user-42")
		h.Upgrade(w, r.WithContext(rctx))
	}))
	defer srv.Close()

	client, _, err := websocket.Dial(ctx, srv.URL, nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer client.Close(websocket.StatusNormalClosure, "")

	// Give the handler time to register
	time.Sleep(50 * time.Millisecond)

	if m.Len() != 1 {
		t.Fatalf("expected 1 connection, got %d", m.Len())
	}
	if m.Get("user-42") == nil {
		t.Fatal("expected connection for user-42")
	}
}

func TestHandler_Upgrade_MissingAuth(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cfg := testConfig()
	m := NewManager(cfg)
	h := NewHandler(m, cfg, ctx)

	// No userID in context
	rec := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/api/v1/ws", nil)
	h.Upgrade(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}

	var body struct {
		Code string `json:"code"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("parse response: %v", err)
	}
	if body.Code != "AUTH_REQUIRED" {
		t.Fatalf("expected AUTH_REQUIRED, got %q", body.Code)
	}

	if m.Len() != 0 {
		t.Fatalf("expected 0 connections, got %d", m.Len())
	}
}
