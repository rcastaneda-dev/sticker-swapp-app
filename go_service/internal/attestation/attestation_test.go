package attestation

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/fxamacker/cbor/v2"
)

// --- Android (Play Integrity) Tests ---

func TestVerifyAndroid_ValidToken(t *testing.T) {
	// Mock Google Play Integrity API returning a valid verdict
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		payload := playIntegrityPayload{}
		payload.TokenPayloadExternal.AppIntegrity.AppRecognitionVerdict = "PLAY_RECOGNIZED"
		payload.TokenPayloadExternal.DeviceIntegrity.DeviceRecognitionVerdict = []string{
			"MEETS_DEVICE_INTEGRITY", "MEETS_BASIC_INTEGRITY",
		}
		payload.TokenPayloadExternal.AccountDetails.AppLicensingVerdict = "LICENSED"
		json.NewEncoder(w).Encode(payload)
	}))
	defer server.Close()

	v := NewVerifier("123456789", "TEAMID.com.worldcup.stickers")
	v.playIntegrityURL = server.URL
	v.httpClient = server.Client()

	err := v.VerifyAndroid(context.Background(), "valid-token")
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}
}

func TestVerifyAndroid_InvalidVerdict(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		payload := playIntegrityPayload{}
		payload.TokenPayloadExternal.AppIntegrity.AppRecognitionVerdict = "UNRECOGNIZED_VERSION"
		payload.TokenPayloadExternal.DeviceIntegrity.DeviceRecognitionVerdict = []string{
			"MEETS_DEVICE_INTEGRITY",
		}
		json.NewEncoder(w).Encode(payload)
	}))
	defer server.Close()

	v := NewVerifier("123456789", "")
	v.playIntegrityURL = server.URL
	v.httpClient = server.Client()

	err := v.VerifyAndroid(context.Background(), "bad-app-token")
	if err == nil {
		t.Fatal("expected error for unrecognized app, got nil")
	}
}

func TestVerifyAndroid_DeviceIntegrityFail(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		payload := playIntegrityPayload{}
		payload.TokenPayloadExternal.AppIntegrity.AppRecognitionVerdict = "PLAY_RECOGNIZED"
		payload.TokenPayloadExternal.DeviceIntegrity.DeviceRecognitionVerdict = []string{
			"MEETS_BASIC_INTEGRITY", // missing MEETS_DEVICE_INTEGRITY
		}
		json.NewEncoder(w).Encode(payload)
	}))
	defer server.Close()

	v := NewVerifier("123456789", "")
	v.playIntegrityURL = server.URL
	v.httpClient = server.Client()

	err := v.VerifyAndroid(context.Background(), "rooted-device-token")
	if err == nil {
		t.Fatal("expected error for device integrity failure, got nil")
	}
}

func TestVerifyAndroid_EmptyToken(t *testing.T) {
	v := NewVerifier("123456789", "")
	err := v.VerifyAndroid(context.Background(), "")
	if err == nil {
		t.Fatal("expected error for empty token, got nil")
	}
}

func TestVerifyAndroid_APIError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		w.Write([]byte(`{"error":"invalid token"}`))
	}))
	defer server.Close()

	v := NewVerifier("123456789", "")
	v.playIntegrityURL = server.URL
	v.httpClient = server.Client()

	err := v.VerifyAndroid(context.Background(), "invalid-format-token")
	if err == nil {
		t.Fatal("expected error for API error response, got nil")
	}
}

