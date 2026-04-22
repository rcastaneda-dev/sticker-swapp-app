package ably

import (
	"context"
	"fmt"
	"log/slog"

	ablySDK "github.com/ably/ably-go/ably"
)

// Publisher publishes server-side events to Ably channels.
type Publisher interface {
	PublishMatchCreated(ctx context.Context, matchID string, event MatchCreatedEvent) error
	PublishTradeConfirmed(ctx context.Context, matchID string, event TradeConfirmedEvent) error
}

// MatchCreatedEvent is the payload for the match channel creation event.
type MatchCreatedEvent struct {
	MatchID   string `json:"match_id"`
	User1ID   string `json:"user1_id"`
	User2ID   string `json:"user2_id"`
	Status    string `json:"status"`
	CreatedAt string `json:"created_at"`
}

// TradeConfirmedEvent is the payload for a trade confirmation event.
type TradeConfirmedEvent struct {
	MatchID       string `json:"match_id"`
	ConfirmedBy   string `json:"confirmed_by"`
	BothConfirmed bool   `json:"both_confirmed"`
	MatchStatus   string `json:"match_status"`
}

// RESTPublisher publishes events via the Ably REST SDK.
type RESTPublisher struct {
	client *ablySDK.REST
}

// NewRESTPublisher creates a publisher backed by the Ably REST SDK.
func NewRESTPublisher(apiKey string) (*RESTPublisher, error) {
	client, err := ablySDK.NewREST(ablySDK.WithKey(apiKey))
	if err != nil {
		return nil, fmt.Errorf("ably REST client init: %w", err)
	}
	return &RESTPublisher{client: client}, nil
}

// PublishMatchCreated publishes a system event to the match channel.
// This establishes the channel and the first persisted message.
func (p *RESTPublisher) PublishMatchCreated(ctx context.Context, matchID string, event MatchCreatedEvent) error {
	channelName := fmt.Sprintf("match:%s", matchID)
	channel := p.client.Channels.Get(channelName)

	err := channel.Publish(ctx, "match.created", event)
	if err != nil {
		return fmt.Errorf("publish match.created to %s: %w", channelName, err)
	}

	slog.Info("Published match.created event",
		"channel", channelName,
		"match_id", matchID,
	)
	return nil
}

// PublishTradeConfirmed publishes a trade confirmation event to the match channel.
func (p *RESTPublisher) PublishTradeConfirmed(ctx context.Context, matchID string, event TradeConfirmedEvent) error {
	channelName := fmt.Sprintf("match:%s", matchID)
	channel := p.client.Channels.Get(channelName)

	err := channel.Publish(ctx, "trade.confirmed", event)
	if err != nil {
		return fmt.Errorf("publish trade.confirmed to %s: %w", channelName, err)
	}

	slog.Info("Published trade.confirmed event",
		"channel", channelName,
		"match_id", matchID,
		"confirmed_by", event.ConfirmedBy,
		"both_confirmed", event.BothConfirmed,
	)
	return nil
}

// NoopPublisher silently succeeds (for dev/test when Ably is disabled).
type NoopPublisher struct{}

// PublishMatchCreated is a no-op.
func (n *NoopPublisher) PublishMatchCreated(_ context.Context, _ string, _ MatchCreatedEvent) error {
	return nil
}

// PublishTradeConfirmed is a no-op.
func (n *NoopPublisher) PublishTradeConfirmed(_ context.Context, _ string, _ TradeConfirmedEvent) error {
	return nil
}

// Compile-time interface checks.
var _ Publisher = (*RESTPublisher)(nil)
var _ Publisher = (*NoopPublisher)(nil)
