package ws

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"nhooyr.io/websocket"
)

// dialPair creates a connected server/client WebSocket pair via httptest.
func dialPair(t *testing.T, ctx context.Context) (serverWS *websocket.Conn, clientWS *websocket.Conn, cleanup func()) {
	t.Helper()

	serverCh := make(chan *websocket.Conn, 1)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ws, err := websocket.Accept(w, r, nil)
		if err != nil {
			return
		}
		serverCh <- ws
	}))

	client, _, err := websocket.Dial(ctx, srv.URL, nil)
	if err != nil {
		srv.Close()
		t.Fatalf("dial: %v", err)
	}

	server := <-serverCh

	// Start background reader so the client responds to pings and
	// close frames (nhooyr.io/websocket handles control frames in Read).
	client.CloseRead(ctx)

	return server, client, func() {
		client.Close(websocket.StatusNormalClosure, "")
		srv.Close()
	}
}

func TestManager_Add_And_Get(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	m := NewManager(testConfig())

	serverWS, _, cleanup := dialPair(t, ctx)
	defer cleanup()

	if !m.Add(ctx, "user-1", serverWS, nil) {
		t.Fatal("Add should return true")
	}

	if m.Get("user-1") == nil {
		t.Fatal("Get should return the connection")
	}
	if m.Get("user-2") != nil {
		t.Fatal("Get for unknown user should return nil")
	}
	if m.Len() != 1 {
		t.Fatalf("expected 1 connection, got %d", m.Len())
	}
}

func TestManager_Add_EvictsExisting(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	m := NewManager(testConfig())

	ws1, _, cleanup1 := dialPair(t, ctx)
	defer cleanup1()
	ws2, _, cleanup2 := dialPair(t, ctx)
	defer cleanup2()

	m.Add(ctx, "user-1", ws1, nil)
	first := m.Get("user-1")

	m.Add(ctx, "user-1", ws2, nil)
	second := m.Get("user-1")

	if first == second {
		t.Fatal("second Add should create a new Conn")
	}

	// Wait for the evicted connection to close
	select {
	case <-first.Done():
		// Expected — evicted
	case <-time.After(2 * time.Second):
		t.Fatal("timeout waiting for evicted connection to close")
	}

	if m.Len() != 1 {
		t.Fatalf("expected 1 connection after eviction, got %d", m.Len())
	}
}

func TestManager_Remove_PointerSafety(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	m := NewManager(testConfig())

	ws1, client1, cleanup1 := dialPair(t, ctx)
	defer cleanup1()
	ws2, _, cleanup2 := dialPair(t, ctx)
	defer cleanup2()

	// Add first connection
	m.Add(ctx, "user-1", ws1, nil)
	first := m.Get("user-1")

	// Replace with second connection
	m.Add(ctx, "user-1", ws2, nil)

	// Force close the first client to trigger its onClose callback
	client1.Close(websocket.StatusNormalClosure, "bye")

	// Wait for first connection to finish
	select {
	case <-first.Done():
	case <-time.After(2 * time.Second):
		t.Fatal("timeout waiting for first connection to close")
	}

	// The second connection should still be registered
	if m.Get("user-1") == nil {
		t.Fatal("second connection should not be removed by first's cleanup")
	}
	if m.Len() != 1 {
		t.Fatalf("expected 1 connection, got %d", m.Len())
	}
}

func TestManager_Shutdown_ClosesAll(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	m := NewManager(testConfig())

	ws1, _, cleanup1 := dialPair(t, ctx)
	defer cleanup1()
	ws2, _, cleanup2 := dialPair(t, ctx)
	defer cleanup2()

	m.Add(ctx, "user-1", ws1, nil)
	m.Add(ctx, "user-2", ws2, nil)

	conn1 := m.Get("user-1")
	conn2 := m.Get("user-2")

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer shutdownCancel()
	m.Shutdown(shutdownCtx)

	select {
	case <-conn1.Done():
	case <-time.After(2 * time.Second):
		t.Fatal("timeout waiting for conn1 to close")
	}
	select {
	case <-conn2.Done():
	case <-time.After(2 * time.Second):
		t.Fatal("timeout waiting for conn2 to close")
	}
}

func TestManager_Shutdown_RejectsNew(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	m := NewManager(testConfig())

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), time.Second)
	defer shutdownCancel()
	m.Shutdown(shutdownCtx)

	ws, _, cleanup := dialPair(t, ctx)
	defer cleanup()

	if m.Add(ctx, "user-1", ws, nil) {
		t.Fatal("Add should return false after Shutdown")
	}
	if m.Len() != 0 {
		t.Fatalf("expected 0 connections, got %d", m.Len())
	}
}

func TestManager_Len(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	m := NewManager(testConfig())

	if m.Len() != 0 {
		t.Fatalf("expected 0, got %d", m.Len())
	}

	ws1, _, cleanup1 := dialPair(t, ctx)
	defer cleanup1()
	ws2, _, cleanup2 := dialPair(t, ctx)
	defer cleanup2()

	m.Add(ctx, "user-1", ws1, nil)
	if m.Len() != 1 {
		t.Fatalf("expected 1, got %d", m.Len())
	}

	m.Add(ctx, "user-2", ws2, nil)
	if m.Len() != 2 {
		t.Fatalf("expected 2, got %d", m.Len())
	}
}

func TestManager_ConcurrentAccess(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	m := NewManager(testConfig())

	// Collect cleanups to run after assertion (client close triggers
	// server-side removal, so we must not close before checking Len).
	var cleanups []func()
	var mu sync.Mutex

	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			ws, _, cleanup := dialPair(t, ctx)
			mu.Lock()
			cleanups = append(cleanups, cleanup)
			mu.Unlock()
			m.Add(ctx, "shared-user", ws, nil)
			m.Get("shared-user")
			m.Len()
		}()
	}
	wg.Wait()

	// Give evicted connections time to settle
	time.Sleep(200 * time.Millisecond)

	// Last writer wins — exactly 1 connection should survive
	if got := m.Len(); got != 1 {
		t.Fatalf("expected 1 connection, got %d", got)
	}

	for _, fn := range cleanups {
		fn()
	}
}
