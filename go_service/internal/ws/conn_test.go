package ws

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"nhooyr.io/websocket"
)

// testConfig returns a fast config for tests.
func testConfig() Config {
	return Config{
		HeartbeatInterval:   100 * time.Millisecond,
		HeartbeatTimeout:    50 * time.Millisecond,
		ReadLimit:           4096,
		WriteTimeout:        time.Second,
		ShutdownGracePeriod: time.Second,
	}
}

// testServer creates an httptest.Server that accepts one WebSocket
// connection and returns it via the channel.
func testServer(t *testing.T) (serverConn chan *websocket.Conn, srv *httptest.Server) {
	t.Helper()
	ch := make(chan *websocket.Conn, 1)
	srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ws, err := websocket.Accept(w, r, nil)
		if err != nil {
			t.Logf("server accept error: %v", err)
			return
		}
		ch <- ws
	}))
	return ch, srv
}

// dial connects to the test server and returns a client-side websocket.Conn.
func dial(t *testing.T, ctx context.Context, url string) *websocket.Conn {
	t.Helper()
	c, _, err := websocket.Dial(ctx, url, nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	return c
}

func TestConn_ReadPump_ReceivesMessage(t *testing.T) {
	serverCh, srv := testServer(t)
	defer srv.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client := dial(t, ctx, srv.URL)
	defer client.Close(websocket.StatusNormalClosure, "")

	serverWS := <-serverCh

	var received atomic.Value
	done := make(chan struct{})
	onMsg := func(_ context.Context, typ websocket.MessageType, data []byte) error {
		received.Store(string(data))
		close(done)
		return nil
	}

	conn := newConn(serverWS, "user-1", testConfig(), onMsg, nil)
	go conn.Run(ctx)

	err := client.Write(ctx, websocket.MessageText, []byte("hello"))
	if err != nil {
		t.Fatalf("client write: %v", err)
	}

	select {
	case <-done:
		if got := received.Load().(string); got != "hello" {
			t.Fatalf("expected 'hello', got %q", got)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timeout waiting for message")
	}
}

func TestConn_ReadPump_ContextCancel(t *testing.T) {
	serverCh, srv := testServer(t)
	defer srv.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client := dial(t, ctx, srv.URL)
	defer client.Close(websocket.StatusNormalClosure, "")

	serverWS := <-serverCh

	var closeCalled atomic.Int32
	onClose := func() {
		closeCalled.Add(1)
	}

	conn := newConn(serverWS, "user-1", testConfig(), nil, onClose)

	connCtx, connCancel := context.WithCancel(ctx)
	go conn.Run(connCtx)

	// Cancel the connection context
	connCancel()

	select {
	case <-conn.Done():
		if closeCalled.Load() != 1 {
			t.Fatalf("expected onClose called once, got %d", closeCalled.Load())
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timeout waiting for conn.Done()")
	}
}

func TestConn_CloseFromClient(t *testing.T) {
	serverCh, srv := testServer(t)
	defer srv.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client := dial(t, ctx, srv.URL)
	serverWS := <-serverCh

	var closeCalled atomic.Int32
	conn := newConn(serverWS, "user-1", testConfig(), nil, func() {
		closeCalled.Add(1)
	})
	go conn.Run(ctx)

	// Client initiates close
	client.Close(websocket.StatusNormalClosure, "bye")

	select {
	case <-conn.Done():
		if closeCalled.Load() != 1 {
			t.Fatalf("expected onClose called once, got %d", closeCalled.Load())
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timeout waiting for conn.Done()")
	}
}

func TestConn_NilMessageHandler(t *testing.T) {
	serverCh, srv := testServer(t)
	defer srv.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client := dial(t, ctx, srv.URL)
	defer client.Close(websocket.StatusNormalClosure, "")

	serverWS := <-serverCh

	// nil onMsg — messages should be discarded, connection stays alive
	conn := newConn(serverWS, "user-1", testConfig(), nil, nil)
	go conn.Run(ctx)

	// Send a message — should not crash
	err := client.Write(ctx, websocket.MessageText, []byte("ignored"))
	if err != nil {
		t.Fatalf("client write: %v", err)
	}

	// Connection should still be alive after a short delay
	time.Sleep(50 * time.Millisecond)
	select {
	case <-conn.Done():
		t.Fatal("connection should not be closed after discarded message")
	default:
		// Expected
	}
}

func TestConn_MessageHandlerError(t *testing.T) {
	serverCh, srv := testServer(t)
	defer srv.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client := dial(t, ctx, srv.URL)
	defer client.Close(websocket.StatusNormalClosure, "")

	serverWS := <-serverCh

	onMsg := func(_ context.Context, _ websocket.MessageType, _ []byte) error {
		return context.DeadlineExceeded // arbitrary error
	}

	conn := newConn(serverWS, "user-1", testConfig(), onMsg, nil)
	go conn.Run(ctx)

	err := client.Write(ctx, websocket.MessageText, []byte("trigger error"))
	if err != nil {
		t.Fatalf("client write: %v", err)
	}

	// Client must be reading for the close handshake to complete
	// (nhooyr.io/websocket handles control frames inside Read).
	client.CloseRead(ctx)

	select {
	case <-conn.Done():
		// Connection closed due to handler error
	case <-time.After(2 * time.Second):
		t.Fatal("timeout waiting for conn.Done()")
	}
}

func TestConn_DoubleClose(t *testing.T) {
	serverCh, srv := testServer(t)
	defer srv.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client := dial(t, ctx, srv.URL)
	defer client.Close(websocket.StatusNormalClosure, "")

	serverWS := <-serverCh

	conn := newConn(serverWS, "user-1", testConfig(), nil, nil)
	go conn.Run(ctx)

	// Should not panic
	conn.Close(websocket.StatusNormalClosure, "first")
	conn.Close(websocket.StatusNormalClosure, "second")

	select {
	case <-conn.Done():
		// Expected
	case <-time.After(2 * time.Second):
		t.Fatal("timeout waiting for conn.Done()")
	}
}

func TestConn_ReadLimitEnforced(t *testing.T) {
	serverCh, srv := testServer(t)
	defer srv.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client := dial(t, ctx, srv.URL)
	defer client.Close(websocket.StatusNormalClosure, "")

	serverWS := <-serverCh

	cfg := testConfig()
	cfg.ReadLimit = 10 // Very small limit

	conn := newConn(serverWS, "user-1", cfg, nil, nil)
	go conn.Run(ctx)

	// Send a message exceeding the read limit
	bigMsg := []byte(strings.Repeat("x", 100))
	_ = client.Write(ctx, websocket.MessageText, bigMsg)

	select {
	case <-conn.Done():
		// Connection closed due to message too big
	case <-time.After(2 * time.Second):
		t.Fatal("timeout waiting for conn.Done()")
	}
}
