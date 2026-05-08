//go:build integration

package ably

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	ablySDK "github.com/ably/ably-go/ably"
)

// ablyLoadTestConfig controls the load test parameters.
type ablyLoadTestConfig struct {
	TotalConnections    int           // number of Ably Realtime clients to create
	ChannelsCount       int           // number of channels (connections distributed across channels)
	ConnectionBatchSize int           // connections to establish per batch
	ConnectionDelay     time.Duration // delay between connection batches
	MessageRate         int           // target messages per second across all channels
	TestDuration        time.Duration // how long to sustain messaging
	WarmupDuration      time.Duration // wait time after connections before messaging
	LatencyTargetP95    time.Duration // p95 delivery latency acceptance criterion

	// Acceptance thresholds
	MinThroughputRatio  float64 // minimum actual/target throughput ratio (e.g., 0.95 = 95%)
	MaxDropRate         float64 // maximum message drop rate (e.g., 0.005 = 0.5%)
	MaxConnectionDrops  int     // maximum allowed connection drops during test
}

func defaultAblyLoadTestConfig() ablyLoadTestConfig {
	return ablyLoadTestConfig{
		TotalConnections:    10_000,
		ChannelsCount:       500,
		ConnectionBatchSize: 100,
		ConnectionDelay:     50 * time.Millisecond,
		MessageRate:         1_000,
		TestDuration:        60 * time.Second,
		WarmupDuration:      10 * time.Second,
		LatencyTargetP95:    100 * time.Millisecond,
		MinThroughputRatio:  0.95,
		MaxDropRate:         0.005,
		MaxConnectionDrops:  10,
	}
}

// loadTestMessage is the payload published on each channel message.
type loadTestMessage struct {
	Ts  int64  `json:"ts"`  // publish timestamp (Unix nanoseconds)
	Seq int    `json:"seq"` // sequence number per publisher
	Src string `json:"src"` // publisher identifier
}

// loadTestClient wraps an Ably Realtime client with its assigned channel index.
type loadTestClient struct {
	client    *ablySDK.Realtime
	channelID int
	userID    string
	unsub     func() // subscription cancel function
}

// loadTestMetrics collects all measurements from the load test.
type loadTestMetrics struct {
	// Connection phase
	tokenTimes   []time.Duration // per-client token issuance duration
	connectTimes []time.Duration // per-client connection establishment duration
	connectFails int64

	// Message phase
	sent             int64
	received         int64
	latencies        []time.Duration // delivery latencies
	connectionDrops  int64

	mu sync.Mutex // protects latencies slice
}

