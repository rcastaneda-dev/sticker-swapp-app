package matchmaking

import (
	"testing"
	"time"
)

func TestCache_GetMiss(t *testing.T) {
	c := NewTestCache()
	_, ok := c.Get("nonexistent")
	if ok {
		t.Fatal("expected cache miss")
	}
}

func TestCache_SetAndGet(t *testing.T) {
	c := NewTestCache()
	results := []ScoredMatch{{UserID: "user-1", TotalScore: 0.9}}
	c.Set("user-a", results)

	got, ok := c.Get("user-a")
	if !ok {
		t.Fatal("expected cache hit")
	}
	if len(got) != 1 || got[0].UserID != "user-1" {
		t.Fatalf("unexpected cached result: %+v", got)
	}
}

func TestCache_Expiry(t *testing.T) {
	now := time.Date(2026, 3, 25, 12, 0, 0, 0, time.UTC)
	c := NewTestCache()
	c.nowFunc = func() time.Time { return now }

	c.Set("user-b", []ScoredMatch{{UserID: "match-1"}})

	// Advance time past TTL
	now = now.Add(61 * time.Second)

	_, ok := c.Get("user-b")
	if ok {
		t.Fatal("expected cache miss after expiry")
	}
}

func TestCache_EvictExpired(t *testing.T) {
	now := time.Date(2026, 3, 25, 12, 0, 0, 0, time.UTC)
	c := NewTestCache()
	c.nowFunc = func() time.Time { return now }

	c.Set("user-fresh", []ScoredMatch{})
	c.Set("user-stale", []ScoredMatch{})

	// Advance past TTL
	now = now.Add(61 * time.Second)

	// Add a new fresh entry
	c.Set("user-new", []ScoredMatch{})

	c.evictExpired()

	if c.Len() != 1 {
		t.Fatalf("expected 1 entry after eviction, got %d", c.Len())
	}
	if _, ok := c.Get("user-new"); !ok {
		t.Fatal("expected user-new to survive eviction")
	}
}

func TestCache_PerUserIsolation(t *testing.T) {
	c := NewTestCache()
	c.Set("user-x", []ScoredMatch{{UserID: "match-x"}})
	c.Set("user-y", []ScoredMatch{{UserID: "match-y"}})

	gotX, okX := c.Get("user-x")
	gotY, okY := c.Get("user-y")

	if !okX || !okY {
		t.Fatal("expected both cache hits")
	}
	if gotX[0].UserID != "match-x" || gotY[0].UserID != "match-y" {
		t.Fatal("cache entries are not isolated per user")
	}
}

func TestCache_EmptyResults(t *testing.T) {
	c := NewTestCache()
	c.Set("user-empty", []ScoredMatch{})

	got, ok := c.Get("user-empty")
	if !ok {
		t.Fatal("expected cache hit for empty results")
	}
	if len(got) != 0 {
		t.Fatalf("expected empty slice, got %d entries", len(got))
	}
}
