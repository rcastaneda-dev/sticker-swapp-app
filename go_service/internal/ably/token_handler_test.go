package ably

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

// mockParticipantChecker implements matches.ParticipantChecker for tests.
type mockParticipantChecker struct {
	isParticipant bool
	err           error
	calledUserID  string
	calledMatchID string
}

func (m *mockParticipantChecker) IsParticipant(_ context.Context, userID, matchID string) (bool, error) {
	m.calledUserID = userID
	m.calledMatchID = matchID
	return m.isParticipant, m.err
}

// testConfig returns a valid Config for testing.
func testConfig() Config {
	return Config{
		APIKey:         "appId.keyId:keySecret",
		SupabaseURL:    "https://example.supabase.co",
		SupabaseSecret: "test-secret",
	}
}

func newTestTokenRequest(userID string, body interface{}) *http.Request {
	var bodyBytes []byte
	if body != nil {
		bodyBytes, _ = json.Marshal(body)
	}
	req := httptest.NewRequest("POST", "/api/v1/ably/auth", bytes.NewReader(bodyBytes))
	req.Header.Set("Content-Type", "application/json")
	if userID != "" {
		ctx := context.WithValue(req.Context(), UserIDKey(), userID)
		req = req.WithContext(ctx)
	}
	return req
}

func assertTokenErrorCode(t *testing.T, rec *httptest.ResponseRecorder, expectedCode string) {
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

func TestIssueToken_WithoutMatchID(t *testing.T) {
	checker := &mockParticipantChecker{}
	handler := NewTokenHandler(testConfig(), checker)

	req := newTestTokenRequest("11111111-1111-1111-1111-111111111111", nil)
	rec := httptest.NewRecorder()
	handler.IssueToken(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	// ParticipantChecker should NOT be called when no matchId
	if checker.calledUserID != "" {
		t.Fatal("participant checker should not be called without matchId")
	}

	// Response should contain a valid token request
	var resp tokenResponse
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if resp.TokenRequest.KeyName == "" {
		t.Fatal("expected non-empty keyName")
	}
	if resp.TokenRequest.ClientID != "11111111-1111-1111-1111-111111111111" {
		t.Fatalf("expected clientId to match user ID, got %q", resp.TokenRequest.ClientID)
	}
	if resp.TokenRequest.Mac == "" {
		t.Fatal("expected non-empty mac")
	}
}

func TestIssueToken_WithMatchID_ValidParticipant(t *testing.T) {
	checker := &mockParticipantChecker{isParticipant: true}
	handler := NewTokenHandler(testConfig(), checker)

	body := map[string]string{"matchId": "22222222-2222-2222-2222-222222222222"}
	req := newTestTokenRequest("11111111-1111-1111-1111-111111111111", body)
	rec := httptest.NewRecorder()
	handler.IssueToken(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	if checker.calledUserID != "11111111-1111-1111-1111-111111111111" {
		t.Fatalf("expected userID %q, got %q", "11111111-1111-1111-1111-111111111111", checker.calledUserID)
	}
	if checker.calledMatchID != "22222222-2222-2222-2222-222222222222" {
		t.Fatalf("expected matchID %q, got %q", "22222222-2222-2222-2222-222222222222", checker.calledMatchID)
	}

	// Capability should include the match channel
	var resp tokenResponse
	json.NewDecoder(rec.Body).Decode(&resp)
	var caps map[string][]string
	json.Unmarshal([]byte(resp.TokenRequest.Capability), &caps)

	matchChan := "match:22222222-2222-2222-2222-222222222222"
	if _, ok := caps[matchChan]; !ok {
		t.Fatalf("expected capability for channel %q, got %v", matchChan, caps)
	}
}

func TestIssueToken_WithMatchID_NotParticipant(t *testing.T) {
	checker := &mockParticipantChecker{isParticipant: false}
	handler := NewTokenHandler(testConfig(), checker)

	body := map[string]string{"matchId": "22222222-2222-2222-2222-222222222222"}
	req := newTestTokenRequest("11111111-1111-1111-1111-111111111111", body)
	rec := httptest.NewRecorder()
	handler.IssueToken(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d: %s", rec.Code, rec.Body.String())
	}
	assertTokenErrorCode(t, rec, "NOT_PARTICIPANT")
}

func TestIssueToken_WithMatchID_InvalidUUID(t *testing.T) {
	checker := &mockParticipantChecker{}
	handler := NewTokenHandler(testConfig(), checker)

	body := map[string]string{"matchId": "not-a-uuid"}
	req := newTestTokenRequest("11111111-1111-1111-1111-111111111111", body)
	rec := httptest.NewRecorder()
	handler.IssueToken(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
	}
	assertTokenErrorCode(t, rec, "INVALID_PARAMS")

	// ParticipantChecker should NOT be called for invalid UUID
	if checker.calledUserID != "" {
		t.Fatal("participant checker should not be called for invalid UUID")
	}
}

func TestIssueToken_WithMatchID_DBError(t *testing.T) {
	checker := &mockParticipantChecker{err: errors.New("connection lost")}
	handler := NewTokenHandler(testConfig(), checker)

	body := map[string]string{"matchId": "22222222-2222-2222-2222-222222222222"}
	req := newTestTokenRequest("11111111-1111-1111-1111-111111111111", body)
	rec := httptest.NewRecorder()
	handler.IssueToken(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d: %s", rec.Code, rec.Body.String())
	}
	assertTokenErrorCode(t, rec, "VALIDATION_ERROR")
}

func TestIssueToken_Unauthorized(t *testing.T) {
	checker := &mockParticipantChecker{}
	handler := NewTokenHandler(testConfig(), checker)

	req := newTestTokenRequest("", nil)
	rec := httptest.NewRecorder()
	handler.IssueToken(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d: %s", rec.Code, rec.Body.String())
	}
	assertTokenErrorCode(t, rec, "AUTH_REQUIRED")
}
