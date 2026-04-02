package ably

import (
	"context"
	"testing"
)

// Compile-time interface checks.
var _ Publisher = (*RESTPublisher)(nil)
var _ Publisher = (*NoopPublisher)(nil)

func TestNoopPublisher_ReturnsNil(t *testing.T) {
	pub := &NoopPublisher{}
	err := pub.PublishMatchCreated(context.Background(), "match-123", MatchCreatedEvent{
		MatchID: "match-123",
		User1ID: "user-a",
		User2ID: "user-b",
		Status:  "PENDING",
	})
	if err != nil {
		t.Fatalf("NoopPublisher should never return error, got: %v", err)
	}
}
