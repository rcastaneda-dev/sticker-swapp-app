package api

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/matches"
)

// Compile-time interface check.
var _ matches.MatchCreator = (*mockMatchCreator)(nil)

type mockMatchCreator struct {
	result   *matches.CreateMatchResult
	err      error
	called   bool
	callerID string
	targetID string
}

func (m *mockMatchCreator) CreateMatchIfMutual(_ context.Context, callerID, targetID string) (*matches.CreateMatchResult, error) {
	m.called = true
	m.callerID = callerID
	m.targetID = targetID
	return m.result, m.err
}

func newCreateMatchRequest(userID string, body interface{}) *http.Request {
	var bodyBytes []byte
	if body != nil {
		bodyBytes, _ = json.Marshal(body)
	}
	req := httptest.NewRequest("POST", "/api/v1/matches", bytes.NewReader(bodyBytes))
	req.Header.Set("Content-Type", "application/json")
	if userID != "" {
		ctx := context.WithValue(req.Context(), ably.UserIDKey(), userID)
		req = req.WithContext(ctx)
	}
	return req
}

func strPtr(s string) *string    { return &s }
func timePtr(t time.Time) *time.Time { return &t }

func TestCreateMatch_MutualMatch(t *testing.T) {
	matchID := "match-uuid-123"
	status := "PENDING"
	now := time.Now().Truncate(time.Second)
	creator := &mockMatchCreator{
		result: &matches.CreateMatchResult{
			Matched:   true,
			MatchID:   &matchID,
			User1ID:   strPtr("11111111-1111-1111-1111-111111111111"),
			User2ID:   strPtr("22222222-2222-2222-2222-222222222222"),
			Status:    &status,
			CreatedAt: timePtr(now),
		},
	}
	handler := NewMatchHandler(creator)

	req := newCreateMatchRequest("11111111-1111-1111-1111-111111111111", createMatchRequest{
		TargetUserID: "22222222-2222-2222-2222-222222222222",
	})
	rec := httptest.NewRecorder()
	handler.CreateMatch(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d", rec.Code)
	}

	var result matches.CreateMatchResult
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if !result.Matched {
		t.Fatal("expected matched to be true")
	}
	if result.MatchID == nil || *result.MatchID != matchID {
		t.Fatalf("expected match_id %q, got %v", matchID, result.MatchID)
	}
	if result.Status == nil || *result.Status != "PENDING" {
		t.Fatalf("expected status PENDING, got %v", result.Status)
	}
}

func TestCreateMatch_SwipeOnly(t *testing.T) {
	creator := &mockMatchCreator{
		result: &matches.CreateMatchResult{
			Matched:       false,
			SwipeRecorded: true,
		},
	}
	handler := NewMatchHandler(creator)

	req := newCreateMatchRequest("11111111-1111-1111-1111-111111111111", createMatchRequest{
		TargetUserID: "22222222-2222-2222-2222-222222222222",
	})
	rec := httptest.NewRecorder()
	handler.CreateMatch(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var result matches.CreateMatchResult
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if result.Matched {
		t.Fatal("expected matched to be false")
	}
	if !result.SwipeRecorded {
		t.Fatal("expected swipe_recorded to be true")
	}
}

func TestCreateMatch_MissingBody(t *testing.T) {
	handler := NewMatchHandler(&mockMatchCreator{})

	req := httptest.NewRequest("POST", "/api/v1/matches", nil)
	ctx := context.WithValue(req.Context(), ably.UserIDKey(), "11111111-1111-1111-1111-111111111111")
	req = req.WithContext(ctx)

	rec := httptest.NewRecorder()
	handler.CreateMatch(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "INVALID_BODY")
}

func TestCreateMatch_MissingTargetUserID(t *testing.T) {
	handler := NewMatchHandler(&mockMatchCreator{})

	req := newCreateMatchRequest("11111111-1111-1111-1111-111111111111", createMatchRequest{
		TargetUserID: "",
	})
	rec := httptest.NewRecorder()
	handler.CreateMatch(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "INVALID_PARAMS")
}

func TestCreateMatch_InvalidUUID(t *testing.T) {
	handler := NewMatchHandler(&mockMatchCreator{})

	req := newCreateMatchRequest("11111111-1111-1111-1111-111111111111", createMatchRequest{
		TargetUserID: "not-a-uuid",
	})
	rec := httptest.NewRecorder()
	handler.CreateMatch(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "INVALID_PARAMS")
}

func TestCreateMatch_SelfSwipe(t *testing.T) {
	creator := &mockMatchCreator{}
	handler := NewMatchHandler(creator)

	req := newCreateMatchRequest("11111111-1111-1111-1111-111111111111", createMatchRequest{
		TargetUserID: "11111111-1111-1111-1111-111111111111",
	})
	rec := httptest.NewRecorder()
	handler.CreateMatch(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "SELF_SWIPE")
	if creator.called {
		t.Fatal("creator should not be called for self-swipe")
	}
}

func TestCreateMatch_Unauthorized(t *testing.T) {
	handler := NewMatchHandler(&mockMatchCreator{})

	req := newCreateMatchRequest("", createMatchRequest{
		TargetUserID: "22222222-2222-2222-2222-222222222222",
	})
	rec := httptest.NewRecorder()
	handler.CreateMatch(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "AUTH_REQUIRED")
}

func TestCreateMatch_DBError(t *testing.T) {
	creator := &mockMatchCreator{
		err: errors.New("connection lost"),
	}
	handler := NewMatchHandler(creator)

	req := newCreateMatchRequest("11111111-1111-1111-1111-111111111111", createMatchRequest{
		TargetUserID: "22222222-2222-2222-2222-222222222222",
	})
	rec := httptest.NewRecorder()
	handler.CreateMatch(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "MATCH_ERROR")
}

func TestCreateMatch_PassesCorrectArgs(t *testing.T) {
	creator := &mockMatchCreator{
		result: &matches.CreateMatchResult{
			Matched:       false,
			SwipeRecorded: true,
		},
	}
	handler := NewMatchHandler(creator)

	callerID := "11111111-1111-1111-1111-111111111111"
	targetID := "22222222-2222-2222-2222-222222222222"
	req := newCreateMatchRequest(callerID, createMatchRequest{
		TargetUserID: targetID,
	})
	rec := httptest.NewRecorder()
	handler.CreateMatch(rec, req)

	if !creator.called {
		t.Fatal("expected creator to be called")
	}
	if creator.callerID != callerID {
		t.Fatalf("expected callerID %q, got %q", callerID, creator.callerID)
	}
	if creator.targetID != targetID {
		t.Fatalf("expected targetID %q, got %q", targetID, creator.targetID)
	}
}

// assertMatchErrorCode validates the error code in a JSON error response.
func assertMatchErrorCode(t *testing.T, rec *httptest.ResponseRecorder, expectedCode string) {
	t.Helper()
	var body struct {
		Code string `json:"code"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("failed to parse error response: %v", err)
	}
	if body.Code != expectedCode {
		t.Fatalf("expected code %q, got %q", expectedCode, body.Code)
	}
}
