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

	"github.com/go-chi/chi/v5"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/ably"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/trades"
)

// Compile-time interface checks.
var _ trades.InventoryLocker = (*mockInventoryLocker)(nil)
var _ trades.TradeExecutor = (*mockTradeExecutor)(nil)

type mockInventoryLocker struct {
	lockResult    *trades.LockResult
	lockErr       error
	releaseResult *trades.ReleaseResult
	releaseErr    error
	lockCalled    bool
	releaseCalled bool
	callerID      string
	matchID       string
	reason        string
}

func (m *mockInventoryLocker) LockForTrade(_ context.Context, callerID, matchID string) (*trades.LockResult, error) {
	m.lockCalled = true
	m.callerID = callerID
	m.matchID = matchID
	return m.lockResult, m.lockErr
}

func (m *mockInventoryLocker) ReleaseLocks(_ context.Context, matchID, reason string) (*trades.ReleaseResult, error) {
	m.releaseCalled = true
	m.matchID = matchID
	m.reason = reason
	return m.releaseResult, m.releaseErr
}

type mockTradeExecutor struct {
	result   *trades.TradeResult
	err      error
	called   bool
	callerID string
	req      trades.TradeRequest
}

func (m *mockTradeExecutor) ExecuteTrade(_ context.Context, callerID string, req trades.TradeRequest) (*trades.TradeResult, error) {
	m.called = true
	m.callerID = callerID
	m.req = req
	return m.result, m.err
}

func newTestTradeHandler(locker trades.InventoryLocker, executor trades.TradeExecutor) *TradeHandler {
	return NewTradeHandler(locker, executor)
}

func newLockRequest(userID, matchID string) *http.Request {
	req := httptest.NewRequest("POST", "/api/v1/matches/"+matchID+"/lock", nil)

	// Set Chi URL parameters
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("matchId", matchID)
	req = req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))

	if userID != "" {
		ctx := context.WithValue(req.Context(), ably.UserIDKey(), userID)
		req = req.WithContext(ctx)
	}
	return req
}

func newReleaseRequest(userID, matchID string) *http.Request {
	req := httptest.NewRequest("DELETE", "/api/v1/matches/"+matchID+"/lock", nil)

	// Set Chi URL parameters
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("matchId", matchID)
	req = req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))

	if userID != "" {
		ctx := context.WithValue(req.Context(), ably.UserIDKey(), userID)
		req = req.WithContext(ctx)
	}
	return req
}

func newExecuteRequest(userID string, body executeTradeRequest) *http.Request {
	bodyBytes, _ := json.Marshal(body)
	req := httptest.NewRequest("POST", "/api/v1/trades", bytes.NewReader(bodyBytes))
	req.Header.Set("Content-Type", "application/json")

	if userID != "" {
		ctx := context.WithValue(req.Context(), ably.UserIDKey(), userID)
		req = req.WithContext(ctx)
	}
	return req
}

// ---------------------------------------------------------------------------
// LockInventory tests
// ---------------------------------------------------------------------------

