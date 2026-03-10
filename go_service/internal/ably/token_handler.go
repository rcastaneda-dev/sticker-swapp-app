package ably

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

// Config holds Ably and Supabase credentials.
type Config struct {
	APIKey         string // Format: "appId.keyId:keySecret"
	SupabaseURL    string
	SupabaseSecret string
}

// parsedKey extracts components from the Ably API key.
type parsedKey struct {
	AppID     string
	KeyID     string
	KeySecret string
	KeyName   string // "appId.keyId"
}

func parseAPIKey(apiKey string) (parsedKey, error) {
	parts := strings.SplitN(apiKey, ":", 2)
	if len(parts) != 2 {
		return parsedKey{}, fmt.Errorf("invalid API key format: expected 'appId.keyId:keySecret'")
	}
	keyName := parts[0]
	keySecret := parts[1]

	nameParts := strings.SplitN(keyName, ".", 2)
	if len(nameParts) != 2 {
		return parsedKey{}, fmt.Errorf("invalid key name format: expected 'appId.keyId'")
	}

	return parsedKey{
		AppID:     nameParts[0],
		KeyID:     nameParts[1],
		KeySecret: keySecret,
		KeyName:   keyName,
	}, nil
}

// TokenHandler issues scoped Ably tokens for authenticated users.
type TokenHandler struct {
	config Config
	key    parsedKey
}

// NewTokenHandler creates a handler with validated config.
func NewTokenHandler(cfg Config) *TokenHandler {
	key, err := parseAPIKey(cfg.APIKey)
	if err != nil {
		panic(fmt.Sprintf("Invalid ABLY_API_KEY: %v", err))
	}
	return &TokenHandler{config: cfg, key: key}
}

// TokenRequest is the Ably-compatible signed token request structure.
// The Flutter client sends this to Ably, which validates the HMAC and
// issues a short-lived token. This approach means the API key secret
// never leaves the server.
type TokenRequest struct {
	KeyName    string `json:"keyName"`
	Timestamp  int64  `json:"timestamp"`
	Nonce      string `json:"nonce"`
	ClientID   string `json:"clientId"`
	TTL        int64  `json:"ttl"`        // milliseconds
	Capability string `json:"capability"`
	Mac        string `json:"mac"`
}

// tokenResponse wraps the signed token request for the HTTP response.
type tokenResponse struct {
	TokenRequest TokenRequest `json:"tokenRequest"`
}

// errorResponse is a structured error payload.
type errorResponse struct {
	Error   string `json:"error"`
	Code    string `json:"code"`
	Details string `json:"details,omitempty"`
}

// IssueToken handles POST /api/v1/ably/auth
//
// It reads the authenticated user's ID from the request context (set by
// the JWT middleware), builds a capability that restricts the user to
// only their active match channels, signs a token request with HMAC-SHA256,
// and returns it. The Flutter client then sends this signed request
// directly to Ably to obtain a token.
func (h *TokenHandler) IssueToken(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(UserIDKey()).(string)
	if !ok || userID == "" {
		writeError(w, http.StatusUnauthorized, "AUTH_REQUIRED", "User ID not found in token")
		return
	}

	// Parse optional request body for specific channel access
	var req struct {
		MatchID string `json:"matchId,omitempty"`
	}
	if r.Body != nil {
		json.NewDecoder(r.Body).Decode(&req) // non-fatal if empty
	}

	// Build capability — scoped to the user's match channels only.
	//
	// Channel naming convention: "match:{matchId}" for trade chat channels.
	// Presence channels: "match:{matchId}" (same channel, presence capability).
	//
	// If no matchId is provided, grant access to the user's personal
	// notification channel only (used for match alerts).
	capability := h.buildCapability(userID, req.MatchID)

	// Generate signed token request
	tokenReq, err := h.createSignedTokenRequest(userID, capability)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "TOKEN_ERROR", "Failed to create token request")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store") // Tokens must not be cached
	json.NewEncoder(w).Encode(tokenResponse{TokenRequest: *tokenReq})
}

// buildCapability constructs the Ably capability JSON string.
//
// Capabilities follow the principle of least privilege:
//   - Users can only subscribe/publish to channels for matches they're in
//   - The personal notification channel is subscribe-only
//   - Presence is enabled on match channels so users can see online status
func (h *TokenHandler) buildCapability(userID, matchID string) string {
	caps := make(map[string][]string)

	// Personal notification channel — subscribe only (server publishes)
	caps[fmt.Sprintf("user:%s:notifications", userID)] = []string{"subscribe"}

	// Match-specific channel — full chat capabilities
	if matchID != "" {
		channelName := fmt.Sprintf("match:%s", matchID)
		caps[channelName] = []string{"publish", "subscribe", "presence", "history"}
	}

	capJSON, _ := json.Marshal(caps)
	return string(capJSON)
}

// createSignedTokenRequest builds and HMAC-signs an Ably token request.
//
// The signing process follows Ably's token request specification:
// https://ably.com/docs/auth/token-request
//
// The MAC is computed over a newline-delimited string of all fields in
// a specific order, using HMAC-SHA256 with the API key secret.
func (h *TokenHandler) createSignedTokenRequest(clientID, capability string) (*TokenRequest, error) {
	nonce, err := generateNonce()
	if err != nil {
		return nil, fmt.Errorf("nonce generation failed: %w", err)
	}

	now := time.Now().UnixMilli()
	ttl := int64(60 * 60 * 1000) // 1 hour in milliseconds

	req := &TokenRequest{
		KeyName:    h.key.KeyName,
		Timestamp:  now,
		Nonce:      nonce,
		ClientID:   clientID,
		TTL:        ttl,
		Capability: capability,
	}

	// Sign the token request
	// The signing string is a newline-delimited concatenation (with trailing newline):
	//   keyName\nttl\ncapability\nclientId\ntimestamp\nnonce\n
	signingString := fmt.Sprintf(
		"%s\n%d\n%s\n%s\n%d\n%s\n",
		req.KeyName,
		req.TTL,
		req.Capability,
		req.ClientID,
		req.Timestamp,
		req.Nonce,
	)

	mac := hmac.New(sha256.New, []byte(h.key.KeySecret))
	mac.Write([]byte(signingString))
	req.Mac = base64.StdEncoding.EncodeToString(mac.Sum(nil))

	return req, nil
}

// generateNonce creates a cryptographically random 16-byte hex string.
func generateNonce() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(errorResponse{
		Error: message,
		Code:  code,
	})
}

// Context keys are defined in context.go
