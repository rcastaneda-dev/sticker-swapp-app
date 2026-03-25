package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/matchmaking"
)

// Compile-time interface check.
var _ matchmaking.Scorer = (*mockScorer)(nil)

type mockScorer struct {
	results []matchmaking.ScoredMatch
	err     error
	called  bool
}

func (m *mockScorer) ScoreMatches(_ context.Context, _ string, _, _ float64, _ int) ([]matchmaking.ScoredMatch, error) {
	m.called = true
	return m.results, m.err
}

func newMatchRequest(userID, lat, lng, radius string) *http.Request {
	url := "/api/v1/matches?lat=" + lat + "&lng=" + lng
	if radius != "" {
		url += "&radius=" + radius
	}
	req := httptest.NewRequest("GET", url, nil)
	if userID != "" {
		ctx := context.WithValue(req.Context(), ably.UserIDKey(), userID)
		req = req.WithContext(ctx)
	}
	return req
}

func TestListMatches_Success(t *testing.T) {
	scorer := &mockScorer{
		results: []matchmaking.ScoredMatch{
			{UserID: "u1", TotalScore: 0.9},
			{UserID: "u2", TotalScore: 0.7},
		},
	}
	cache := matchmaking.NewTestCache()
	handler := NewMatchmakingHandler(scorer, cache)

	req := newMatchRequest("caller-123", "13.69", "-89.19", "")
	rec := httptest.NewRecorder()
	handler.ListMatches(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var results []matchmaking.ScoredMatch
	if err := json.NewDecoder(rec.Body).Decode(&results); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if len(results) != 2 {
		t.Fatalf("expected 2 results, got %d", len(results))
	}
	if rec.Header().Get("X-Cache") != "MISS" {
		t.Fatalf("expected X-Cache: MISS, got %q", rec.Header().Get("X-Cache"))
	}
}

func TestListMatches_CacheHit(t *testing.T) {
	scorer := &mockScorer{
		results: []matchmaking.ScoredMatch{{UserID: "u1", TotalScore: 0.9}},
	}
	cache := matchmaking.NewTestCache()
	handler := NewMatchmakingHandler(scorer, cache)

	// First call populates cache
	req1 := newMatchRequest("caller-123", "13.69", "-89.19", "")
	rec1 := httptest.NewRecorder()
	handler.ListMatches(rec1, req1)

	// Second call should hit cache
	scorer.called = false
	req2 := newMatchRequest("caller-123", "13.69", "-89.19", "")
	rec2 := httptest.NewRecorder()
	handler.ListMatches(rec2, req2)

	if rec2.Header().Get("X-Cache") != "HIT" {
		t.Fatalf("expected X-Cache: HIT, got %q", rec2.Header().Get("X-Cache"))
	}
	if scorer.called {
		t.Fatal("scorer should not be called on cache hit")
	}
}

func TestListMatches_MissingAuth(t *testing.T) {
	handler := NewMatchmakingHandler(&mockScorer{}, matchmaking.NewTestCache())

	req := newMatchRequest("", "13.69", "-89.19", "")
	rec := httptest.NewRecorder()
	handler.ListMatches(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestListMatches_MissingLatLng(t *testing.T) {
	handler := NewMatchmakingHandler(&mockScorer{}, matchmaking.NewTestCache())

	req := httptest.NewRequest("GET", "/api/v1/matches", nil)
	ctx := context.WithValue(req.Context(), ably.UserIDKey(), "user-1")
	req = req.WithContext(ctx)

	rec := httptest.NewRecorder()
	handler.ListMatches(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
}

func TestListMatches_InvalidLatitude(t *testing.T) {
	handler := NewMatchmakingHandler(&mockScorer{}, matchmaking.NewTestCache())

	req := newMatchRequest("user-1", "999", "-89.19", "")
	rec := httptest.NewRecorder()
	handler.ListMatches(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid latitude, got %d", rec.Code)
	}
}

func TestListMatches_InvalidRadius(t *testing.T) {
	handler := NewMatchmakingHandler(&mockScorer{}, matchmaking.NewTestCache())

	req := newMatchRequest("user-1", "13.69", "-89.19", "100000")
	rec := httptest.NewRecorder()
	handler.ListMatches(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid radius, got %d", rec.Code)
	}
}

func TestListMatches_ScorerError(t *testing.T) {
	scorer := &mockScorer{err: errors.New("db connection lost")}
	handler := NewMatchmakingHandler(scorer, matchmaking.NewTestCache())

	req := newMatchRequest("user-1", "13.69", "-89.19", "")
	rec := httptest.NewRecorder()
	handler.ListMatches(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rec.Code)
	}
}

func TestListMatches_DefaultRadius(t *testing.T) {
	scorer := &mockScorer{results: []matchmaking.ScoredMatch{}}
	cache := matchmaking.NewTestCache()
	handler := NewMatchmakingHandler(scorer, cache)

	// No radius param — should default to 5000
	req := newMatchRequest("user-1", "13.69", "-89.19", "")
	rec := httptest.NewRecorder()
	handler.ListMatches(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestListMatches_EmptyResults(t *testing.T) {
	scorer := &mockScorer{results: []matchmaking.ScoredMatch{}}
	cache := matchmaking.NewTestCache()
	handler := NewMatchmakingHandler(scorer, cache)

	req := newMatchRequest("user-1", "13.69", "-89.19", "")
	rec := httptest.NewRecorder()
	handler.ListMatches(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var results []matchmaking.ScoredMatch
	if err := json.NewDecoder(rec.Body).Decode(&results); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if len(results) != 0 {
		t.Fatalf("expected empty results, got %d", len(results))
	}
}
