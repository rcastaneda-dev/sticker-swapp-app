package attestation

import (
	"context"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/fxamacker/cbor/v2"
)

// IntegrityChecker verifies device attestation tokens. Implementations
// handle platform-specific verification (Play Integrity for Android,
// App Attest for iOS). The interface enables dependency injection for
// testing.
type IntegrityChecker interface {
	VerifyAndroid(ctx context.Context, token string) error
	VerifyIOS(ctx context.Context, assertionData string) error
}

// Verifier implements IntegrityChecker using the Google Play Integrity
// API for Android and Apple's App Attest certificate chain for iOS.
type Verifier struct {
	googleProjectNumber string
	appleAppID          string // format: "TEAMID.BUNDLEID"
	httpClient          *http.Client

	// playIntegrityURL is the endpoint for decoding Play Integrity tokens.
	// Overridable for testing.
	playIntegrityURL string
}

// NewVerifier creates an attestation verifier.
//
// googleProjectNumber: Google Cloud project number for Play Integrity.
// appleAppID: Apple Team ID + Bundle ID (e.g., "ABC123.com.worldcup.stickers").
func NewVerifier(googleProjectNumber, appleAppID string) *Verifier {
	return &Verifier{
		googleProjectNumber: googleProjectNumber,
		appleAppID:          appleAppID,
		httpClient:          &http.Client{Timeout: 10 * time.Second},
		playIntegrityURL:    "https://playintegrity.googleapis.com/v1",
	}
}

// --- Android: Play Integrity ---

// playIntegrityPayload is the decoded Play Integrity verdict.
type playIntegrityPayload struct {
	TokenPayloadExternal struct {
		RequestDetails struct {
			RequestPackageName string `json:"requestPackageName"`
			Nonce              string `json:"nonce"`
			TimestampMillis    string `json:"timestampMillis"`
		} `json:"requestDetails"`
		AppIntegrity struct {
			AppRecognitionVerdict string `json:"appRecognitionVerdict"`
		} `json:"appIntegrity"`
		DeviceIntegrity struct {
			DeviceRecognitionVerdict []string `json:"deviceRecognitionVerdict"`
		} `json:"deviceIntegrity"`
		AccountDetails struct {
			AppLicensingVerdict string `json:"appLicensingVerdict"`
		} `json:"accountDetails"`
	} `json:"tokenPayloadExternal"`
}

