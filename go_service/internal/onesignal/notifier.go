package onesignal

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"time"
)

// Notifier sends push notifications to users.
type Notifier interface {
	NotifyMatchCreated(ctx context.Context, recipientUserID, matchID, senderDisplayName string) error
}

// Config holds OneSignal API credentials.
type Config struct {
	AppID      string
	RestAPIKey string
}

// PushNotifier sends push notifications via OneSignal REST API.
type PushNotifier struct {
	config  Config
	client  *http.Client
	baseURL string // overridable for tests
}

// NewPushNotifier creates a production notifier.
func NewPushNotifier(cfg Config) *PushNotifier {
	return &PushNotifier{
		config:  cfg,
		client:  &http.Client{Timeout: 5 * time.Second},
		baseURL: "https://api.onesignal.com",
	}
}

// notificationPayload is the OneSignal REST API request body.
type notificationPayload struct {
	AppID          string              `json:"app_id"`
	IncludeAliases map[string][]string `json:"include_aliases"`
	TargetChannel  string              `json:"target_channel"`
	Headings       map[string]string   `json:"headings"`
	Contents       map[string]string   `json:"contents"`
	Data           map[string]string   `json:"data"`
}

// NotifyMatchCreated sends a push to the recipient when a mutual match is created.
func (n *PushNotifier) NotifyMatchCreated(ctx context.Context, recipientUserID, matchID, senderDisplayName string) error {
	payload := notificationPayload{
		AppID: n.config.AppID,
		IncludeAliases: map[string][]string{
			"external_id": {recipientUserID},
		},
		TargetChannel: "push",
		Headings:      map[string]string{"en": "New Match!"},
		Contents:      map[string]string{"en": fmt.Sprintf("%s wants to trade with you!", senderDisplayName)},
		Data:          map[string]string{"match_id": matchID, "type": "match_created"},
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal payload: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", n.baseURL+"/notifications", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Key "+n.config.RestAPIKey)

	resp, err := n.client.Do(req)
	if err != nil {
		return fmt.Errorf("send notification: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		slog.Warn("OneSignal push failed",
			"status", resp.StatusCode,
			"recipient", recipientUserID,
			"match_id", matchID,
		)
		return fmt.Errorf("onesignal returned %d", resp.StatusCode)
	}

	slog.Info("Match push sent",
		"recipient", recipientUserID,
		"match_id", matchID,
	)
	return nil
}

// NoopNotifier silently succeeds (for dev/test when push is disabled).
type NoopNotifier struct{}

func (n *NoopNotifier) NotifyMatchCreated(_ context.Context, _, _, _ string) error {
	return nil
}