func TestVerifyAndroid_TokenWithSpecialChars(t *testing.T) {
	// Verify that tokens containing JSON-breaking characters are safely marshalled
	// (prevents JSON injection via fmt.Sprintf → json.Marshal fix)
	var receivedBody string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := readBody(r)
		receivedBody = body

		// Parse the request body to verify it's valid JSON
		var req map[string]string
		if err := json.Unmarshal([]byte(body), &req); err != nil {
			t.Errorf("request body is not valid JSON: %v", err)
			w.WriteHeader(http.StatusBadRequest)
			return
		}

		// Return a valid verdict so we can inspect the request
		payload := playIntegrityPayload{}
		payload.TokenPayloadExternal.AppIntegrity.AppRecognitionVerdict = "PLAY_RECOGNIZED"
		payload.TokenPayloadExternal.DeviceIntegrity.DeviceRecognitionVerdict = []string{
			"MEETS_DEVICE_INTEGRITY",
		}
		json.NewEncoder(w).Encode(payload)
	}))
	defer server.Close()

	v := NewVerifier("123456789", "")
	v.playIntegrityURL = server.URL
	v.httpClient = server.Client()

	// Token with characters that would break fmt.Sprintf JSON construction
	maliciousToken := `","evil":"injected","x":"`
	err := v.VerifyAndroid(context.Background(), maliciousToken)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Verify the token was properly escaped in the JSON body
	var parsed map[string]string
	if err := json.Unmarshal([]byte(receivedBody), &parsed); err != nil {
		t.Fatalf("response body is not valid JSON: %v", err)
	}
	if parsed["integrity_token"] != maliciousToken {
		t.Errorf("token was not properly preserved: got %q, want %q", parsed["integrity_token"], maliciousToken)
	}
}

func readBody(r *http.Request) (string, error) {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		return "", err
	}
	return string(body), nil
}

// --- iOS (App Attest) Tests ---

func TestVerifyIOS_EmptyAssertion(t *testing.T) {
	v := NewVerifier("", "TEAMID.com.worldcup.stickers")
	err := v.VerifyIOS(context.Background(), "")
	if err == nil {
		t.Fatal("expected error for empty assertion, got nil")
	}
}

func TestVerifyIOS_InvalidBase64(t *testing.T) {
	v := NewVerifier("", "TEAMID.com.worldcup.stickers")
	err := v.VerifyIOS(context.Background(), "not-valid-base64!!!")
	if err == nil {
		t.Fatal("expected error for invalid base64, got nil")
	}
}

func TestVerifyIOS_InvalidCBOR(t *testing.T) {
	// Valid base64, but not valid CBOR
	data := base64.StdEncoding.EncodeToString([]byte("not cbor data"))
	v := NewVerifier("", "TEAMID.com.worldcup.stickers")
	err := v.VerifyIOS(context.Background(), data)
	if err == nil {
		t.Fatal("expected error for invalid CBOR, got nil")
	}
}

func TestVerifyIOS_NoCertificates(t *testing.T) {
	// Valid CBOR but no x5c certificates
	assertion := appAttestAssertion{
		Fmt:      "apple-appattest",
		AttStmt:  attStmt{X5c: [][]byte{}},
		AuthData: make([]byte, 37),
	}
	encoded, _ := cbor.Marshal(assertion)
	data := base64.StdEncoding.EncodeToString(encoded)

	v := NewVerifier("", "TEAMID.com.worldcup.stickers")
	err := v.VerifyIOS(context.Background(), data)
	if err == nil {
		t.Fatal("expected error for missing certificates, got nil")
	}
}

func TestVerifyIOS_InvalidCertificate(t *testing.T) {
	// Valid CBOR with garbage certificate bytes
	assertion := appAttestAssertion{
		Fmt: "apple-appattest",
		AttStmt: attStmt{
			X5c: [][]byte{[]byte("not-a-real-certificate")},
		},
		AuthData: make([]byte, 37),
	}
	encoded, _ := cbor.Marshal(assertion)
	data := base64.StdEncoding.EncodeToString(encoded)

	v := NewVerifier("", "TEAMID.com.worldcup.stickers")
	err := v.VerifyIOS(context.Background(), data)
	if err == nil {
		t.Fatal("expected error for invalid certificate, got nil")
	}
}

// --- Helper Tests ---

func TestContainsVerdict(t *testing.T) {
	verdicts := []string{"MEETS_BASIC_INTEGRITY", "MEETS_DEVICE_INTEGRITY"}

	if !containsVerdict(verdicts, "MEETS_DEVICE_INTEGRITY") {
		t.Error("expected true for present verdict")
	}
	if containsVerdict(verdicts, "MEETS_STRONG_INTEGRITY") {
		t.Error("expected false for absent verdict")
	}
	if containsVerdict(nil, "MEETS_DEVICE_INTEGRITY") {
		t.Error("expected false for nil slice")
	}
}