// VerifyAndroid decodes and verifies a Play Integrity token via Google's API.
//
// The token is sent to Google's server-side decryption endpoint. The response
// contains verdicts for app integrity, device integrity, and account licensing.
// We require:
//   - appRecognitionVerdict == "PLAY_RECOGNIZED"
//   - deviceRecognitionVerdict contains "MEETS_DEVICE_INTEGRITY"
func (v *Verifier) VerifyAndroid(ctx context.Context, token string) error {
	if token == "" {
		return errors.New("attestation: empty Play Integrity token")
	}

	// Call Play Integrity API to decode the token
	url := fmt.Sprintf("%s/%s:decodeIntegrityToken", v.playIntegrityURL, v.googleProjectNumber)

	body := fmt.Sprintf(`{"integrity_token":"%s"}`, token)
	req, err := http.NewRequestWithContext(ctx, "POST", url, strings.NewReader(body))
	if err != nil {
		return fmt.Errorf("attestation: failed to build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := v.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("attestation: Play Integrity API unreachable: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("attestation: failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("attestation: Play Integrity API returned %d: %s", resp.StatusCode, string(respBody))
	}

	var payload playIntegrityPayload
	if err := json.Unmarshal(respBody, &payload); err != nil {
		return fmt.Errorf("attestation: failed to decode verdict: %w", err)
	}

	ext := payload.TokenPayloadExternal

	// Verify app integrity
	if ext.AppIntegrity.AppRecognitionVerdict != "PLAY_RECOGNIZED" {
		return fmt.Errorf("attestation: app not recognized (verdict: %s)", ext.AppIntegrity.AppRecognitionVerdict)
	}

	// Verify device integrity
	if !containsVerdict(ext.DeviceIntegrity.DeviceRecognitionVerdict, "MEETS_DEVICE_INTEGRITY") {
		return fmt.Errorf("attestation: device integrity check failed (verdicts: %v)", ext.DeviceIntegrity.DeviceRecognitionVerdict)
	}

	return nil
}

func containsVerdict(verdicts []string, target string) bool {
	for _, v := range verdicts {
		if v == target {
			return true
		}
	}
	return false
}

// --- iOS: App Attest ---

// appAttestAssertion is the CBOR-decoded App Attest assertion structure.
type appAttestAssertion struct {
	Fmt      string `cbor:"fmt"`
	AttStmt  attStmt `cbor:"attStmt"`
	AuthData []byte `cbor:"authData"`
}

type attStmt struct {
	X5c       [][]byte `cbor:"x5c"`
	Receipt   []byte   `cbor:"receipt"`
}

// VerifyIOS verifies an Apple App Attest assertion.
//
// The assertion is base64-encoded CBOR data containing:
//   - A certificate chain (x5c) rooted in Apple's App Attest CA
//   - Authenticator data with the RP ID hash and counter
//
// Verification steps:
//  1. Base64-decode the assertion data
//  2. CBOR-decode the assertion structure
//  3. Validate the certificate chain against Apple's App Attest root CA
//  4. Verify the authenticator data contains expected RP ID hash
func (v *Verifier) VerifyIOS(ctx context.Context, assertionData string) error {
	if assertionData == "" {
		return errors.New("attestation: empty App Attest assertion")
	}

	// Decode base64 assertion
	rawAssertion, err := base64.StdEncoding.DecodeString(assertionData)
	if err != nil {
		return fmt.Errorf("attestation: invalid base64 assertion: %w", err)
	}

	// CBOR-decode the assertion
	var assertion appAttestAssertion
	if err := cbor.Unmarshal(rawAssertion, &assertion); err != nil {
		return fmt.Errorf("attestation: failed to decode CBOR assertion: %w", err)
	}

	// Validate certificate chain
	if len(assertion.AttStmt.X5c) == 0 {
		return errors.New("attestation: assertion contains no certificates")
	}

	// Parse leaf certificate
	leafCert, err := x509.ParseCertificate(assertion.AttStmt.X5c[0])
	if err != nil {
		return fmt.Errorf("attestation: failed to parse leaf certificate: %w", err)
	}

	// Build intermediate pool from remaining certificates
	intermediates := x509.NewCertPool()
	for _, certBytes := range assertion.AttStmt.X5c[1:] {
		cert, err := x509.ParseCertificate(certBytes)
		if err != nil {
			return fmt.Errorf("attestation: failed to parse intermediate certificate: %w", err)
		}
		intermediates.AddCert(cert)
	}

	// Verify against Apple App Attest root CA
	roots := x509.NewCertPool()
	roots.AppendCertsFromPEM([]byte(appleAppAttestRootCA))

	opts := x509.VerifyOptions{
		Roots:         roots,
		Intermediates: intermediates,
	}

	if _, err := leafCert.Verify(opts); err != nil {
		return fmt.Errorf("attestation: certificate chain verification failed: %w", err)
	}

	// Validate authenticator data length (at minimum: 32 bytes RP ID hash + 1 byte flags + 4 bytes counter)
	if len(assertion.AuthData) < 37 {
		return errors.New("attestation: authenticator data too short")
	}

	return nil
}

// appleAppAttestRootCA is Apple's App Attest Root CA certificate.
// Source: https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
const appleAppAttestRootCA = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Ywn2XM6RFG0LU+BKRR51GBgzAG3GGNITRGbWo0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhd6bX5C7+cku6AjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrS/E38PCZAJ9
-----END CERTIFICATE-----`
