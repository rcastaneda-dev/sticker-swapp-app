package ws

import (
	"context"
	"log/slog"
	"sync"
	"time"

	"nhooyr.io/websocket"
)

// MessageHandler is called when the connection receives a message.
// Returning an error closes the connection.
type MessageHandler func(ctx context.Context, typ websocket.MessageType, data []byte) error

// closeReq carries the status code and reason for a close initiated
// via Conn.Close (eviction, shutdown, etc.).
type closeReq struct {
	status websocket.StatusCode
	reason string
}

// Conn manages a single WebSocket connection's lifecycle.
type Conn struct {
	ws      *websocket.Conn
	userID  string
	cfg     Config
	onMsg   MessageHandler // nil = discard reads
	onClose func()         // removal callback

	stopCh   chan closeReq // buffered(1), signals Run to shut down
	stopOnce sync.Once
	done     chan struct{} // closed when Run exits
}

func newConn(ws *websocket.Conn, userID string, cfg Config, onMsg MessageHandler, onClose func()) *Conn {
	ws.SetReadLimit(cfg.ReadLimit)
	return &Conn{
		ws:      ws,
		userID:  userID,
		cfg:     cfg,
		onMsg:   onMsg,
		onClose: onClose,
		stopCh:  make(chan closeReq, 1),
		done:    make(chan struct{}),
	}
}

// Run starts the connection lifecycle. Blocks until closed.
// The caller should invoke this in a goroutine.
func (c *Conn) Run(ctx context.Context) {
	// Default close status (used when readPump exits on its own).
	closeStatus := websocket.StatusNormalClosure
	closeReason := "connection closed"

	defer func() {
		// CloseRead handles incoming frames so ws.Close's handshake
		// can read the peer's close response without blocking.
		c.ws.CloseRead(context.Background())
		c.ws.Close(closeStatus, closeReason)

		if c.onClose != nil {
			c.onClose()
		}
		slog.Info("ws connection closed", "user_id", c.userID)
		close(c.done)
	}()

	connCtx, connCancel := context.WithCancel(ctx)
	defer connCancel()

	// Translate Close() signal → context cancellation.
	go func() {
		select {
		case req := <-c.stopCh:
			closeStatus = req.status
			closeReason = req.reason
			connCancel()
		case <-connCtx.Done():
		}
	}()

	go c.heartbeatLoop(connCtx, connCancel)

	c.readPump(connCtx)
}

// heartbeatLoop sends periodic pings. Cancels context on failure.
func (c *Conn) heartbeatLoop(ctx context.Context, cancel context.CancelFunc) {
	ticker := time.NewTicker(c.cfg.HeartbeatInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			pingCtx, pingCancel := context.WithTimeout(ctx, c.cfg.HeartbeatTimeout)
			err := c.ws.Ping(pingCtx)
			pingCancel()
			if err != nil {
				slog.Info("heartbeat failed, closing connection",
					"user_id", c.userID,
					"error", err,
				)
				cancel()
				return
			}
		}
	}
}

// readPump reads messages until context is canceled or an error occurs.
func (c *Conn) readPump(ctx context.Context) {
	for {
		typ, data, err := c.ws.Read(ctx)
		if err != nil {
			if ctx.Err() == nil {
				slog.Info("ws read error",
					"user_id", c.userID,
					"error", err,
				)
			}
			return
		}
		if c.onMsg != nil {
			if err := c.onMsg(ctx, typ, data); err != nil {
				slog.Warn("message handler error, closing connection",
					"user_id", c.userID,
					"error", err,
				)
				return
			}
		}
	}
}

// Close signals the connection to shut down with the given status.
// Non-blocking and safe to call multiple times. The actual close
// handshake happens in Run's deferred cleanup.
func (c *Conn) Close(status websocket.StatusCode, reason string) {
	c.stopOnce.Do(func() {
		c.stopCh <- closeReq{status, reason}
	})
}

// Done returns a channel that closes when the connection is fully torn down.
func (c *Conn) Done() <-chan struct{} {
	return c.done
}
