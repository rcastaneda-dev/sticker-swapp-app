package api

import (
	"encoding/json"
	"net/http"
	"regexp"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/matches"
)

// uuidRegex validates UUID format.
var uuidRegex = regexp.MustCompile(
	`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`,
)

// MatchHandler serves the match creation endpoint.
type MatchHandler struct {
	creator matches.MatchCreator
}

// NewMatchHandler creates a handler with the given MatchCreator.
func NewMatchHandler(creator matches.MatchCreator) *MatchHandler {
	return &MatchHandler{creator: creator}
}

// createMatchRequest is the expected JSON body for POST /api/v1/matches.
type createMatchRequest struct {
	TargetUserID string `json:"target_user_id"`
}

// CreateMatch handles POST /api/v1/matches
//
// Records a right-swipe from the caller toward the target user.
// If the target has already swiped right on the caller, creates a PENDING match.
func (h *MatchHandler) CreateMatch(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(ably.UserIDKey()).(string)
	if !ok || userID == "" {
		writeMatchError(w, http.StatusUnauthorized, "AUTH_REQUIRED", "User ID not found in token")
		return
	}

	var req createMatchRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeMatchError(w, http.StatusBadRequest, "INVALID_BODY", "Request body must be valid JSON with target_user_id")
		return
	}

	if req.TargetUserID == "" {
		writeMatchError(w, http.StatusBadRequest, "INVALID_PARAMS", "target_user_id is required")
		return
	}
	if !uuidRegex.MatchString(req.TargetUserID) {
		writeMatchError(w, http.StatusBadRequest, "INVALID_PARAMS", "target_user_id must be a valid UUID")
		return
	}

	if userID == req.TargetUserID {
		writeMatchError(w, http.StatusConflict, "SELF_SWIPE", "Cannot swipe on yourself")
		return
	}

	result, err := h.creator.CreateMatchIfMutual(r.Context(), userID, req.TargetUserID)
	if err != nil {
		writeMatchError(w, http.StatusInternalServerError, "MATCH_ERROR", "Failed to process match request")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if result.Matched {
		w.WriteHeader(http.StatusCreated)
	}
	json.NewEncoder(w).Encode(result)
}