func TestLockInventory_Success(t *testing.T) {
	expires := time.Now().Add(15 * time.Minute).Truncate(time.Second)
	locker := &mockInventoryLocker{
		lockResult: &trades.LockResult{
			Success:    true,
			StickerIDs: []int{10, 25, 42},
			LockCount:  3,
			ExpiresAt:  &expires,
			Extended:   false,
		},
	}
	handler := newTestTradeHandler(locker, &mockTradeExecutor{})

	req := newLockRequest("11111111-1111-1111-1111-111111111111", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
	rec := httptest.NewRecorder()
	handler.LockInventory(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var result trades.LockResult
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if !result.Success {
		t.Fatal("expected success to be true")
	}
	if result.LockCount != 3 {
		t.Fatalf("expected lock_count 3, got %d", result.LockCount)
	}
	if len(result.StickerIDs) != 3 {
		t.Fatalf("expected 3 sticker_ids, got %d", len(result.StickerIDs))
	}
	if result.Extended {
		t.Fatal("expected extended to be false")
	}
}

func TestLockInventory_Extended(t *testing.T) {
	expires := time.Now().Add(15 * time.Minute).Truncate(time.Second)
	locker := &mockInventoryLocker{
		lockResult: &trades.LockResult{
			Success:    true,
			StickerIDs: []int{10, 25},
			LockCount:  2,
			ExpiresAt:  &expires,
			Extended:   true,
		},
	}
	handler := newTestTradeHandler(locker, &mockTradeExecutor{})

	req := newLockRequest("11111111-1111-1111-1111-111111111111", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
	rec := httptest.NewRecorder()
	handler.LockInventory(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var result trades.LockResult
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if !result.Extended {
		t.Fatal("expected extended to be true")
	}
}

func TestLockInventory_Conflict(t *testing.T) {
	errMsg := "STICKERS_ALREADY_LOCKED"
	locker := &mockInventoryLocker{
		lockResult: &trades.LockResult{
			Success: false,
			Error:   &errMsg,
		},
	}
	handler := newTestTradeHandler(locker, &mockTradeExecutor{})

	req := newLockRequest("11111111-1111-1111-1111-111111111111", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
	rec := httptest.NewRecorder()
	handler.LockInventory(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", rec.Code)
	}

	var result trades.LockResult
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if result.Success {
		t.Fatal("expected success to be false")
	}
	if result.Error == nil || *result.Error != "STICKERS_ALREADY_LOCKED" {
		t.Fatalf("expected error STICKERS_ALREADY_LOCKED, got %v", result.Error)
	}
}

func TestLockInventory_NoDuplicates(t *testing.T) {
	errMsg := "NO_DUPLICATES"
	locker := &mockInventoryLocker{
		lockResult: &trades.LockResult{
			Success: false,
			Error:   &errMsg,
		},
	}
	handler := newTestTradeHandler(locker, &mockTradeExecutor{})

	req := newLockRequest("11111111-1111-1111-1111-111111111111", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
	rec := httptest.NewRecorder()
	handler.LockInventory(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", rec.Code)
	}
}

func TestLockInventory_StickersNotAvailable(t *testing.T) {
	errMsg := "STICKERS_NOT_AVAILABLE"
	locker := &mockInventoryLocker{
		lockResult: &trades.LockResult{
			Success: false,
			Error:   &errMsg,
		},
	}
	handler := newTestTradeHandler(locker, &mockTradeExecutor{})

	req := newLockRequest("11111111-1111-1111-1111-111111111111", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
	rec := httptest.NewRecorder()
	handler.LockInventory(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", rec.Code)
	}

	var result trades.LockResult
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if result.Success {
		t.Fatal("expected success to be false")
	}
	if result.Error == nil || *result.Error != "STICKERS_NOT_AVAILABLE" {
		t.Fatalf("expected error STICKERS_NOT_AVAILABLE, got %v", result.Error)
	}
}

func TestLockInventory_Unauthorized(t *testing.T) {
	handler := newTestTradeHandler(&mockInventoryLocker{}, &mockTradeExecutor{})

	req := newLockRequest("", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
	rec := httptest.NewRecorder()
	handler.LockInventory(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "AUTH_REQUIRED")
}

func TestLockInventory_InvalidMatchID(t *testing.T) {
	handler := newTestTradeHandler(&mockInventoryLocker{}, &mockTradeExecutor{})

	req := newLockRequest("11111111-1111-1111-1111-111111111111", "not-a-uuid")
	rec := httptest.NewRecorder()
	handler.LockInventory(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "INVALID_PARAMS")
}

func TestLockInventory_DBError(t *testing.T) {
	locker := &mockInventoryLocker{
		lockErr: errors.New("connection lost"),
	}
	handler := newTestTradeHandler(locker, &mockTradeExecutor{})

	req := newLockRequest("11111111-1111-1111-1111-111111111111", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
	rec := httptest.NewRecorder()
	handler.LockInventory(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "LOCK_ERROR")
}

func TestLockInventory_PassesCorrectArgs(t *testing.T) {
	locker := &mockInventoryLocker{
		lockResult: &trades.LockResult{
			Success:    true,
			StickerIDs: []int{1},
			LockCount:  1,
		},
	}
	handler := newTestTradeHandler(locker, &mockTradeExecutor{})

	callerID := "11111111-1111-1111-1111-111111111111"
	matchID := "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
	req := newLockRequest(callerID, matchID)
	rec := httptest.NewRecorder()
	handler.LockInventory(rec, req)

	if !locker.lockCalled {
		t.Fatal("expected locker.LockForTrade to be called")
	}
	if locker.callerID != callerID {
		t.Fatalf("expected callerID %q, got %q", callerID, locker.callerID)
	}
	if locker.matchID != matchID {
		t.Fatalf("expected matchID %q, got %q", matchID, locker.matchID)
	}
}

// ---------------------------------------------------------------------------
// ReleaseInventory tests
// ---------------------------------------------------------------------------

func TestReleaseInventory_Success(t *testing.T) {
	locker := &mockInventoryLocker{
		releaseResult: &trades.ReleaseResult{
			Success:       true,
			ReleasedCount: 2,
		},
	}
	handler := newTestTradeHandler(locker, &mockTradeExecutor{})

	req := newReleaseRequest("11111111-1111-1111-1111-111111111111", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
	rec := httptest.NewRecorder()
	handler.ReleaseInventory(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var result trades.ReleaseResult
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if !result.Success {
		t.Fatal("expected success to be true")
	}
	if result.ReleasedCount != 2 {
		t.Fatalf("expected released_count 2, got %d", result.ReleasedCount)
	}
}

func TestReleaseInventory_Unauthorized(t *testing.T) {
	handler := newTestTradeHandler(&mockInventoryLocker{}, &mockTradeExecutor{})

	req := newReleaseRequest("", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
	rec := httptest.NewRecorder()
	handler.ReleaseInventory(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "AUTH_REQUIRED")
}

func TestReleaseInventory_InvalidMatchID(t *testing.T) {
	handler := newTestTradeHandler(&mockInventoryLocker{}, &mockTradeExecutor{})

	req := newReleaseRequest("11111111-1111-1111-1111-111111111111", "not-a-uuid")
	rec := httptest.NewRecorder()
	handler.ReleaseInventory(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "INVALID_PARAMS")
}

func TestReleaseInventory_DBError(t *testing.T) {
	locker := &mockInventoryLocker{
		releaseErr: errors.New("connection lost"),
	}
	handler := newTestTradeHandler(locker, &mockTradeExecutor{})

	req := newReleaseRequest("11111111-1111-1111-1111-111111111111", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
	rec := httptest.NewRecorder()
	handler.ReleaseInventory(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "RELEASE_ERROR")
}

func TestReleaseInventory_PassesManualReason(t *testing.T) {
	locker := &mockInventoryLocker{
		releaseResult: &trades.ReleaseResult{
			Success:       true,
			ReleasedCount: 1,
		},
	}
	handler := newTestTradeHandler(locker, &mockTradeExecutor{})

	req := newReleaseRequest("11111111-1111-1111-1111-111111111111", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
	rec := httptest.NewRecorder()
	handler.ReleaseInventory(rec, req)

	if !locker.releaseCalled {
		t.Fatal("expected locker.ReleaseLocks to be called")
	}
	if locker.reason != "MANUAL_RELEASE" {
		t.Fatalf("expected reason %q, got %q", "MANUAL_RELEASE", locker.reason)
	}
}

// ---------------------------------------------------------------------------
// Execute (trade) tests
// ---------------------------------------------------------------------------

var (
	testUserID        = "11111111-1111-1111-1111-111111111111"
	testMatchID       = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
	testIdempotencyKey = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
	testTradeID       = "cccccccc-cccc-cccc-cccc-cccccccccccc"
	testResponderID   = "dddddddd-dddd-dddd-dddd-dddddddddddd"
	testStatus        = "COMPLETED"
)

func validExecuteBody() executeTradeRequest {
	return executeTradeRequest{
		MatchID:             testMatchID,
		InitiatorStickerIDs: []int{10, 25, 42},
		ResponderStickerIDs: []int{5, 88},
		IdempotencyKey:      testIdempotencyKey,
	}
}

func successTradeResult() *trades.TradeResult {
	return &trades.TradeResult{
		Success:             true,
		TradeID:             &testTradeID,
		MatchID:             &testMatchID,
		InitiatorID:         &testUserID,
		ResponderID:         &testResponderID,
		InitiatorStickerIDs: []int{10, 25, 42},
		ResponderStickerIDs: []int{5, 88},
		Status:              &testStatus,
	}
}

func TestExecuteTrade_Success(t *testing.T) {
	executor := &mockTradeExecutor{result: successTradeResult()}
	handler := newTestTradeHandler(&mockInventoryLocker{}, executor)

	req := newExecuteRequest(testUserID, validExecuteBody())
	rec := httptest.NewRecorder()
	handler.Execute(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var result trades.TradeResult
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if !result.Success {
		t.Fatal("expected success to be true")
	}
	if result.TradeID == nil || *result.TradeID != testTradeID {
		t.Fatalf("expected trade_id %q, got %v", testTradeID, result.TradeID)
	}
	if len(result.InitiatorStickerIDs) != 3 {
		t.Fatalf("expected 3 initiator stickers, got %d", len(result.InitiatorStickerIDs))
	}
	if len(result.ResponderStickerIDs) != 2 {
		t.Fatalf("expected 2 responder stickers, got %d", len(result.ResponderStickerIDs))
	}
}

func TestExecuteTrade_AlreadyCompleted(t *testing.T) {
	r := successTradeResult()
	r.AlreadyCompleted = true
	executor := &mockTradeExecutor{result: r}
	handler := newTestTradeHandler(&mockInventoryLocker{}, executor)

	req := newExecuteRequest(testUserID, validExecuteBody())
	rec := httptest.NewRecorder()
	handler.Execute(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var result trades.TradeResult
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if !result.Success {
		t.Fatal("expected success to be true")
	}
	if !result.AlreadyCompleted {
		t.Fatal("expected already_completed to be true")
	}
}

func TestExecuteTrade_MatchNotFound(t *testing.T) {
	errMsg := "MATCH_NOT_FOUND"
	executor := &mockTradeExecutor{
		result: &trades.TradeResult{Success: false, Error: &errMsg},
	}
	handler := newTestTradeHandler(&mockInventoryLocker{}, executor)

	req := newExecuteRequest(testUserID, validExecuteBody())
	rec := httptest.NewRecorder()
	handler.Execute(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", rec.Code)
	}

	var result trades.TradeResult
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if result.Success {
		t.Fatal("expected success to be false")
	}
	if result.Error == nil || *result.Error != "MATCH_NOT_FOUND" {
		t.Fatalf("expected error MATCH_NOT_FOUND, got %v", result.Error)
	}
}

func TestExecuteTrade_NotParticipant(t *testing.T) {
	errMsg := "NOT_PARTICIPANT"
	executor := &mockTradeExecutor{
		result: &trades.TradeResult{Success: false, Error: &errMsg},
	}
	handler := newTestTradeHandler(&mockInventoryLocker{}, executor)

	req := newExecuteRequest(testUserID, validExecuteBody())
	rec := httptest.NewRecorder()
	handler.Execute(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", rec.Code)
	}
}

func TestExecuteTrade_MatchNotPending(t *testing.T) {
	errMsg := "MATCH_NOT_PENDING"
	executor := &mockTradeExecutor{
		result: &trades.TradeResult{Success: false, Error: &errMsg},
	}
	handler := newTestTradeHandler(&mockInventoryLocker{}, executor)

	req := newExecuteRequest(testUserID, validExecuteBody())
	rec := httptest.NewRecorder()
	handler.Execute(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", rec.Code)
	}
}

func TestExecuteTrade_NoActiveLockInitiator(t *testing.T) {
	errMsg := "NO_ACTIVE_LOCK_INITIATOR"
	executor := &mockTradeExecutor{
		result: &trades.TradeResult{Success: false, Error: &errMsg},
	}
	handler := newTestTradeHandler(&mockInventoryLocker{}, executor)

	req := newExecuteRequest(testUserID, validExecuteBody())
	rec := httptest.NewRecorder()
	handler.Execute(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", rec.Code)
	}
}

func TestExecuteTrade_NoActiveLockResponder(t *testing.T) {
	errMsg := "NO_ACTIVE_LOCK_RESPONDER"
	executor := &mockTradeExecutor{
		result: &trades.TradeResult{Success: false, Error: &errMsg},
	}
	handler := newTestTradeHandler(&mockInventoryLocker{}, executor)

	req := newExecuteRequest(testUserID, validExecuteBody())
	rec := httptest.NewRecorder()
	handler.Execute(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", rec.Code)
	}
}

func TestExecuteTrade_StickersNotInLock(t *testing.T) {
	errMsg := "STICKERS_NOT_IN_LOCK"
	executor := &mockTradeExecutor{
		result: &trades.TradeResult{Success: false, Error: &errMsg},
	}
	handler := newTestTradeHandler(&mockInventoryLocker{}, executor)

	req := newExecuteRequest(testUserID, validExecuteBody())
	rec := httptest.NewRecorder()
	handler.Execute(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", rec.Code)
	}

	var result trades.TradeResult
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if result.Error == nil || *result.Error != "STICKERS_NOT_IN_LOCK" {
		t.Fatalf("expected error STICKERS_NOT_IN_LOCK, got %v", result.Error)
	}
}

func TestExecuteTrade_StickersNotReserved(t *testing.T) {
	errMsg := "STICKERS_NOT_RESERVED"
	executor := &mockTradeExecutor{
		result: &trades.TradeResult{Success: false, Error: &errMsg},
	}
	handler := newTestTradeHandler(&mockInventoryLocker{}, executor)

	req := newExecuteRequest(testUserID, validExecuteBody())
	rec := httptest.NewRecorder()
	handler.Execute(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", rec.Code)
	}

	var result trades.TradeResult
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if result.Success {
		t.Fatal("expected success to be false")
	}
	if result.Error == nil || *result.Error != "STICKERS_NOT_RESERVED" {
		t.Fatalf("expected error STICKERS_NOT_RESERVED, got %v", result.Error)
	}
}

func TestExecuteTrade_Unauthorized(t *testing.T) {
	handler := newTestTradeHandler(&mockInventoryLocker{}, &mockTradeExecutor{})

	req := newExecuteRequest("", validExecuteBody())
	rec := httptest.NewRecorder()
	handler.Execute(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "AUTH_REQUIRED")
}

func TestExecuteTrade_InvalidBody(t *testing.T) {
	handler := newTestTradeHandler(&mockInventoryLocker{}, &mockTradeExecutor{})

	req := httptest.NewRequest("POST", "/api/v1/trades", bytes.NewReader([]byte("not json")))
	ctx := context.WithValue(req.Context(), ably.UserIDKey(), testUserID)
	req = req.WithContext(ctx)

	rec := httptest.NewRecorder()
	handler.Execute(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "INVALID_BODY")
}

func TestExecuteTrade_InvalidMatchID(t *testing.T) {
	handler := newTestTradeHandler(&mockInventoryLocker{}, &mockTradeExecutor{})

	body := validExecuteBody()
	body.MatchID = "not-a-uuid"
	req := newExecuteRequest(testUserID, body)
	rec := httptest.NewRecorder()
	handler.Execute(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "INVALID_PARAMS")
}

func TestExecuteTrade_InvalidIdempotencyKey(t *testing.T) {
	handler := newTestTradeHandler(&mockInventoryLocker{}, &mockTradeExecutor{})

	body := validExecuteBody()
	body.IdempotencyKey = "not-a-uuid"
	req := newExecuteRequest(testUserID, body)
	rec := httptest.NewRecorder()
	handler.Execute(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "INVALID_PARAMS")
}

func TestExecuteTrade_EmptyInitiatorStickers(t *testing.T) {
	handler := newTestTradeHandler(&mockInventoryLocker{}, &mockTradeExecutor{})

	body := validExecuteBody()
	body.InitiatorStickerIDs = []int{}
	req := newExecuteRequest(testUserID, body)
	rec := httptest.NewRecorder()
	handler.Execute(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "INVALID_PARAMS")
}

func TestExecuteTrade_EmptyResponderStickers(t *testing.T) {
	handler := newTestTradeHandler(&mockInventoryLocker{}, &mockTradeExecutor{})

	body := validExecuteBody()
	body.ResponderStickerIDs = []int{}
	req := newExecuteRequest(testUserID, body)
	rec := httptest.NewRecorder()
	handler.Execute(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "INVALID_PARAMS")
}

func TestExecuteTrade_DBError(t *testing.T) {
	executor := &mockTradeExecutor{err: errors.New("connection lost")}
	handler := newTestTradeHandler(&mockInventoryLocker{}, executor)

	req := newExecuteRequest(testUserID, validExecuteBody())
	rec := httptest.NewRecorder()
	handler.Execute(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "TRADE_ERROR")
}

func TestExecuteTrade_PassesCorrectArgs(t *testing.T) {
	executor := &mockTradeExecutor{result: successTradeResult()}
	handler := newTestTradeHandler(&mockInventoryLocker{}, executor)

	body := validExecuteBody()
	req := newExecuteRequest(testUserID, body)
	rec := httptest.NewRecorder()
	handler.Execute(rec, req)

	if !executor.called {
		t.Fatal("expected executor.ExecuteTrade to be called")
	}
	if executor.callerID != testUserID {
		t.Fatalf("expected callerID %q, got %q", testUserID, executor.callerID)
	}
	if executor.req.MatchID != testMatchID {
		t.Fatalf("expected matchID %q, got %q", testMatchID, executor.req.MatchID)
	}
	if executor.req.IdempotencyKey != testIdempotencyKey {
		t.Fatalf("expected idempotencyKey %q, got %q", testIdempotencyKey, executor.req.IdempotencyKey)
	}
	if len(executor.req.InitiatorStickerIDs) != 3 {
		t.Fatalf("expected 3 initiator stickers, got %d", len(executor.req.InitiatorStickerIDs))
	}
	if len(executor.req.ResponderStickerIDs) != 2 {
		t.Fatalf("expected 2 responder stickers, got %d", len(executor.req.ResponderStickerIDs))
	}
}
