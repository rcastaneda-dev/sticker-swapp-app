package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strconv"
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
	return newMatchRequestWithPagination(userID, lat, lng, radius, "", "")
}

func newMatchRequestWithPagination(userID, lat, lng, radius, offset, limit string) *http.Request {
	url := "/api/v1/matches?lat=" + lat + "&lng=" + lng
	if radius != "" {
		url += "&radius=" + radius
	}
	if offset != "" {
		url += "&offset=" + offset
	}
	if limit != "" {
		url += "&limit=" + limit
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
	if rec.Header().Get("X-Total-Count") != "2" {
		t.Fatalf("expected X-Total-Count: 2, got %q", rec.Header().Get("X-Total-Count"))
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

func TestListMatches_PaginationOffsetLimit(t *testing.T) {
	scorer := &mockScorer{
		results: []matchmaking.ScoredMatch{
			{UserID: "u1", TotalScore: 0.9},
			{UserID: "u2", TotalScore: 0.8},
			{UserID: "u3", TotalScore: 0.7},
			{UserID: "u4", TotalScore: 0.6},
			{UserID: "u5", TotalScore: 0.5},
		},
	}
	cache := matchmaking.NewTestCache()
	handler := NewMatchmakingHandler(scorer, cache)

	// Request page 2: offset=2, limit=2 → should return u3, u4
	req := newMatchRequestWithPagination("user-1", "13.69", "-89.19", "", "2", "2")
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
	if results[0].UserID != "u3" || results[1].UserID != "u4" {
		t.Fatalf("expected u3, u4 but got %s, %s", results[0].UserID, results[1].UserID)
	}
	if rec.Header().Get("X-Total-Count") != "5" {
		t.Fatalf("expected X-Total-Count: 5, got %q", rec.Header().Get("X-Total-Count"))
	}
}

func TestListMatches_PaginationOffsetBeyondResults(t *testing.T) {
	scorer := &mockScorer{
		results: []matchmaking.ScoredMatch{
			{UserID: "u1", TotalScore: 0.9},
		},
	}
	cache := matchmaking.NewTestCache()
	handler := NewMatchmakingHandler(scorer, cache)

	req := newMatchRequestWithPagination("user-1", "13.69", "-89.19", "", "10", "5")
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
	if rec.Header().Get("X-Total-Count") != "1" {
		t.Fatalf("expected X-Total-Count: 1, got %q", rec.Header().Get("X-Total-Count"))
	}
}

func TestListMatches_PaginationDefaultLimit(t *testing.T) {
	results := make([]matchmaking.ScoredMatch, 15)
	for i := range results {
		results[i] = matchmaking.ScoredMatch{UserID: "u" + strconv.Itoa(i), TotalScore: float64(15-i) / 15}
	}
	scorer := &mockScorer{results: results}
	cache := matchmaking.NewTestCache()
	handler := NewMatchmakingHandler(scorer, cache)

	// No offset/limit → default offset=0, limit=10
	req := newMatchRequest("user-1", "13.69", "-89.19", "")
	rec := httptest.NewRecorder()
	handler.ListMatches(rec, req)

	var page []matchmaking.ScoredMatch
	if err := json.NewDecoder(rec.Body).Decode(&page); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if len(page) != 10 {
		t.Fatalf("expected default page size 10, got %d", len(page))
	}
	if rec.Header().Get("X-Total-Count") != "15" {
		t.Fatalf("expected X-Total-Count: 15, got %q", rec.Header().Get("X-Total-Count"))
	}
}

func TestListMatches_InvalidOffset(t *testing.T) {
	handler := NewMatchmakingHandler(&mockScorer{}, matchmaking.NewTestCache())

	req := newMatchRequestWithPagination("user-1", "13.69", "-89.19", "", "-1", "")
	rec := httptest.NewRecorder()
	handler.ListMatches(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid offset, got %d", rec.Code)
	}
}

func TestListMatches_InvalidLimit(t *testing.T) {
	handler := NewMatchmakingHandler(&mockScorer{}, matchmaking.NewTestCache())

	req := newMatchRequestWithPagination("user-1", "13.69", "-89.19", "", "0", "100")
	rec := httptest.NewRecorder()
	handler.ListMatches(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid limit, got %d", rec.Code)
	}
}

func TestListMatches_PaginationWithCache(t *testing.T) {
	scorer := &mockScorer{
		results: []matchmaking.ScoredMatch{
			{UserID: "u1", TotalScore: 0.9},
			{UserID: "u2", TotalScore: 0.8},
			{UserID: "u3", TotalScore: 0.7},
		},
	}
	cache := matchmaking.NewTestCache()
	handler := NewMatchmakingHandler(scorer, cache)

	// First call: page 1 (populates cache)
	req1 := newMatchRequestWithPagination("user-1", "13.69", "-89.19", "", "0", "2")
	rec1 := httptest.NewRecorder()
	handler.ListMatches(rec1, req1)

	var page1 []matchmaking.ScoredMatch
	json.NewDecoder(rec1.Body).Decode(&page1)
	if len(page1) != 2 || page1[0].UserID != "u1" {
		t.Fatalf("page 1 unexpected: got %d results", len(page1))
	}

	// Second call: page 2 (should hit cache, different slice)
	scorer.called = false
	req2 := newMatchRequestWithPagination("user-1", "13.69", "-89.19", "", "2", "2")
	rec2 := httptest.NewRecorder()
	handler.ListMatches(rec2, req2)

	if rec2.Header().Get("X-Cache") != "HIT" {
		t.Fatalf("expected cache HIT for page 2, got %q", rec2.Header().Get("X-Cache"))
	}
	if scorer.called {
		t.Fatal("scorer should not be called for cached page 2")
	}

	var page2 []matchmaking.ScoredMatch
	json.NewDecoder(rec2.Body).Decode(&page2)
	if len(page2) != 1 || page2[0].UserID != "u3" {
		t.Fatalf("page 2 unexpected: got %d results", len(page2))
	}
}
