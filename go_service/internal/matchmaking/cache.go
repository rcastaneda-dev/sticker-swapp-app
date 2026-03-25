package matchmaking

import (
	"sync"
	"time"
)

// cacheEntry holds scored results with an expiry timestamp.
type cacheEntry struct {
	results []ScoredMatch
	expiry  time.Time
}

// Cache is a thread-safe, TTL-based in-memory cache for scored matches.
type Cache struct {
	mu      sync.RWMutex
	entries map[string]cacheEntry
	ttl     time.Duration
	nowFunc func() time.Time // injectable for testing
	stopCh  chan struct{}
}

// CacheConfig holds configuration for the cache.
type CacheConfig struct {
	TTL             time.Duration
	CleanupInterval time.Duration
}

// DefaultCacheConfig returns 60s TTL, 30s cleanup interval.
func DefaultCacheConfig() CacheConfig {
	return CacheConfig{
		TTL:             60 * time.Second,
		CleanupInterval: 30 * time.Second,
	}
}

// NewCache creates a cache with background cleanup.
// Call Stop() to stop the cleanup goroutine.
func NewCache(cfg CacheConfig) *Cache {
	c := &Cache{
		entries: make(map[string]cacheEntry),
		ttl:     cfg.TTL,
		nowFunc: time.Now,
		stopCh:  make(chan struct{}),
	}

	go func() {
		ticker := time.NewTicker(cfg.CleanupInterval)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				c.evictExpired()
			case <-c.stopCh:
				return
			}
		}
	}()

	return c
}

// NewTestCache creates a cache without the background goroutine.
func NewTestCache() *Cache {
	return &Cache{
		entries: make(map[string]cacheEntry),
		ttl:     60 * time.Second,
		nowFunc: time.Now,
	}
}

// Stop halts the background cleanup goroutine.
func (c *Cache) Stop() {
	if c.stopCh != nil {
		close(c.stopCh)
	}
}

// Get returns cached results if present and not expired.
func (c *Cache) Get(userID string) ([]ScoredMatch, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()

	entry, ok := c.entries[userID]
	if !ok {
		return nil, false
	}
	if c.nowFunc().After(entry.expiry) {
		return nil, false
	}
	return entry.results, true
}

// Set stores results with a TTL-based expiry.
func (c *Cache) Set(userID string, results []ScoredMatch) {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.entries[userID] = cacheEntry{
		results: results,
		expiry:  c.nowFunc().Add(c.ttl),
	}
}

// evictExpired removes all expired entries.
func (c *Cache) evictExpired() {
	c.mu.Lock()
	defer c.mu.Unlock()

	now := c.nowFunc()
	for key, entry := range c.entries {
		if now.After(entry.expiry) {
			delete(c.entries, key)
		}
	}
}

// Len returns the number of entries.
func (c *Cache) Len() int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return len(c.entries)
}
