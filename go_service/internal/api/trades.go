package api

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/trades"
)

// TradeHandler serves the inventory lock and trade execution endpoints.
type TradeHandler struct {
	locker   trades.InventoryLocker
	executor trades.TradeExecutor
}

// NewTradeHandler creates a handler with the given InventoryLocker and TradeExecutor.
func NewTradeHandler(locker trades.InventoryLocker, executor trades.TradeExecutor) *TradeHandler {
	return &TradeHandler{locker: locker, executor: executor}
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

// executeTradeRequest is the expected JSON body for POST /api/v1/trades.
type executeTradeRequest struct {
	MatchID             string `json:"match_id"`
	InitiatorStickerIDs []int  `json:"initiator_sticker_ids"`
	ResponderStickerIDs []int  `json:"responder_sticker_ids"`
	IdempotencyKey      string `json:"idempotency_key"`
}

// Execute handles POST /api/v1/trades
//
// Executes an atomic trade: verify locks, transfer stickers, record audit,
// update match status, release locks. Idempotent by idempotency_key.
func (h *TradeHandler) Execute(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(ably.UserIDKey()).(string)
	if !ok || userID == "" {
		writeMatchError(w, http.StatusUnauthorized, "AUTH_REQUIRED", "User ID not found in token")
		return
	}

	var req executeTradeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeMatchError(w, http.StatusBadRequest, "INVALID_BODY", "Request body must be valid JSON")
		return
	}

	if req.MatchID == "" || !uuidRegex.MatchString(req.MatchID) {
		writeMatchError(w, http.StatusBadRequest, "INVALID_PARAMS", "match_id must be a valid UUID")
		return
	}

	if req.IdempotencyKey == "" || !uuidRegex.MatchString(req.IdempotencyKey) {
		writeMatchError(w, http.StatusBadRequest, "INVALID_PARAMS", "idempotency_key must be a valid UUID")
		return
	}

	if len(req.InitiatorStickerIDs) == 0 {
		writeMatchError(w, http.StatusBadRequest, "INVALID_PARAMS", "initiator_sticker_ids must not be empty")
		return
	}

	if len(req.ResponderStickerIDs) == 0 {
		writeMatchError(w, http.StatusBadRequest, "INVALID_PARAMS", "responder_sticker_ids must not be empty")
		return
	}

	tradeReq := trades.TradeRequest{
		MatchID:             req.MatchID,
		InitiatorStickerIDs: req.InitiatorStickerIDs,
		ResponderStickerIDs: req.ResponderStickerIDs,
		IdempotencyKey:      req.IdempotencyKey,
	}

	result, err := h.executor.ExecuteTrade(r.Context(), userID, tradeReq)
	if err != nil {
		slog.Error("Failed to execute trade",
			"error", err,
			"user_id", userID,
			"match_id", req.MatchID,
		)
		writeMatchError(w, http.StatusInternalServerError, "TRADE_ERROR", "Failed to execute trade")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if !result.Success {
		w.WriteHeader(http.StatusConflict)
	}
	json.NewEncoder(w).Encode(result)
}
