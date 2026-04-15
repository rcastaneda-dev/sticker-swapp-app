package middleware

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"
)

// ---------------------------------------------------------------------------
// Fake NonceStore
// ---------------------------------------------------------------------------

// Compile-time check that fakeNonceStore implements NonceStore.
var _ NonceStore = (*fakeNonceStore)(nil)

type fakeNonceStore struct {
	consumed map[string]bool
	err      error
}

func newFakeNonceStore() *fakeNonceStore {
	return &fakeNonceStore{consumed: make(map[string]bool)}
}

func (f *fakeNonceStore) ConsumeNonce(_ context.Context, nonce string, _ time.Time) (bool, error) {
	if f.err != nil {
		return false, f.err
	}
	if f.consumed[nonce] {
		return false, nil // already used
	}
	f.consumed[nonce] = true
	return true, nil
}

func (f *fakeNonceStore) CleanupExpired(_ context.Context) (int64, error) {
	return 0, nil
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const testSecret = "test-hmac-secret-key"

func testReplayGuardConfig() ReplayGuardConfig {
	cfg := DefaultReplayGuardConfig()
	cfg.HMACSecret = testSecret
	// Use a very long cleanup interval so the background goroutine
	// does not interfere with short-lived tests.
	cfg.CleanupInterval = 24 * time.Hour
	return cfg
}

func computeSignature(method, path, timestamp, nonce, secret string) string {
	signingString := fmt.Sprintf("%s:%s:%s:%s", method, path, timestamp, nonce)
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(signingString))
	return hex.EncodeToString(mac.Sum(nil))
}

func newReplayGuardedRequest(method, path, secret string) *http.Request {
	nonce := "abcdef0123456789abcdef0123456789" // 32-char hex
	timestamp := strconv.FormatInt(time.Now().Unix(), 10)
	sig := computeSignature(method, path, timestamp, nonce, secret)

	req := httptest.NewRequest(method, path, nil)
	req.Header.Set("X-Nonce", nonce)
	req.Header.Set("X-Timestamp", timestamp)
	req.Header.Set("X-Signature", sig)
	return req
}

func newReplayGuardedRequestWithNonce(method, path, secret, nonce string) *http.Request {
	timestamp := strconv.FormatInt(time.Now().Unix(), 10)
	sig := computeSignature(method, path, timestamp, nonce, secret)

	req := httptest.NewRequest(method, path, nil)
	req.Header.Set("X-Nonce", nonce)
	req.Header.Set("X-Timestamp", timestamp)
	req.Header.Set("X-Signature", sig)
	return req
}

func newReplayGuardedRequestWithTimestamp(method, path, secret string, ts time.Time) *http.Request {
	nonce := "abcdef0123456789abcdef0123456789"
	timestamp := strconv.FormatInt(ts.Unix(), 10)
	sig := computeSignature(method, path, timestamp, nonce, secret)

	req := httptest.NewRequest(method, path, nil)
	req.Header.Set("X-Nonce", nonce)
	req.Header.Set("X-Timestamp", timestamp)
	req.Header.Set("X-Signature", sig)
	return req
}

