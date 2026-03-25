package matchmaking

import (
	"math"
	"testing"
	"time"
)

// --- NormalizeProximity ---

func TestNormalizeProximity_AtOrigin(t *testing.T) {
	got := NormalizeProximity(0, 5000)
	if got != 1.0 {
		t.Fatalf("expected 1.0, got %f", got)
	}
}

func TestNormalizeProximity_AtRadius(t *testing.T) {
	got := NormalizeProximity(5000, 5000)
	if got != 0.0 {
		t.Fatalf("expected 0.0, got %f", got)
	}
}

func TestNormalizeProximity_BeyondRadius(t *testing.T) {
	got := NormalizeProximity(7000, 5000)
	if got != 0.0 {
		t.Fatalf("expected 0.0 (clamped), got %f", got)
	}
}

func TestNormalizeProximity_Midpoint(t *testing.T) {
	got := NormalizeProximity(2500, 5000)
	if got != 0.5 {
		t.Fatalf("expected 0.5, got %f", got)
	}
}

func TestNormalizeProximity_ZeroRadius(t *testing.T) {
	got := NormalizeProximity(100, 0)
	if got != 0.0 {
		t.Fatalf("expected 0.0 for zero radius, got %f", got)
	}
}

// --- NormalizeReciprocal ---

func TestNormalizeReciprocal_Zero(t *testing.T) {
	got := NormalizeReciprocal(0, 20)
	if got != 0.0 {
		t.Fatalf("expected 0.0, got %f", got)
	}
}

func TestNormalizeReciprocal_AtCap(t *testing.T) {
	got := NormalizeReciprocal(20, 20)
	if got != 1.0 {
		t.Fatalf("expected 1.0, got %f", got)
	}
}

func TestNormalizeReciprocal_AboveCap(t *testing.T) {
	got := NormalizeReciprocal(50, 20)
	if got != 1.0 {
		t.Fatalf("expected 1.0 (clamped), got %f", got)
	}
}

func TestNormalizeReciprocal_Midpoint(t *testing.T) {
	got := NormalizeReciprocal(10, 20)
	if got != 0.5 {
		t.Fatalf("expected 0.5, got %f", got)
	}
}

func TestNormalizeReciprocal_ZeroCap(t *testing.T) {
	got := NormalizeReciprocal(10, 0)
	if got != 0.0 {
		t.Fatalf("expected 0.0 for zero cap, got %f", got)
	}
}

// --- NormalizeActivity ---

func TestNormalizeActivity_JustNow(t *testing.T) {
	now := time.Now()
	got := NormalizeActivity(now, now, 24)
	if math.Abs(got-1.0) > 0.001 {
		t.Fatalf("expected ~1.0, got %f", got)
	}
}

func TestNormalizeActivity_OneHalfLife(t *testing.T) {
	now := time.Now()
	updatedAt := now.Add(-24 * time.Hour)
	got := NormalizeActivity(updatedAt, now, 24)
	if math.Abs(got-0.5) > 0.001 {
		t.Fatalf("expected ~0.5, got %f", got)
	}
}

func TestNormalizeActivity_TwoHalfLives(t *testing.T) {
	now := time.Now()
	updatedAt := now.Add(-48 * time.Hour)
	got := NormalizeActivity(updatedAt, now, 24)
	if math.Abs(got-0.25) > 0.001 {
		t.Fatalf("expected ~0.25, got %f", got)
	}
}

func TestNormalizeActivity_FutureTimestamp(t *testing.T) {
	now := time.Now()
	future := now.Add(1 * time.Hour)
	got := NormalizeActivity(future, now, 24)
	if math.Abs(got-1.0) > 0.001 {
		t.Fatalf("expected ~1.0 for future timestamp, got %f", got)
	}
}

func TestNormalizeActivity_ZeroHalfLife(t *testing.T) {
	now := time.Now()
	got := NormalizeActivity(now, now, 0)
	if got != 0.0 {
		t.Fatalf("expected 0.0 for zero half-life, got %f", got)
	}
}

// --- ComputeScore ---

func TestComputeScore_AllMax(t *testing.T) {
	w := DefaultWeights()
	got := ComputeScore(1.0, 1.0, 1.0, w)
	if math.Abs(got-1.0) > 0.001 {
		t.Fatalf("expected 1.0, got %f", got)
	}
}

func TestComputeScore_AllZero(t *testing.T) {
	w := DefaultWeights()
	got := ComputeScore(0, 0, 0, w)
	if got != 0.0 {
		t.Fatalf("expected 0.0, got %f", got)
	}
}

func TestComputeScore_ProximityOnly(t *testing.T) {
	w := DefaultWeights()
	got := ComputeScore(1.0, 0, 0, w)
	if math.Abs(got-0.5) > 0.001 {
		t.Fatalf("expected 0.5 (proximity weight), got %f", got)
	}
}

func TestComputeScore_ReciprocalOnly(t *testing.T) {
	w := DefaultWeights()
	got := ComputeScore(0, 1.0, 0, w)
	if math.Abs(got-0.3) > 0.001 {
		t.Fatalf("expected 0.3 (reciprocal weight), got %f", got)
	}
}

func TestComputeScore_ActivityOnly(t *testing.T) {
	w := DefaultWeights()
	got := ComputeScore(0, 0, 1.0, w)
	if math.Abs(got-0.2) > 0.001 {
		t.Fatalf("expected 0.2 (activity weight), got %f", got)
	}
}

func TestComputeScore_RealisticScenario(t *testing.T) {
	w := DefaultWeights()
	prox := NormalizeProximity(1000, 5000)   // 0.8
	recip := NormalizeReciprocal(10, 20)     // 0.5
	now := time.Now()
	act := NormalizeActivity(now.Add(-12*time.Hour), now, 24) // ~0.707

	got := ComputeScore(prox, recip, act, w)
	expected := prox*w.Proximity + recip*w.Reciprocal + act*w.Activity
	if math.Abs(got-expected) > 0.001 {
		t.Fatalf("expected %f, got %f", expected, got)
	}
}
