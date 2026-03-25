package api

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/matchmaking"
)

// MatchmakingHandler serves the scored match discovery endpoint.
type MatchmakingHandler struct {
	scorer matchmaking.Scorer
	cache  *matchmaking.Cache
}

// NewMatchmakingHandler creates a handler with the given scorer and cache.
func NewMatchmakingHandler(scorer matchmaking.Scorer, cache *matchmaking.Cache) *MatchmakingHandler {
	return &MatchmakingHandler{scorer: scorer, cache: cache}
}

// ListMatches handles GET /api/v1/matches?lat=X&lng=Y&radius=Z
//
// Returns a JSON array of scored matches sorted by total_score descending.
// Results are cached per-user for 60 seconds.
func (h *MatchmakingHandler) ListMatches(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(ably.UserIDKey()).(string)
	if !ok || userID == "" {
		writeMatchError(w, http.StatusUnauthorized, "AUTH_REQUIRED", "User ID not found in token")
		return
	}

	latStr := r.URL.Query().Get("lat")
	lngStr := r.URL.Query().Get("lng")
	if latStr == "" || lngStr == "" {
		writeMatchError(w, http.StatusBadRequest, "INVALID_PARAMS", "lat and lng query parameters are required")
		return
	}

	lat, err := strconv.ParseFloat(latStr, 64)
	if err != nil || lat < -90 || lat > 90 {
		writeMatchError(w, http.StatusBadRequest, "INVALID_PARAMS", "lat must be a valid latitude (-90 to 90)")
		return
	}

	lng, err := strconv.ParseFloat(lngStr, 64)
	if err != nil || lng < -180 || lng > 180 {
		writeMatchError(w, http.StatusBadRequest, "INVALID_PARAMS", "lng must be a valid longitude (-180 to 180)")
		return
	}

	radiusM := 5000
	if radiusStr := r.URL.Query().Get("radius"); radiusStr != "" {
		parsed, err := strconv.Atoi(radiusStr)
		if err != nil || parsed < 1 || parsed > 50000 {
			writeMatchError(w, http.StatusBadRequest, "INVALID_PARAMS", "radius must be between 1 and 50000 meters")
			return
		}
		radiusM = parsed
	}

	// Check cache
	if cached, hit := h.cache.Get(userID); hit {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("X-Cache", "HIT")
		json.NewEncoder(w).Encode(cached)
		return
	}

	// Compute scores
	results, err := h.scorer.ScoreMatches(r.Context(), userID, lat, lng, radiusM)
	if err != nil {
		writeMatchError(w, http.StatusInternalServerError, "MATCHMAKING_ERROR", "Failed to compute matches")
		return
	}

	// Cache and respond
	h.cache.Set(userID, results)

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("X-Cache", "MISS")
	json.NewEncoder(w).Encode(results)
}

// writeMatchError writes a JSON error response.
func writeMatchError(w http.ResponseWriter, status int, code, message string) {
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