func assertReplayErrorCode(t *testing.T, rec *httptest.ResponseRecorder, expectedCode string) {
	t.Helper()
	var body struct {
		Code string `json:"code"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("failed to decode response body: %v", err)
	}
	if body.Code != expectedCode {
		t.Fatalf("expected error code %q, got %q (body: %s)", expectedCode, body.Code, rec.Body.String())
	}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

func TestReplayGuard_ValidRequest(t *testing.T) {
	store := newFakeNonceStore()
	cfg := testReplayGuardConfig()

	var innerCalled bool
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		innerCalled = true
		w.WriteHeader(http.StatusOK)
	})

	handler := ReplayGuard(store, cfg, false)(inner)
	req := newReplayGuardedRequest("POST", "/api/v1/trades", testSecret)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if !innerCalled {
		t.Fatal("expected inner handler to be called")
	}
}

func TestReplayGuard_MissingNonce(t *testing.T) {
	store := newFakeNonceStore()
	cfg := testReplayGuardConfig()
	handler := ReplayGuard(store, cfg, false)(okHandler())

	req := httptest.NewRequest("POST", "/test", nil)
	req.Header.Set("X-Timestamp", strconv.FormatInt(time.Now().Unix(), 10))
	req.Header.Set("X-Signature", "deadbeef")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
	assertReplayErrorCode(t, rec, "REPLAY_HEADERS_MISSING")
}

func TestReplayGuard_MissingTimestamp(t *testing.T) {
	store := newFakeNonceStore()
	cfg := testReplayGuardConfig()
	handler := ReplayGuard(store, cfg, false)(okHandler())

	req := httptest.NewRequest("POST", "/test", nil)
	req.Header.Set("X-Nonce", "abcdef0123456789abcdef0123456789")
	req.Header.Set("X-Signature", "deadbeef")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
	assertReplayErrorCode(t, rec, "REPLAY_HEADERS_MISSING")
}

func TestReplayGuard_MissingSignature(t *testing.T) {
	store := newFakeNonceStore()
	cfg := testReplayGuardConfig()
	handler := ReplayGuard(store, cfg, false)(okHandler())

	req := httptest.NewRequest("POST", "/test", nil)
	req.Header.Set("X-Nonce", "abcdef0123456789abcdef0123456789")
	req.Header.Set("X-Timestamp", strconv.FormatInt(time.Now().Unix(), 10))
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
	assertReplayErrorCode(t, rec, "REPLAY_HEADERS_MISSING")
}

func TestReplayGuard_InvalidNonceFormat(t *testing.T) {
	store := newFakeNonceStore()
	cfg := testReplayGuardConfig()
	handler := ReplayGuard(store, cfg, false)(okHandler())

	req := httptest.NewRequest("POST", "/test", nil)
	req.Header.Set("X-Nonce", "too-short")
	req.Header.Set("X-Timestamp", strconv.FormatInt(time.Now().Unix(), 10))
	req.Header.Set("X-Signature", "deadbeef")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
	assertReplayErrorCode(t, rec, "REPLAY_INVALID_NONCE")
}

func TestReplayGuard_InvalidTimestamp(t *testing.T) {
	store := newFakeNonceStore()
	cfg := testReplayGuardConfig()
	handler := ReplayGuard(store, cfg, false)(okHandler())

	req := httptest.NewRequest("POST", "/test", nil)
	req.Header.Set("X-Nonce", "abcdef0123456789abcdef0123456789")
	req.Header.Set("X-Timestamp", "not-a-number")
	req.Header.Set("X-Signature", "deadbeef")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
	assertReplayErrorCode(t, rec, "REPLAY_INVALID_TIMESTAMP")
}

func TestReplayGuard_TimestampTooOld(t *testing.T) {
	store := newFakeNonceStore()
	cfg := testReplayGuardConfig()
	handler := ReplayGuard(store, cfg, false)(okHandler())

	req := newReplayGuardedRequestWithTimestamp("POST", "/test", testSecret, time.Now().Add(-5*time.Minute))
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", rec.Code)
	}
	assertReplayErrorCode(t, rec, "REPLAY_TIMESTAMP_EXPIRED")
}

func TestReplayGuard_TimestampTooFuture(t *testing.T) {
	store := newFakeNonceStore()
	cfg := testReplayGuardConfig()
	handler := ReplayGuard(store, cfg, false)(okHandler())

	req := newReplayGuardedRequestWithTimestamp("POST", "/test", testSecret, time.Now().Add(5*time.Minute))
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", rec.Code)
	}
	assertReplayErrorCode(t, rec, "REPLAY_TIMESTAMP_EXPIRED")
}

func TestReplayGuard_InvalidSignature(t *testing.T) {
	store := newFakeNonceStore()
	cfg := testReplayGuardConfig()
	handler := ReplayGuard(store, cfg, false)(okHandler())

	nonce := "abcdef0123456789abcdef0123456789"
	timestamp := strconv.FormatInt(time.Now().Unix(), 10)

	req := httptest.NewRequest("POST", "/test", nil)
	req.Header.Set("X-Nonce", nonce)
	req.Header.Set("X-Timestamp", timestamp)
	req.Header.Set("X-Signature", "0000000000000000000000000000000000000000000000000000000000000000")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", rec.Code)
	}
	assertReplayErrorCode(t, rec, "REPLAY_INVALID_SIGNATURE")
}

func TestReplayGuard_DuplicateNonce(t *testing.T) {
	store := newFakeNonceStore()
	cfg := testReplayGuardConfig()
	handler := ReplayGuard(store, cfg, false)(okHandler())

	// First request — should succeed
	req1 := newReplayGuardedRequest("POST", "/test", testSecret)
	rec1 := httptest.NewRecorder()
	handler.ServeHTTP(rec1, req1)

	if rec1.Code != http.StatusOK {
		t.Fatalf("first request: expected 200, got %d", rec1.Code)
	}

	// Second request with same nonce — should be rejected as replay
	req2 := newReplayGuardedRequest("POST", "/test", testSecret)
	rec2 := httptest.NewRecorder()
	handler.ServeHTTP(rec2, req2)

	if rec2.Code != http.StatusConflict {
		t.Fatalf("second request: expected 409, got %d", rec2.Code)
	}
	assertReplayErrorCode(t, rec2, "REPLAY_DETECTED")
}

func TestReplayGuard_Disabled(t *testing.T) {
	store := newFakeNonceStore()
	cfg := testReplayGuardConfig()

	var innerCalled bool
	inner := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		innerCalled = true
		w.WriteHeader(http.StatusOK)
	})

	// disabled = true, no headers at all
	handler := ReplayGuard(store, cfg, true)(inner)
	req := httptest.NewRequest("POST", "/test", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if !innerCalled {
		t.Fatal("expected inner handler to be called when disabled")
	}
	if len(store.consumed) != 0 {
		t.Fatal("expected nonce store to not be called when disabled")
	}
}

func TestReplayGuard_StoreError(t *testing.T) {
	store := newFakeNonceStore()
	store.err = errors.New("database connection lost")
	cfg := testReplayGuardConfig()
	handler := ReplayGuard(store, cfg, false)(okHandler())

	req := newReplayGuardedRequest("POST", "/test", testSecret)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rec.Code)
	}
	assertReplayErrorCode(t, rec, "REPLAY_STORE_ERROR")
}

func TestReplayGuard_DifferentNoncesSameTimestamp(t *testing.T) {
	store := newFakeNonceStore()
	cfg := testReplayGuardConfig()
	handler := ReplayGuard(store, cfg, false)(okHandler())

	// Two requests with different nonces — both should succeed
	req1 := newReplayGuardedRequestWithNonce("POST", "/test", testSecret, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1")
	rec1 := httptest.NewRecorder()
	handler.ServeHTTP(rec1, req1)

	if rec1.Code != http.StatusOK {
		t.Fatalf("first request: expected 200, got %d", rec1.Code)
	}

	req2 := newReplayGuardedRequestWithNonce("POST", "/test", testSecret, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa2")
	rec2 := httptest.NewRecorder()
	handler.ServeHTTP(rec2, req2)

	if rec2.Code != http.StatusOK {
		t.Fatalf("second request: expected 200, got %d", rec2.Code)
	}
}

func TestReplayGuard_NonceAtBoundaryTimestamp(t *testing.T) {
	store := newFakeNonceStore()
	cfg := testReplayGuardConfig()
	handler := ReplayGuard(store, cfg, false)(okHandler())

	// Timestamp exactly at the boundary (3 minutes ago) — should pass
	// We use 2m59s to stay within the window accounting for test execution time.
	req := newReplayGuardedRequestWithTimestamp("POST", "/test", testSecret, time.Now().Add(-2*time.Minute-59*time.Second))
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 at boundary, got %d (body: %s)", rec.Code, rec.Body.String())
	}
}
