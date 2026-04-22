package api

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/trades"
)

// ConfirmHandler serves the trade confirmation endpoints.
type ConfirmHandler struct {
	confirmer trades.TradeConfirmer
	publisher ably.Publisher
}

// NewConfirmHandler creates a handler with the given TradeConfirmer and Ably Publisher.
func NewConfirmHandler(confirmer trades.TradeConfirmer, publisher ably.Publisher) *ConfirmHandler {
	return &ConfirmHandler{confirmer: confirmer, publisher: publisher}
}

// ConfirmTrade handles POST /api/v1/matches/{matchId}/confirm
//
// Records the caller's trade confirmation. When both participants have
// confirmed, the match transitions to COMPLETED.
func (h *ConfirmHandler) ConfirmTrade(w http.ResponseWriter, r *http.Request) {
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

	result, err := h.confirmer.ConfirmTrade(r.Context(), userID, matchID)
	if err != nil {
		slog.Error("Failed to confirm trade",
			"error", err,
			"user_id", userID,
			"match_id", matchID,
		)
		writeMatchError(w, http.StatusInternalServerError, "CONFIRM_ERROR", "Failed to confirm trade")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if !result.Success {
		w.WriteHeader(http.StatusConflict)
		json.NewEncoder(w).Encode(result)
		return
	}

	// Publish real-time event asynchronously
	go h.publishTradeConfirmed(userID, matchID, result)

	json.NewEncoder(w).Encode(result)
}

// GetConfirmationState handles GET /api/v1/matches/{matchId}/confirm
//
// Returns the current confirmation state for a match.
func (h *ConfirmHandler) GetConfirmationState(w http.ResponseWriter, r *http.Request) {
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

	result, err := h.confirmer.GetConfirmationState(r.Context(), userID, matchID)
	if err != nil {
		slog.Error("Failed to get confirmation state",
			"error", err,
			"user_id", userID,
			"match_id", matchID,
		)
		writeMatchError(w, http.StatusInternalServerError, "CONFIRM_ERROR", "Failed to get confirmation state")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if !result.Success {
		w.WriteHeader(http.StatusConflict)
	}
	json.NewEncoder(w).Encode(result)
}

// publishTradeConfirmed publishes a trade.confirmed event to the match Ably channel.
func (h *ConfirmHandler) publishTradeConfirmed(userID, matchID string, result *trades.ConfirmResult) {
	event := ably.TradeConfirmedEvent{
		MatchID:       matchID,
		ConfirmedBy:   userID,
		BothConfirmed: result.BothConfirmed,
		MatchStatus:   result.MatchStatus,
	}

	ctx := context.Background()
	if err := h.publisher.PublishTradeConfirmed(ctx, matchID, event); err != nil {
		slog.Warn("Failed to publish trade.confirmed event",
			"error", err,
			"match_id", matchID,
			"confirmed_by", userID,
		)
	}
}
