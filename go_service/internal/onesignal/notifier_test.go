package onesignal

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestPushNotifier_NotifyMatchCreated_Success(t *testing.T) {
	var receivedPayload notificationPayload
	var receivedAuth string

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receivedAuth = r.Header.Get("Authorization")

		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("failed to read body: %v", err)
		}
		if err := json.Unmarshal(body, &receivedPayload); err != nil {
			t.Fatalf("failed to unmarshal body: %v", err)
		}

		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"id":"notification-123"}`))
	}))
	defer server.Close()

	notifier := NewPushNotifier(Config{
		AppID:      "test-app-id",
		RestAPIKey: "test-api-key",
	})
	notifier.baseURL = server.URL

	err := notifier.NotifyMatchCreated(context.Background(), "user-abc", "match-456", "Carlos")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Verify auth header
	if receivedAuth != "Key test-api-key" {
		t.Fatalf("expected auth %q, got %q", "Key test-api-key", receivedAuth)
	}

	// Verify payload
	if receivedPayload.AppID != "test-app-id" {
		t.Fatalf("expected app_id %q, got %q", "test-app-id", receivedPayload.AppID)
	}
	if receivedPayload.TargetChannel != "push" {
		t.Fatalf("expected target_channel %q, got %q", "push", receivedPayload.TargetChannel)
	}

	externalIDs := receivedPayload.IncludeAliases["external_id"]
	if len(externalIDs) != 1 || externalIDs[0] != "user-abc" {
		t.Fatalf("expected external_id [user-abc], got %v", externalIDs)
	}

	if receivedPayload.Contents["en"] != "Carlos wants to trade with you!" {
		t.Fatalf("unexpected contents: %q", receivedPayload.Contents["en"])
	}

	if receivedPayload.Data["match_id"] != "match-456" {
		t.Fatalf("expected data.match_id %q, got %q", "match-456", receivedPayload.Data["match_id"])
	}
	if receivedPayload.Data["type"] != "match_created" {
		t.Fatalf("expected data.type %q, got %q", "match_created", receivedPayload.Data["type"])
	}
}

func TestPushNotifier_NotifyMatchCreated_ServerError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer server.Close()

	notifier := NewPushNotifier(Config{
		AppID:      "test-app-id",
		RestAPIKey: "test-api-key",
	})
	notifier.baseURL = server.URL

	err := notifier.NotifyMatchCreated(context.Background(), "user-abc", "match-456", "Carlos")
	if err == nil {
		t.Fatal("expected error for server error response")
	}
}

func TestPushNotifier_NotifyMatchCreated_NetworkError(t *testing.T) {
	notifier := NewPushNotifier(Config{
		AppID:      "test-app-id",
		RestAPIKey: "test-api-key",
	})
	notifier.baseURL = "http://localhost:1" // unreachable port

	err := notifier.NotifyMatchCreated(context.Background(), "user-abc", "match-456", "Carlos")
	if err == nil {
		t.Fatal("expected error for network failure")
	}
}

func TestNoopNotifier(t *testing.T) {
	notifier := &NoopNotifier{}
	err := notifier.NotifyMatchCreated(context.Background(), "user-abc", "match-456", "Carlos")
	if err != nil {
		t.Fatalf("NoopNotifier should never return error, got: %v", err)
	}
}
