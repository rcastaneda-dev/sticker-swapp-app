package api

import (
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

// Compile-time interface check.
var _ trades.InventoryLocker = (*mockInventoryLocker)(nil)

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

func newTestTradeHandler(locker trades.InventoryLocker) *TradeHandler {
	return NewTradeHandler(locker)
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
	handler := newTestTradeHandler(locker)

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
	handler := newTestTradeHandler(locker)

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
	handler := newTestTradeHandler(locker)

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
	handler := newTestTradeHandler(locker)

	req := newLockRequest("11111111-1111-1111-1111-111111111111", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
	rec := httptest.NewRecorder()
	handler.LockInventory(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", rec.Code)
	}
}

func TestLockInventory_Unauthorized(t *testing.T) {
	handler := newTestTradeHandler(&mockInventoryLocker{})

	req := newLockRequest("", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
	rec := httptest.NewRecorder()
	handler.LockInventory(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "AUTH_REQUIRED")
}

func TestLockInventory_InvalidMatchID(t *testing.T) {
	handler := newTestTradeHandler(&mockInventoryLocker{})

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
	handler := newTestTradeHandler(locker)

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
	handler := newTestTradeHandler(locker)

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
	handler := newTestTradeHandler(locker)

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
	handler := newTestTradeHandler(&mockInventoryLocker{})

	req := newReleaseRequest("", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
	rec := httptest.NewRecorder()
	handler.ReleaseInventory(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
	assertMatchErrorCode(t, rec, "AUTH_REQUIRED")
}

func TestReleaseInventory_InvalidMatchID(t *testing.T) {
	handler := newTestTradeHandler(&mockInventoryLocker{})

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
	handler := newTestTradeHandler(locker)

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
	handler := newTestTradeHandler(locker)

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
