package matchmaking

import (
	"context"
	"fmt"
	"math"
	"sort"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ScoringWeights controls the composite formula weights.
type ScoringWeights struct {
	Proximity  float64
	Reciprocal float64
	Activity   float64
}

// DefaultWeights returns Proximity 0.5, Reciprocal 0.3, Activity 0.2.
func DefaultWeights() ScoringWeights {
	return ScoringWeights{
		Proximity:  0.5,
		Reciprocal: 0.3,
		Activity:   0.2,
	}
}

// ScoringConfig holds tuning parameters for normalization.
type ScoringConfig struct {
	Weights            ScoringWeights
	ReciprocalCap      int     // max match_score for normalization (default 20)
	ActivityDecayHours float64 // half-life in hours (default 24)
}

// DefaultConfig returns the default scoring configuration.
func DefaultConfig() ScoringConfig {
	return ScoringConfig{
		Weights:            DefaultWeights(),
		ReciprocalCap:      20,
		ActivityDecayHours: 24,
	}
}

// NearbyTrader is the row returned by find_nearby_traders().
type NearbyTrader struct {
	UserID            string
	DistanceM         float64
	DisplayName       string
	DuplicateCount    int64
	NeededCount       int64
	LocationUpdatedAt time.Time
}

// ReciprocalMatch is the row returned by get_reciprocal_matches().
type ReciprocalMatch struct {
	UserID        string
	TheyHaveINeed int64
	IHaveTheyNeed int64
	MatchScore    int64
}

// ScoredMatch is the final output of the scoring engine.
type ScoredMatch struct {
	UserID          string  `json:"user_id"`
	DisplayName     string  `json:"display_name"`
	DistanceM       float64 `json:"distance_m"`
	DuplicateCount  int64   `json:"duplicate_count"`
	NeededCount     int64   `json:"needed_count"`
	TheyHaveINeed   int64   `json:"they_have_i_need"`
	IHaveTheyNeed   int64   `json:"i_have_they_need"`
	ProximityScore  float64 `json:"proximity_score"`
	ReciprocalScore float64 `json:"reciprocal_score"`
	ActivityScore   float64 `json:"activity_score"`
	TotalScore      float64 `json:"total_score"`
}

// Scorer computes scored matches for a user.
type Scorer interface {
	ScoreMatches(ctx context.Context, userID string, lat, lng float64, radiusM int) ([]ScoredMatch, error)
}

// DBScorer is the production implementation backed by pgx.
type DBScorer struct {
	pool   *pgxpool.Pool
	config ScoringConfig
}

// NewScorer creates a DBScorer with the given pool and config.
func NewScorer(pool *pgxpool.Pool, config ScoringConfig) *DBScorer {
	return &DBScorer{pool: pool, config: config}
}

// ScoreMatches fetches nearby traders and reciprocal data, then computes
// and returns composite-scored matches sorted by TotalScore descending.
func (s *DBScorer) ScoreMatches(ctx context.Context, userID string, lat, lng float64, radiusM int) ([]ScoredMatch, error) {
	traders, err := s.fetchNearbyTraders(ctx, userID, lat, lng, radiusM)
	if err != nil {
		return nil, fmt.Errorf("fetch nearby traders: %w", err)
	}
	if len(traders) == 0 {
		return []ScoredMatch{}, nil
	}

	nearbyIDs := make([]string, len(traders))
	for i, t := range traders {
		nearbyIDs[i] = t.UserID
	}

	reciprocals, err := s.fetchReciprocalMatches(ctx, userID, nearbyIDs)
	if err != nil {
		return nil, fmt.Errorf("fetch reciprocal matches: %w", err)
	}

	reciprocalMap := make(map[string]ReciprocalMatch, len(reciprocals))
	for _, r := range reciprocals {
		reciprocalMap[r.UserID] = r
	}

	now := time.Now()
	results := make([]ScoredMatch, 0, len(traders))
	for _, t := range traders {
		rm := reciprocalMap[t.UserID]

		proxScore := NormalizeProximity(t.DistanceM, float64(radiusM))
		recipScore := NormalizeReciprocal(rm.MatchScore, s.config.ReciprocalCap)
		actScore := NormalizeActivity(t.LocationUpdatedAt, now, s.config.ActivityDecayHours)
		total := ComputeScore(proxScore, recipScore, actScore, s.config.Weights)

		results = append(results, ScoredMatch{
			UserID:          t.UserID,
			DisplayName:     t.DisplayName,
			DistanceM:       t.DistanceM,
			DuplicateCount:  t.DuplicateCount,
			NeededCount:     t.NeededCount,
			TheyHaveINeed:   rm.TheyHaveINeed,
			IHaveTheyNeed:   rm.IHaveTheyNeed,
			ProximityScore:  proxScore,
			ReciprocalScore: recipScore,
			ActivityScore:   actScore,
			TotalScore:      total,
		})
	}

	sort.Slice(results, func(i, j int) bool {
		return results[i].TotalScore > results[j].TotalScore
	})

	return results, nil
}

// fetchNearbyTraders calls the find_nearby_traders() RPC via pgx.
func (s *DBScorer) fetchNearbyTraders(ctx context.Context, userID string, lat, lng float64, radiusM int) ([]NearbyTrader, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, "SELECT set_config('request.jwt.claim.sub', $1, true)", userID); err != nil {
		return nil, err
	}

	rows, err := tx.Query(ctx,
		"SELECT user_id, distance_m, display_name, duplicate_count, needed_count, location_updated_at FROM find_nearby_traders($1, $2, $3)",
		lat, lng, radiusM,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var traders []NearbyTrader
	for rows.Next() {
		var t NearbyTrader
		if err := rows.Scan(&t.UserID, &t.DistanceM, &t.DisplayName, &t.DuplicateCount, &t.NeededCount, &t.LocationUpdatedAt); err != nil {
			return nil, err
		}
		traders = append(traders, t)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return traders, nil
}

// fetchReciprocalMatches calls the get_reciprocal_matches() RPC via pgx.
func (s *DBScorer) fetchReciprocalMatches(ctx context.Context, userID string, nearbyIDs []string) ([]ReciprocalMatch, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, "SELECT set_config('request.jwt.claim.sub', $1, true)", userID); err != nil {
		return nil, err
	}

	rows, err := tx.Query(ctx,
		"SELECT user_id, they_have_i_need, i_have_they_need, match_score FROM get_reciprocal_matches($1::uuid[])",
		nearbyIDs,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var matches []ReciprocalMatch
	for rows.Next() {
		var m ReciprocalMatch
		if err := rows.Scan(&m.UserID, &m.TheyHaveINeed, &m.IHaveTheyNeed, &m.MatchScore); err != nil {
			return nil, err
		}
		matches = append(matches, m)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return matches, nil
}

// --- Pure scoring functions (no DB dependency) ---

// NormalizeProximity returns [0,1] where closer distance = higher score.
// Formula: 1 - (distanceM / radiusM), clamped to [0,1].
func NormalizeProximity(distanceM, radiusM float64) float64 {
	if radiusM <= 0 {
		return 0
	}
	return clamp(1-(distanceM/radiusM), 0, 1)
}

// NormalizeReciprocal returns [0,1] based on match_score vs cap.
// Formula: min(matchScore, cap) / cap.
func NormalizeReciprocal(matchScore int64, cap int) float64 {
	if cap <= 0 {
		return 0
	}
	effective := matchScore
	if effective > int64(cap) {
		effective = int64(cap)
	}
	return float64(effective) / float64(cap)
}

// NormalizeActivity returns [0,1] using exponential decay.
// Formula: exp(-ln(2) * hoursSince / halfLife).
// A 24h half-life: 0h → 1.0, 24h → 0.5, 48h → 0.25.
func NormalizeActivity(updatedAt, now time.Time, decayHalfLifeHours float64) float64 {
	if decayHalfLifeHours <= 0 {
		return 0
	}
	hoursSince := now.Sub(updatedAt).Hours()
	if hoursSince < 0 {
		hoursSince = 0
	}
	lambda := math.Log(2) / decayHalfLifeHours
	return math.Exp(-lambda * hoursSince)
}

// ComputeScore applies the weighted scoring formula.
func ComputeScore(proximity, reciprocal, activity float64, w ScoringWeights) float64 {
	return proximity*w.Proximity + reciprocal*w.Reciprocal + activity*w.Activity
}

func clamp(v, min, max float64) float64 {
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}
