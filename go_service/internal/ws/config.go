package ws

import "time"

// Config holds tunable parameters for the WebSocket connection manager.
type Config struct {
	// HeartbeatInterval is how often the server pings each client.
	HeartbeatInterval time.Duration

	// HeartbeatTimeout is the maximum time to wait for a pong after a ping.
	HeartbeatTimeout time.Duration

	// ReadLimit is the maximum incoming message size in bytes.
	ReadLimit int64

	// WriteTimeout is the maximum time for a single write operation.
	WriteTimeout time.Duration

	// ShutdownGracePeriod is how long the manager waits for connections
	// to close during shutdown before abandoning them.
	ShutdownGracePeriod time.Duration
}

// DefaultConfig returns production defaults.
func DefaultConfig() Config {
	return Config{
		HeartbeatInterval:   30 * time.Second,
		HeartbeatTimeout:    10 * time.Second,
		ReadLimit:           4096,
		WriteTimeout:        5 * time.Second,
		ShutdownGracePeriod: 5 * time.Second,
	}
}
