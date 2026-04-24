package api

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/matches"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/onesignal"
)

// Compile-time interface checks.
var _ matches.MatchCreator = (*mockMatchCreator)(nil)
var _ onesignal.Notifier = (*mockNotifier)(nil)
var _ DisplayNameLookup = (*mockDisplayNameLookup)(nil)
var _ ably.Publisher = (*mockPublisher)(nil)

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

type mockNotifier struct {
	mu            sync.Mutex
	called        bool
	recipientID   string
	matchID       string
	displayName   string
	err           error
	notifyCh      chan struct{} // closed when NotifyMatchCreated is called
}

func newMockNotifier() *mockNotifier {
	return &mockNotifier{notifyCh: make(chan struct{})}
}

func (m *mockNotifier) NotifyMatchCreated(_ context.Context, recipientID, matchID, displayName string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.called = true
	m.recipientID = recipientID
	m.matchID = matchID
	m.displayName = displayName
	select {
	case <-m.notifyCh:
	default:
		close(m.notifyCh)
	}
	return m.err
}

type mockDisplayNameLookup struct {
	name string
}

func (m *mockDisplayNameLookup) LookupDisplayName(_ context.Context, _ string) string {
	if m.name == "" {
		return "Someone"
	}
	return m.name
}

type mockPublisher struct {
	mu        sync.Mutex
	called    bool
	matchID   string
	event     ably.MatchCreatedEvent
	err       error
	publishCh chan struct{}
}

func newMockPublisher() *mockPublisher {
	return &mockPublisher{publishCh: make(chan struct{})}
}

func (m *mockPublisher) PublishMatchCreated(_ context.Context, matchID string, event ably.MatchCreatedEvent) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.called = true
	m.matchID = matchID
	m.event = event
	select {
	case <-m.publishCh:
	default:
		close(m.publishCh)
	}
	return m.err
}

func (m *mockPublisher) PublishTradeConfirmed(_ context.Context, _ string, _ ably.TradeConfirmedEvent) error {
	return nil
}