// TestAblyWebSocketLoadTest validates 10K concurrent Ably WebSocket connections
// with sustained 1K msg/sec throughput through the Go service token auth flow.
//
// Prerequisites:
//   - ABLY_API_KEY environment variable set
//   - Ably account with sufficient connection limits (Pro plan or higher)
//
// Run: make test-ably-loadtest
func TestAblyWebSocketLoadTest(t *testing.T) {
	apiKey := loadAblyAPIKey(t)
	cfg := defaultAblyLoadTestConfig()

	// Allow overriding for smaller test runs
	if os.Getenv("ABLY_LOADTEST_CONNECTIONS") != "" {
		var n int
		fmt.Sscanf(os.Getenv("ABLY_LOADTEST_CONNECTIONS"), "%d", &n)
		if n > 0 {
			cfg.TotalConnections = n
			cfg.ChannelsCount = max(n/20, 1)
		}
	}

	t.Logf("=== Ably WebSocket Load Test ===")
	t.Logf("Connections: %d, Channels: %d, Msg rate: %d/sec, Duration: %s",
		cfg.TotalConnections, cfg.ChannelsCount, cfg.MessageRate, cfg.TestDuration)

	// Phase 1: Set up token auth server
	tokenServer := setupTokenServer(t, apiKey)
	defer tokenServer.Close()
	t.Logf("Token server ready at %s", tokenServer.URL)

	metrics := &loadTestMetrics{
		tokenTimes:   make([]time.Duration, 0, cfg.TotalConnections),
		connectTimes: make([]time.Duration, 0, cfg.TotalConnections),
		latencies:    make([]time.Duration, 0, cfg.MessageRate*int(cfg.TestDuration.Seconds())),
	}

	// Phase 2: Connect clients in batches
	ctx, cancel := context.WithTimeout(context.Background(),
		cfg.TestDuration+cfg.WarmupDuration+5*time.Minute) // generous timeout for connection phase
	defer cancel()

	clients := connectClients(t, ctx, cfg, tokenServer.URL, apiKey, metrics)
	defer closeClients(t, clients)

	connectedCount := len(clients)
	t.Logf("Connected %d / %d clients", connectedCount, cfg.TotalConnections)

	if connectedCount == 0 {
		t.Fatal("No clients connected — cannot proceed with message phase")
	}

	// Phase 3: Subscribe all clients to their channels
	subscribeCh := make(chan time.Duration, cfg.MessageRate*int(cfg.TestDuration.Seconds())*2)
	var receivedCount atomic.Int64

	subscribeClients(t, ctx, clients, subscribeCh, &receivedCount)

	// Phase 4: Warmup — let connections stabilize
	t.Logf("Warming up for %s...", cfg.WarmupDuration)
	time.Sleep(cfg.WarmupDuration)

	// Verify connections are still alive after warmup
	aliveCount := countAliveConnections(clients)
	t.Logf("Alive after warmup: %d / %d", aliveCount, connectedCount)

	// Phase 5: Sustained messaging
	t.Logf("Starting message phase: %d msg/sec for %s", cfg.MessageRate, cfg.TestDuration)
	var sentCount atomic.Int64
	publishMessages(t, ctx, cfg, clients, &sentCount)

	// Phase 6: Drain — wait for in-flight messages
	drainDuration := 5 * time.Second
	t.Logf("Draining for %s...", drainDuration)
	time.Sleep(drainDuration)

	// Phase 7: Collect metrics
	close(subscribeCh)
	for lat := range subscribeCh {
		metrics.latencies = append(metrics.latencies, lat)
	}
	metrics.sent = sentCount.Load()
	metrics.received = receivedCount.Load()

	// Count connection drops
	dropsAfterTest := int64(connectedCount) - int64(countAliveConnections(clients))
	metrics.connectionDrops = dropsAfterTest

	// Phase 8: Report and assert
	printAblyLoadTestReport(t, cfg, metrics, connectedCount)
	assertAblyLoadTestCriteria(t, cfg, metrics, connectedCount)
}

// loadAblyAPIKey reads the Ably API key from environment, skipping the test if absent.
func loadAblyAPIKey(t *testing.T) string {
	t.Helper()

	// Try loading from .env file if env var not set
	if os.Getenv("ABLY_API_KEY") == "" {
		loadEnvFile(t)
	}

	apiKey := os.Getenv("ABLY_API_KEY")
	if apiKey == "" {
		t.Skip("ABLY_API_KEY not set — skipping Ably load test")
	}
	return apiKey
}

// loadEnvFile attempts to read ../.env and set environment variables.
func loadEnvFile(t *testing.T) {
	t.Helper()
	data, err := os.ReadFile("../../.env")
	if err != nil {
		return // silently ignore if .env doesn't exist
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			key := strings.TrimSpace(parts[0])
			val := strings.TrimSpace(parts[1])
			// Remove quotes if present
			val = strings.Trim(val, `"'`)
			if os.Getenv(key) == "" {
				os.Setenv(key, val)
			}
		}
	}
}

// setupTokenServer creates an httptest.Server wrapping the TokenHandler.
// It injects a synthetic userID into the request context, bypassing JWT middleware.
func setupTokenServer(t *testing.T, apiKey string) *httptest.Server {
	t.Helper()

	checker := &mockParticipantChecker{isParticipant: true}
	handler := NewTokenHandler(Config{
		APIKey:         apiKey,
		SupabaseURL:    "https://test.supabase.co",
		SupabaseSecret: "test-secret",
	}, checker)

	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/v1/ably/auth", func(w http.ResponseWriter, r *http.Request) {
		// Extract userID from X-User-ID header (set by test clients)
		userID := r.Header.Get("X-User-ID")
		if userID == "" {
			userID = "loadtest-user-0"
		}
		ctx := context.WithValue(r.Context(), UserIDKey(), userID)
		handler.IssueToken(w, r.WithContext(ctx))
	})

	return httptest.NewServer(mux)
}

