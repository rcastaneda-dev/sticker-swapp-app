package ws

import (
	"context"
	"log/slog"
	"sync"

	"nhooyr.io/websocket"
)

// Manager is a thread-safe registry of active WebSocket connections,
// keyed by user ID. Enforces one connection per user.
type Manager struct {
	cfg   Config
	mu    sync.RWMutex
	conns map[string]*Conn

	shutdownCh chan struct{}
	shutOnce   sync.Once
}

// NewManager creates a Manager with the given configuration.
func NewManager(cfg Config) *Manager {
	return &Manager{
		cfg:        cfg,
		conns:      make(map[string]*Conn),
		shutdownCh: make(chan struct{}),
	}
}

// Add registers a new connection for the given user. If the user already
// has an active connection, the old one is evicted with StatusPolicyViolation.
// Returns false if the manager is shutting down.
func (m *Manager) Add(ctx context.Context, userID string, ws *websocket.Conn, onMsg MessageHandler) bool {
	select {
	case <-m.shutdownCh:
		ws.Close(websocket.StatusGoingAway, "server shutting down")
		return false
	default:
	}

	m.mu.Lock()

	if existing, ok := m.conns[userID]; ok {
		slog.Info("evicting existing ws connection", "user_id", userID)
		existing.Close(websocket.StatusPolicyViolation, "replaced by new connection")
	}

	var conn *Conn
	conn = newConn(ws, userID, m.cfg, onMsg, func() {
		m.remove(userID, conn)
	})
	m.conns[userID] = conn
	m.mu.Unlock()

	slog.Info("ws connection added",
		"user_id", userID,
		"active_connections", m.Len(),
	)

	go conn.Run(ctx)

	return true
}

// remove deletes a connection from the registry only if the pointer matches.
// This prevents a stale cleanup callback from removing a newer connection.
func (m *Manager) remove(userID string, conn *Conn) {
	m.mu.Lock()
	defer m.mu.Unlock()

	if current, ok := m.conns[userID]; ok && current == conn {
		delete(m.conns, userID)
		slog.Info("ws connection removed",
			"user_id", userID,
			"active_connections", len(m.conns),
		)
	}
}

// Get returns the active connection for a user, or nil.
func (m *Manager) Get(userID string) *Conn {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.conns[userID]
}

// Len returns the number of active connections.
func (m *Manager) Len() int {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return len(m.conns)
}

// Shutdown gracefully closes all connections. Safe to call multiple times.
// After Shutdown, Add() rejects new connections.
func (m *Manager) Shutdown(ctx context.Context) {
	m.shutOnce.Do(func() {
		close(m.shutdownCh)
	})

	m.mu.RLock()
	snapshot := make([]*Conn, 0, len(m.conns))
	for _, c := range m.conns {
		snapshot = append(snapshot, c)
	}
	m.mu.RUnlock()

	slog.Info("ws manager shutting down", "active_connections", len(snapshot))

	for _, c := range snapshot {
		c.Close(websocket.StatusGoingAway, "server shutting down")
	}

	for _, c := range snapshot {
		select {
		case <-c.Done():
		case <-ctx.Done():
			slog.Warn("ws shutdown timed out, abandoning remaining connections")
			return
		}
	}

	slog.Info("ws manager shutdown complete")
}