func newTestHandler(creator matches.MatchCreator) *MatchHandler {
	return NewMatchHandler(creator, newMockNotifier(), &mockDisplayNameLookup{}, newMockPublisher())
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

func strPtr(s string) *string        { return &s }
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
	handler := newTestHandler(creator)

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
	handler := newTestHandler(creator)

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
	handler := newTestHandler(&mockMatchCreator{})

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
	handler := newTestHandler(&mockMatchCreator{})

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
	handler := newTestHandler(&mockMatchCreator{})

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
	handler := newTestHandler(creator)

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
	handler := newTestHandler(&mockMatchCreator{})

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
	handler := newTestHandler(creator)

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
	handler := newTestHandler(creator)

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

func TestCreateMatch_MutualMatch_SendsPush(t *testing.T) {
	matchID := "match-uuid-456"
	callerID := "11111111-1111-1111-1111-111111111111"
	targetID := "22222222-2222-2222-2222-222222222222"
	status := "PENDING"

	creator := &mockMatchCreator{
		result: &matches.CreateMatchResult{
			Matched:   true,
			MatchID:   &matchID,
			User1ID:   strPtr(callerID),
			User2ID:   strPtr(targetID),
			Status:    &status,
			CreatedAt: timePtr(time.Now()),
		},
	}
	notifier := newMockNotifier()
	names := &mockDisplayNameLookup{name: "Carlos"}
	handler := NewMatchHandler(creator, notifier, names, newMockPublisher())

	req := newCreateMatchRequest(callerID, createMatchRequest{
		TargetUserID: targetID,
	})
	rec := httptest.NewRecorder()
	handler.CreateMatch(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d", rec.Code)
	}

	// Wait for async push goroutine
	select {
	case <-notifier.notifyCh:
	case <-time.After(2 * time.Second):
		t.Fatal("push notification was not sent within timeout")
	}

	notifier.mu.Lock()
	defer notifier.mu.Unlock()
	if !notifier.called {
		t.Fatal("expected notifier to be called")
	}
	if notifier.recipientID != targetID {
		t.Fatalf("expected recipient %q, got %q", targetID, notifier.recipientID)
	}
	if notifier.matchID != matchID {
		t.Fatalf("expected matchID %q, got %q", matchID, notifier.matchID)
	}
	if notifier.displayName != "Carlos" {
		t.Fatalf("expected displayName %q, got %q", "Carlos", notifier.displayName)
	}
}

func TestCreateMatch_SwipeOnly_NoPush(t *testing.T) {
	creator := &mockMatchCreator{
		result: &matches.CreateMatchResult{
			Matched:       false,
			SwipeRecorded: true,
		},
	}
	notifier := newMockNotifier()
	handler := NewMatchHandler(creator, notifier, &mockDisplayNameLookup{}, newMockPublisher())

	req := newCreateMatchRequest("11111111-1111-1111-1111-111111111111", createMatchRequest{
		TargetUserID: "22222222-2222-2222-2222-222222222222",
	})
	rec := httptest.NewRecorder()
	handler.CreateMatch(rec, req)

	// Give goroutine a chance to run (it shouldn't)
	time.Sleep(50 * time.Millisecond)

	notifier.mu.Lock()
	defer notifier.mu.Unlock()
	if notifier.called {
		t.Fatal("notifier should not be called for non-mutual swipe")
	}
}

func TestCreateMatch_PushFailure_StillReturns201(t *testing.T) {
	matchID := "match-uuid-789"
	status := "PENDING"
	callerID := "11111111-1111-1111-1111-111111111111"
	targetID := "22222222-2222-2222-2222-222222222222"

	creator := &mockMatchCreator{
		result: &matches.CreateMatchResult{
			Matched:   true,
			MatchID:   &matchID,
			User1ID:   strPtr(callerID),
			User2ID:   strPtr(targetID),
			Status:    &status,
			CreatedAt: timePtr(time.Now()),
		},
	}
	notifier := newMockNotifier()
	notifier.err = errors.New("onesignal returned 500")
	handler := NewMatchHandler(creator, notifier, &mockDisplayNameLookup{}, newMockPublisher())

	req := newCreateMatchRequest(callerID, createMatchRequest{
		TargetUserID: targetID,
	})
	rec := httptest.NewRecorder()
	handler.CreateMatch(rec, req)

	// Response should still be 201 regardless of push failure
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d", rec.Code)
	}

	// Wait for async push goroutine
	select {
	case <-notifier.notifyCh:
	case <-time.After(2 * time.Second):
		t.Fatal("push notification was not attempted within timeout")
	}

	notifier.mu.Lock()
	defer notifier.mu.Unlock()
	if !notifier.called {
		t.Fatal("expected notifier to be called even though it returns error")
	}
}

func TestRecipientFromMatch(t *testing.T) {
	tests := []struct {
		name     string
		callerID string
		user1    string
		user2    string
		want     string
	}{
		{
			name:     "caller is user1, recipient is user2",
			callerID: "aaa",
			user1:    "aaa",
			user2:    "bbb",
			want:     "bbb",
		},
		{
			name:     "caller is user2, recipient is user1",
			callerID: "bbb",
			user1:    "aaa",
			user2:    "bbb",
			want:     "aaa",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := &matches.CreateMatchResult{
				User1ID: strPtr(tt.user1),
				User2ID: strPtr(tt.user2),
			}
			got := recipientFromMatch(tt.callerID, result)
			if got != tt.want {
				t.Fatalf("expected %q, got %q", tt.want, got)
			}
		})
	}
}