// connectClients establishes Ably Realtime connections in batches using token auth.
func connectClients(
	t *testing.T,
	ctx context.Context,
	cfg ablyLoadTestConfig,
	tokenServerURL string,
	apiKey string,
	metrics *loadTestMetrics,
) []*loadTestClient {
	t.Helper()

	clients := make([]*loadTestClient, 0, cfg.TotalConnections)
	var mu sync.Mutex
	var wg sync.WaitGroup
	sem := make(chan struct{}, cfg.ConnectionBatchSize)

	httpClient := &http.Client{Timeout: 30 * time.Second}

	for i := 0; i < cfg.TotalConnections; i++ {
		select {
		case <-ctx.Done():
			t.Logf("Context cancelled during connection phase at %d/%d", i, cfg.TotalConnections)
			return clients
		default:
		}

		sem <- struct{}{}
		wg.Add(1)

		go func(idx int) {
			defer wg.Done()
			defer func() { <-sem }()

			userID := fmt.Sprintf("loadtest-user-%d", idx)
			channelID := idx % cfg.ChannelsCount

			// Step 1: Request token from Go service
			tokenStart := time.Now()
			tokenReq, err := requestToken(httpClient, tokenServerURL, userID)
			tokenDuration := time.Since(tokenStart)
			if err != nil {
				atomic.AddInt64(&metrics.connectFails, 1)
				if idx < 5 || idx%1000 == 0 {
					t.Logf("Token request failed for client %d: %v", idx, err)
				}
				return
			}

			// Step 2: Connect to Ably using the token
			connectStart := time.Now()
			client, err := ablySDK.NewRealtime(
				ablySDK.WithAuthCallback(func(_ context.Context, _ ablySDK.TokenParams) (ablySDK.Tokener, error) {
					// Return the signed token request from our Go service
					return tokenReq, nil
				}),
				ablySDK.WithAutoConnect(true),
			)
			if err != nil {
				atomic.AddInt64(&metrics.connectFails, 1)
				if idx < 5 || idx%1000 == 0 {
					t.Logf("Ably connect failed for client %d: %v", idx, err)
				}
				return
			}

			// Wait for connected state (with timeout)
			connectCtx, connectCancel := context.WithTimeout(ctx, 30*time.Second)
			defer connectCancel()

			connected := waitForConnected(connectCtx, client)
			connectDuration := time.Since(connectStart)

			if !connected {
				atomic.AddInt64(&metrics.connectFails, 1)
				client.Close()
				if idx < 5 || idx%1000 == 0 {
					t.Logf("Client %d failed to reach connected state", idx)
				}
				return
			}

			ltc := &loadTestClient{
				client:    client,
				channelID: channelID,
				userID:    userID,
			}

			mu.Lock()
			clients = append(clients, ltc)
			metrics.tokenTimes = append(metrics.tokenTimes, tokenDuration)
			metrics.connectTimes = append(metrics.connectTimes, connectDuration)
			mu.Unlock()

			if (idx+1)%1000 == 0 {
				t.Logf("Connected %d / %d clients", idx+1, cfg.TotalConnections)
			}
		}(i)

		// Batch delay
		if (i+1)%cfg.ConnectionBatchSize == 0 {
			time.Sleep(cfg.ConnectionDelay)
		}
	}

	wg.Wait()
	return clients
}

