package middleware

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/attestation"
)

// Compile-time check that fakeVerifier implements IntegrityChecker.
var _ attestation.IntegrityChecker = (*fakeVerifier)(nil)

type fakeVerifier struct {
	androidErr error
	iosErr     error
	called     bool
}

func (f *fakeVerifier) VerifyAndroid(_ context.Context, _ string) error {
	f.called = true
	return f.androidErr
}

func (f *fakeVerifier) VerifyIOS(_ context.Context, _ string) error {
	f.called = true
	return f.iosErr
}

// okHandler returns 200 when the middleware chain passes.
func okHandler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"ok":true}`))
	})
}

func TestVerifyAttestation_Android_Valid(t *testing.T) {
	v := &fakeVerifier{}
	handler := VerifyAttestation(v, false)(okHandler())

	req := httptest.NewRequest("POST", "/api/v1/ably/auth", nil)
	req.Header.Set("X-Attestation-Token", "android-token")
	req.Header.Set("X-Attestation-Platform", "android")
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if !v.called {
		t.Fatal("expected verifier to be called")
	}
}

func TestVerifyAttestation_iOS_Valid(t *testing.T) {
	v := &fakeVerifier{}
	handler := VerifyAttestation(v, false)(okHandler())

	req := httptest.NewRequest("POST", "/api/v1/ably/auth", nil)
	req.Header.Set("X-Attestation-Token", "ios-assertion")
	req.Header.Set("X-Attestation-Platform", "ios")
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
	if !v.called {
		t.Fatal("expected verifier to be called")
	}
}

func TestVerifyAttestation_MissingToken(t *testing.T) {
	v := &fakeVerifier{}
	handler := VerifyAttestation(v, false)(okHandler())

	req := httptest.NewRequest("POST", "/api/v1/ably/auth", nil)
	req.Header.Set("X-Attestation-Platform", "android")
	// Missing X-Attestation-Token
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", rec.Code)
	}
	assertErrorCode(t, rec, "ATTESTATION_MISSING")
}

func TestVerifyAttestation_MissingPlatform(t *testing.T) {
	v := &fakeVerifier{}
	handler := VerifyAttestation(v, false)(okHandler())

	req := httptest.NewRequest("POST", "/api/v1/ably/auth", nil)
	req.Header.Set("X-Attestation-Token", "some-token")
	// Missing X-Attestation-Platform
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", rec.Code)
	}
	assertErrorCode(t, rec, "ATTESTATION_MISSING")
}

func TestVerifyAttestation_InvalidPlatform(t *testing.T) {
	v := &fakeVerifier{}
	handler := VerifyAttestation(v, false)(okHandler())

	req := httptest.NewRequest("POST", "/api/v1/ably/auth", nil)
	req.Header.Set("X-Attestation-Token", "some-token")
	req.Header.Set("X-Attestation-Platform", "windows")
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", rec.Code)
	}
	assertErrorCode(t, rec, "ATTESTATION_INVALID_PLATFORM")
}

func TestVerifyAttestation_VerificationFails(t *testing.T) {
	v := &fakeVerifier{androidErr: errors.New("fake: device rooted")}
	handler := VerifyAttestation(v, false)(okHandler())

	req := httptest.NewRequest("POST", "/api/v1/ably/auth", nil)
	req.Header.Set("X-Attestation-Token", "bad-token")
	req.Header.Set("X-Attestation-Platform", "android")
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", rec.Code)
	}
	assertErrorCode(t, rec, "ATTESTATION_FAILED")
}

func TestVerifyAttestation_Disabled(t *testing.T) {
	v := &fakeVerifier{}
	handler := VerifyAttestation(v, true)(okHandler()) // disabled = true

	req := httptest.NewRequest("POST", "/api/v1/ably/auth", nil)
	// No attestation headers at all
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 (disabled mode), got %d", rec.Code)
	}
	if v.called {
		t.Fatal("verifier should NOT be called when disabled")
	}
}

// assertErrorCode checks that the response body contains the expected error code.
func assertErrorCode(t *testing.T, rec *httptest.ResponseRecorder, expectedCode string) {
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
