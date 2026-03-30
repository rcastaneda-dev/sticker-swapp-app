package ws

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"

	"nhooyr.io/websocket"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
)

// Handler upgrades HTTP requests to WebSocket connections.
type Handler struct {
	manager  *Manager
	cfg      Config
	lifetime context.Context // server lifetime context
}

// NewHandler creates a WebSocket upgrade handler.
func NewHandler(manager *Manager, cfg Config, lifetime context.Context) *Handler {
	return &Handler{
		manager:  manager,
		cfg:      cfg,
		lifetime: lifetime,
	}
}

// Upgrade handles GET /api/v1/ws — upgrades to WebSocket and registers
// with the Manager. Requires ValidateJWT middleware upstream.
func (h *Handler) Upgrade(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(ably.UserIDKey()).(string)
	if !ok || userID == "" {
		writeWSError(w, http.StatusUnauthorized, "AUTH_REQUIRED", "User ID not found in token")
		return
	}

	ws, err := websocket.Accept(w, r, &websocket.AcceptOptions{})
	if err != nil {
		slog.Error("ws upgrade failed",
			"user_id", userID,
			"error", err,
		)
		return
	}

	if !h.manager.Add(h.lifetime, userID, ws, nil) {
		return
	}

	slog.Info("ws connection established",
		"user_id", userID,
		"remote_addr", r.RemoteAddr,
	)
}

func writeWSError(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(struct {
		Error string `json:"error"`
		Code  string `json:"code"`
	}{
		Error: message,
		Code:  code,
	})
}