// requestToken calls the Go service's token endpoint and returns an Ably TokenRequest.
func requestToken(httpClient *http.Client, tokenServerURL, userID string) (*ablySDK.TokenRequest, error) {
	req, err := http.NewRequest("POST", tokenServerURL+"/api/v1/ably/auth", bytes.NewReader([]byte("{}")))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-User-ID", userID)

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("HTTP request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("token endpoint returned %d: %s", resp.StatusCode, string(body))
	}

	var tokenResp struct {
		TokenRequest ablySDK.TokenRequest `json:"tokenRequest"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&tokenResp); err != nil {
		return nil, fmt.Errorf("decode token response: %w", err)
	}

	return &tokenResp.TokenRequest, nil
}

// waitForConnected blocks until the Ably client reaches ConnectionStateConnected or timeout.
func waitForConnected(ctx context.Context, client *ablySDK.Realtime) bool {
	if client.Connection.State() == ablySDK.ConnectionStateConnected {
		return true
	}

	ch := make(chan bool, 1)
	off := client.Connection.OnAll(func(change ablySDK.ConnectionStateChange) {
		if change.Current == ablySDK.ConnectionStateConnected {
			select {
			case ch <- true:
			default:
			}
		} else if change.Current == ablySDK.ConnectionStateFailed {
			select {
			case ch <- false:
			default:
			}
		}
	})
	defer off()

	// Check again after registering handler (race window)
	if client.Connection.State() == ablySDK.ConnectionStateConnected {
		return true
	}

	select {
	case result := <-ch:
		return result
	case <-ctx.Done():
		return false
	}
}

// subscribeClients subscribes each client to its assigned channel and records latencies.
func subscribeClients(
	t *testing.T,
	ctx context.Context,
	clients []*loadTestClient,
	latencyCh chan<- time.Duration,
	receivedCount *atomic.Int64,
) {
	t.Helper()

	for _, ltc := range clients {
		channelName := fmt.Sprintf("loadtest:match:%d", ltc.channelID)
		channel := ltc.client.Channels.Get(channelName)

		unsub, err := channel.Subscribe(ctx, "chat.message", func(msg *ablySDK.Message) {
			if msg.Data == nil {
				return
			}

			// Parse message payload to extract publish timestamp
			var payload loadTestMessage
			switch data := msg.Data.(type) {
			case string:
				if err := json.Unmarshal([]byte(data), &payload); err != nil {
					return
				}
			case map[string]interface{}:
				// Ably may decode JSON objects automatically
				if ts, ok := data["ts"].(float64); ok {
					payload.Ts = int64(ts)
				}
			default:
				return
			}

			if payload.Ts > 0 {
				latency := time.Duration(time.Now().UnixNano() - payload.Ts)
				if latency > 0 && latency < 30*time.Second { // sanity check
					select {
					case latencyCh <- latency:
					default:
						// channel full, count but don't block
					}
				}
			}
			receivedCount.Add(1)
		})
		if err != nil {
			t.Logf("Subscribe failed for client %s on channel %s: %v", ltc.userID, channelName, err)
			continue
		}
		ltc.unsub = unsub
	}
}

// publishMessages publishes messages at the target rate across channels for the test duration.
func publishMessages(
	t *testing.T,
	ctx context.Context,
	cfg ablyLoadTestConfig,
	clients []*loadTestClient,
	sentCount *atomic.Int64,
) {
	t.Helper()

	// Select one publisher per channel (the first client assigned to each channel)
	publishers := make(map[int]*loadTestClient) // channelID → client
	for _, ltc := range clients {
		if _, exists := publishers[ltc.channelID]; !exists {
			publishers[ltc.channelID] = ltc
		}
	}

	// Calculate per-channel rate
	// Total rate / number of channels = per-channel rate
	activeChannels := len(publishers)
	if activeChannels == 0 {
		t.Fatal("No publishers available")
	}

	// Use a ticker for overall rate control
	interval := time.Second / time.Duration(cfg.MessageRate)
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	deadline := time.After(cfg.TestDuration)
	channelIDs := make([]int, 0, activeChannels)
	for id := range publishers {
		channelIDs = append(channelIDs, id)
	}
	sort.Ints(channelIDs)

	msgIdx := 0
	for {
		select {
		case <-deadline:
			return
		case <-ctx.Done():
			return
		case <-ticker.C:
			// Round-robin across channels
			chID := channelIDs[msgIdx%activeChannels]
			pub := publishers[chID]
			channelName := fmt.Sprintf("loadtest:match:%d", chID)
			channel := pub.client.Channels.Get(channelName)

			payload := loadTestMessage{
				Ts:  time.Now().UnixNano(),
				Seq: msgIdx,
				Src: fmt.Sprintf("pub-%d", chID),
			}
			data, _ := json.Marshal(payload)

			// Use async publish to avoid blocking the ticker loop
			err := channel.PublishAsync("chat.message", string(data), func(err error) {
				if err != nil {
					// Log occasional failures
					count := sentCount.Load()
					if count < 5 || count%10000 == 0 {
						t.Logf("Publish error on channel %s (msg %d): %v", channelName, count, err)
					}
				}
			})
			if err != nil {
				// Enqueue error — connection likely dropped
				continue
			}
			sentCount.Add(1)
			msgIdx++

			if msgIdx%10000 == 0 {
				t.Logf("Published %d messages...", msgIdx)
			}
		}
	}
}

// countAliveConnections returns how many clients are in Connected state.
func countAliveConnections(clients []*loadTestClient) int {
	count := 0
	for _, ltc := range clients {
		if ltc.client.Connection.State() == ablySDK.ConnectionStateConnected {
			count++
		}
	}
	return count
}

// closeClients gracefully closes all Ably connections.
func closeClients(t *testing.T, clients []*loadTestClient) {
	t.Helper()
	t.Logf("Closing %d clients...", len(clients))

	var wg sync.WaitGroup
	sem := make(chan struct{}, 100) // close 100 at a time

	for _, ltc := range clients {
		wg.Add(1)
		sem <- struct{}{}
		go func(c *loadTestClient) {
			defer wg.Done()
			defer func() { <-sem }()
			if c.unsub != nil {
				c.unsub()
			}
			c.client.Close()
		}(ltc)
	}
	wg.Wait()
	t.Logf("All clients closed")
}

// printAblyLoadTestReport outputs a formatted summary of the load test results.
func printAblyLoadTestReport(
	t *testing.T,
	cfg ablyLoadTestConfig,
	metrics *loadTestMetrics,
	connectedCount int,
) {
	t.Helper()

	t.Logf("")
	t.Logf("╔══════════════════════════════════════════════╗")
	t.Logf("║     Ably WebSocket Load Test Report          ║")
	t.Logf("╠══════════════════════════════════════════════╣")

	// Token issuance
	if len(metrics.tokenTimes) > 0 {
		tokenDurations := sortedDurations(metrics.tokenTimes)
		totalTokenTime := sumDurations(tokenDurations)
		tokensPerSec := float64(len(tokenDurations)) / totalTokenTime.Seconds()
		t.Logf("║ Token issuance: %d tokens (%.0f tokens/sec)", len(tokenDurations), tokensPerSec)
		t.Logf("║   p50/p95/p99: %s / %s / %s",
			percentileDuration(tokenDurations, 50),
			percentileDuration(tokenDurations, 95),
			percentileDuration(tokenDurations, 99))
	}

	// Connections
	t.Logf("║ Connections: %d / %d (%.1f%%)",
		connectedCount, cfg.TotalConnections,
		float64(connectedCount)/float64(cfg.TotalConnections)*100)
	if len(metrics.connectTimes) > 0 {
		connectDurations := sortedDurations(metrics.connectTimes)
		t.Logf("║   Connect time p50/p95/p99: %s / %s / %s",
			percentileDuration(connectDurations, 50),
			percentileDuration(connectDurations, 95),
			percentileDuration(connectDurations, 99))
	}

	// Messages
	t.Logf("║ Channels: %d", cfg.ChannelsCount)
	t.Logf("║ Duration: %s", cfg.TestDuration)
	t.Logf("║ Messages sent: %d", metrics.sent)

	deliveryRate := float64(0)
	if metrics.sent > 0 {
		// Each message is received by all subscribers on that channel
		// So expected received = sent * (subscribers per channel)
		deliveryRate = float64(metrics.received) / float64(metrics.sent) / float64(connectedCount/cfg.ChannelsCount) * 100
	}
	t.Logf("║ Messages received: %d", metrics.received)
	throughput := float64(metrics.sent) / cfg.TestDuration.Seconds()
	t.Logf("║ Throughput: %.0f msg/sec (target: %d)", throughput, cfg.MessageRate)

	// Latency
	if len(metrics.latencies) > 0 {
		latencies := sortedDurations(metrics.latencies)
		t.Logf("║ Delivery latency:")
		t.Logf("║   p50: %s", percentileDuration(latencies, 50))
		t.Logf("║   p95: %s", percentileDuration(latencies, 95))
		t.Logf("║   p99: %s", percentileDuration(latencies, 99))
		t.Logf("║   max: %s", latencies[len(latencies)-1])
	} else {
		t.Logf("║ Delivery latency: NO SAMPLES")
	}

	// Connection drops
	t.Logf("║ Connection drops: %d", metrics.connectionDrops)
	_ = deliveryRate

	t.Logf("╚══════════════════════════════════════════════╝")
}

// assertAblyLoadTestCriteria checks all acceptance criteria and fails the test if any are breached.
func assertAblyLoadTestCriteria(
	t *testing.T,
	cfg ablyLoadTestConfig,
	metrics *loadTestMetrics,
	connectedCount int,
) {
	t.Helper()

	passed := true

	// 1. All connections established
	if connectedCount < cfg.TotalConnections {
		failRate := 1.0 - float64(connectedCount)/float64(cfg.TotalConnections)
		if failRate > 0.001 { // allow 0.1% connection failures
			t.Errorf("FAIL: Only %d / %d connections established (%.2f%% failure rate)",
				connectedCount, cfg.TotalConnections, failRate*100)
			passed = false
		}
	}

	// 2. Sustained throughput
	actualThroughput := float64(metrics.sent) / cfg.TestDuration.Seconds()
	throughputRatio := actualThroughput / float64(cfg.MessageRate)
	if throughputRatio < cfg.MinThroughputRatio {
		t.Errorf("FAIL: Throughput %.0f msg/sec is below %.0f%% of target %d msg/sec",
			actualThroughput, cfg.MinThroughputRatio*100, cfg.MessageRate)
		passed = false
	}

	// 3. Delivery latency p95
	if len(metrics.latencies) > 0 {
		latencies := sortedDurations(metrics.latencies)
		p95 := percentileDuration(latencies, 95)
		if p95 > cfg.LatencyTargetP95 {
			t.Errorf("FAIL: Delivery latency p95 %s exceeds target %s", p95, cfg.LatencyTargetP95)
			passed = false
		}
	} else {
		t.Errorf("FAIL: No latency samples collected")
		passed = false
	}

	// 4. Connection drops
	if metrics.connectionDrops > int64(cfg.MaxConnectionDrops) {
		t.Errorf("FAIL: %d connection drops exceeds maximum %d",
			metrics.connectionDrops, cfg.MaxConnectionDrops)
		passed = false
	}

	// 5. Message delivery rate
	if metrics.sent > 0 {
		// Calculate expected total received messages
		// Each sent message goes to all subscribers on the channel
		subsPerChannel := connectedCount / cfg.ChannelsCount
		if subsPerChannel < 1 {
			subsPerChannel = 1
		}
		expectedReceived := metrics.sent * int64(subsPerChannel)
		if expectedReceived > 0 {
			dropRate := 1.0 - float64(metrics.received)/float64(expectedReceived)
			if dropRate > cfg.MaxDropRate {
				t.Errorf("FAIL: Message drop rate %.2f%% exceeds maximum %.2f%%",
					dropRate*100, cfg.MaxDropRate*100)
				passed = false
			}
		}
	}

	if passed {
		t.Logf("RESULT: PASS — all acceptance criteria met")
	} else {
		t.Logf("RESULT: FAIL — one or more criteria breached")
	}
}

// --- Statistics helpers ---

// sortedDurations returns a sorted copy of the duration slice.
func sortedDurations(durations []time.Duration) []time.Duration {
	sorted := make([]time.Duration, len(durations))
	copy(sorted, durations)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i] < sorted[j] })
	return sorted
}

// percentileDuration returns the p-th percentile from a sorted duration slice.
func percentileDuration(sorted []time.Duration, p float64) time.Duration {
	if len(sorted) == 0 {
		return 0
	}
	idx := int(math.Ceil(p/100*float64(len(sorted)))) - 1
	if idx < 0 {
		idx = 0
	}
	if idx >= len(sorted) {
		idx = len(sorted) - 1
	}
	return sorted[idx]
}

// sumDurations returns the sum of all durations.
func sumDurations(durations []time.Duration) time.Duration {
	var total time.Duration
	for _, d := range durations {
		total += d
	}
	if total == 0 {
		total = time.Millisecond // avoid division by zero
	}
	return total
}