func TestCreateMatch_MutualMatch_PublishesAblyEvent(t *testing.T) {
	matchID := "match-uuid-pub"
	callerID := "11111111-1111-1111-1111-111111111111"
	targetID := "22222222-2222-2222-2222-222222222222"
	status := "PENDING"

	creator := &mockMatchCreator{
		result: &matches.CreateMatchResult{
			Matched:   true,
			MatchID:   &matchID,
			User1ID:   strPtr(callerID),
			User2ID:   strPtr(targetID),
			Status:    &status,
			CreatedAt: timePtr(time.Now()),
		},
	}
	publisher := newMockPublisher()
	handler := NewMatchHandler(creator, newMockNotifier(), &mockDisplayNameLookup{}, publisher)

	req := newCreateMatchRequest(callerID, createMatchRequest{
		TargetUserID: targetID,
	})
	rec := httptest.NewRecorder()
	handler.CreateMatch(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d", rec.Code)
	}

	// Wait for async publish goroutine
	select {
	case <-publisher.publishCh:
	case <-time.After(2 * time.Second):
		t.Fatal("ably publish was not called within timeout")
	}

	publisher.mu.Lock()
	defer publisher.mu.Unlock()
	if !publisher.called {
		t.Fatal("expected publisher to be called")
	}
	if publisher.matchID != matchID {
		t.Fatalf("expected matchID %q, got %q", matchID, publisher.matchID)
	}
	if publisher.event.User1ID != callerID {
		t.Fatalf("expected user1_id %q, got %q", callerID, publisher.event.User1ID)
	}
	if publisher.event.User2ID != targetID {
		t.Fatalf("expected user2_id %q, got %q", targetID, publisher.event.User2ID)
	}
	if publisher.event.Status != "PENDING" {
		t.Fatalf("expected status %q, got %q", "PENDING", publisher.event.Status)
	}
}

func TestCreateMatch_SwipeOnly_NoAblyPublish(t *testing.T) {
	creator := &mockMatchCreator{
		result: &matches.CreateMatchResult{
			Matched:       false,
			SwipeRecorded: true,
		},
	}
	publisher := newMockPublisher()
	handler := NewMatchHandler(creator, newMockNotifier(), &mockDisplayNameLookup{}, publisher)

	req := newCreateMatchRequest("11111111-1111-1111-1111-111111111111", createMatchRequest{
		TargetUserID: "22222222-2222-2222-2222-222222222222",
	})
	rec := httptest.NewRecorder()
	handler.CreateMatch(rec, req)

	// Give goroutine a chance to run (it shouldn't)
	time.Sleep(50 * time.Millisecond)

	publisher.mu.Lock()
	defer publisher.mu.Unlock()
	if publisher.called {
		t.Fatal("publisher should not be called for non-mutual swipe")
	}
}

func TestCreateMatch_AblyPublishFailure_StillReturns201(t *testing.T) {
	matchID := "match-uuid-fail"
	status := "PENDING"
	callerID := "11111111-1111-1111-1111-111111111111"
	targetID := "22222222-2222-2222-2222-222222222222"

	creator := &mockMatchCreator{
		result: &matches.CreateMatchResult{
			Matched:   true,
			MatchID:   &matchID,
			User1ID:   strPtr(callerID),
			User2ID:   strPtr(targetID),
			Status:    &status,
			CreatedAt: timePtr(time.Now()),
		},
	}
	publisher := newMockPublisher()
	publisher.err = errors.New("ably returned 500")
	handler := NewMatchHandler(creator, newMockNotifier(), &mockDisplayNameLookup{}, publisher)

	req := newCreateMatchRequest(callerID, createMatchRequest{
		TargetUserID: targetID,
	})
	rec := httptest.NewRecorder()
	handler.CreateMatch(rec, req)

	// Response should still be 201 regardless of publish failure
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d", rec.Code)
	}

	// Wait for async publish goroutine
	select {
	case <-publisher.publishCh:
	case <-time.After(2 * time.Second):
		t.Fatal("ably publish was not attempted within timeout")
	}

	publisher.mu.Lock()
	defer publisher.mu.Unlock()
	if !publisher.called {
		t.Fatal("expected publisher to be called even though it returns error")
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
