package api

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/trades"
)

// TradeHandler serves the inventory lock endpoints.
type TradeHandler struct {
	locker trades.InventoryLocker
}

// NewTradeHandler creates a handler with the given InventoryLocker.
func NewTradeHandler(locker trades.InventoryLocker) *TradeHandler {
	return &TradeHandler{locker: locker}
}

// LockInventory handles POST /api/v1/matches/{matchId}/lock
//
// Locks the caller's DUPLICATE stickers for the given match.
// Returns the locked sticker IDs and expiry time.
func (h *TradeHandler) LockInventory(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(ably.UserIDKey()).(string)
	if !ok || userID == "" {
		writeMatchError(w, http.StatusUnauthorized, "AUTH_REQUIRED", "User ID not found in token")
		return
	}

	matchID := chi.URLParam(r, "matchId")
	if matchID == "" || !uuidRegex.MatchString(matchID) {
		writeMatchError(w, http.StatusBadRequest, "INVALID_PARAMS", "matchId must be a valid UUID")
		return
	}

	result, err := h.locker.LockForTrade(r.Context(), userID, matchID)
	if err != nil {
		slog.Error("Failed to lock inventory",
			"error", err,
			"user_id", userID,
			"match_id", matchID,
		)
		writeMatchError(w, http.StatusInternalServerError, "LOCK_ERROR", "Failed to lock inventory")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if !result.Success {
		w.WriteHeader(http.StatusConflict)
	}
	json.NewEncoder(w).Encode(result)
}

// ReleaseInventory handles DELETE /api/v1/matches/{matchId}/lock
//
// Releases all active locks for the given match with MANUAL_RELEASE reason.
func (h *TradeHandler) ReleaseInventory(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(ably.UserIDKey()).(string)
	if !ok || userID == "" {
		writeMatchError(w, http.StatusUnauthorized, "AUTH_REQUIRED", "User ID not found in token")
		return
	}

	matchID := chi.URLParam(r, "matchId")
	if matchID == "" || !uuidRegex.MatchString(matchID) {
		writeMatchError(w, http.StatusBadRequest, "INVALID_PARAMS", "matchId must be a valid UUID")
		return
	}

	result, err := h.locker.ReleaseLocks(r.Context(), matchID, "MANUAL_RELEASE")
	if err != nil {
		slog.Error("Failed to release inventory locks",
			"error", err,
			"user_id", userID,
			"match_id", matchID,
		)
		writeMatchError(w, http.StatusInternalServerError, "RELEASE_ERROR", "Failed to release locks")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}
