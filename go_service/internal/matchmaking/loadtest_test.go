//go:build integration

package matchmaking

import (
	"context"
	"fmt"
	"math"
	"math/rand"
	"os"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// loadTestConfig controls the load test parameters.
type loadTestConfig struct {
	// Database seeding
	NumUsers        int     // total users with locations + inventory
	CenterLat       float64 // geographic center latitude
	CenterLng       float64 // geographic center longitude
	SpreadKm        float64 // radius in km to spread users around center
	StickersPerUser int     // number of stickers per user (mix of OWNED/DUPLICATE/NEEDED)

	// Query parameters
	QueryRadiusM    int // radius for each find_nearby_traders() call
	QueryTimeoutSec int // per-query timeout in seconds

	// Benchmark
	SamplesPerVariant int // EXPLAIN ANALYZE samples per variant

	// Acceptance criteria
	P95TargetMs float64 // p95 latency target in milliseconds
}

func defaultLoadTestConfig() loadTestConfig {
	return loadTestConfig{
		NumUsers:          1000,
		CenterLat:         13.6929, // San Salvador, El Salvador
		CenterLng:         -89.2182,
		SpreadKm:          25, // 25 km spread around city center
		StickersPerUser:   50,
		QueryRadiusM:      5000, // 5 km default radius
		QueryTimeoutSec:   10,
		SamplesPerVariant: 200,
		P95TargetMs:       100,
	}
}

// variantDef defines a find_nearby_traders variant to benchmark.
type variantDef struct {
	Name     string // display name
	FuncName string // PostgreSQL function name
}

// benchmarkVariants returns the list of variants to test.
// After migration 0029, find_nearby_traders uses denormalized columns.
// The variant functions have been dropped. To re-run the full comparison,
// revert migration 0029 and re-apply 0028.
func benchmarkVariants() []variantDef {
	return []variantDef{
		{Name: "find_nearby_traders", FuncName: "find_nearby_traders"},
	}
}

// variantResult holds benchmark results for one variant.
type variantResult struct {
	Name    string
	Timings []float64 // sorted server-side execution times in ms
	Errors  int
}

// TestLoadProximityQueries seeds the database with realistic data and
// benchmarks find_nearby_traders() variants via EXPLAIN ANALYZE to measure
// pure server-side execution time.
//
// Prerequisites:
//   - TEST_DATABASE_URL or SUPABASE_DB_URL env var set (direct connection, not pooler)
//   - All migrations applied (including 0028 benchmark variants)
//
// Run:
//
//	make test-loadtest
func TestLoadProximityQueries(t *testing.T) {
	dbURL := os.Getenv("TEST_DATABASE_URL")
	if dbURL == "" {
		dbURL = os.Getenv("SUPABASE_DB_URL")
	}
	if dbURL == "" {
		t.Skip("no TEST_DATABASE_URL or SUPABASE_DB_URL set; skipping load test")
	}

	cfg := defaultLoadTestConfig()
	ctx := context.Background()

	// --- Setup pool ---
	poolCfg, err := pgxpool.ParseConfig(dbURL)
	if err != nil {
		t.Fatalf("parse config: %v", err)
	}
	poolCfg.ConnConfig.DefaultQueryExecMode = pgx.QueryExecModeSimpleProtocol
	poolCfg.MaxConns = 20

	pool, err := pgxpool.NewWithConfig(ctx, poolCfg)
	if err != nil {
		t.Fatalf("create pool: %v", err)
	}
	defer pool.Close()

	if err := pool.Ping(ctx); err != nil {
		t.Fatalf("ping: %v", err)
	}

	// --- Seed data ---
	t.Logf("Seeding %d users around (%.4f, %.4f) with %.0f km spread...",
		cfg.NumUsers, cfg.CenterLat, cfg.CenterLng, cfg.SpreadKm)

	seedStart := time.Now()
	userIDs, err := seedLoadTestData(ctx, pool, cfg)
	if err != nil {
		t.Fatalf("seed data: %v", err)
	}
	t.Logf("Seeded %d users in %s", len(userIDs), time.Since(seedStart).Round(time.Millisecond))

	// Cleanup after test
	t.Cleanup(func() {
		t.Log("Cleaning up load test data...")
		cleanupLoadTestData(context.Background(), pool, userIDs)
		t.Log("Cleanup complete")
	})

	// Refresh matview now that data is seeded (trigger only fires on subsequent changes)
	_, _ = pool.Exec(ctx, "REFRESH MATERIALIZED VIEW CONCURRENTLY trader_inventory_stats")

	// --- Benchmark all variants via EXPLAIN ANALYZE ---
	variants := benchmarkVariants()
	results := make([]variantResult, len(variants))

	for i, v := range variants {
		t.Logf("Benchmarking [%s] (%d samples)...", v.Name, cfg.SamplesPerVariant)
		timings, errors := measureVariant(ctx, t, pool, cfg, userIDs, v.FuncName, cfg.SamplesPerVariant)
		results[i] = variantResult{
			Name:    v.Name,
			Timings: timings,
			Errors:  errors,
		}
		if len(timings) > 0 {
			t.Logf("  → p50=%.1f ms  p95=%.1f ms  avg=%.1f ms  (%d errors)",
				percentile(timings, 50), percentile(timings, 95),
				avg(timings), errors)
		} else {
			t.Logf("  → no timings collected (%d errors)", errors)
		}
	}

	// --- Print comparison report ---
	printBenchmarkReport(t, results, cfg)
}

// measureVariant runs EXPLAIN ANALYZE against a specific function variant.
func measureVariant(ctx context.Context, t *testing.T, pool *pgxpool.Pool, cfg loadTestConfig, userIDs []string, funcName string, sampleCount int) ([]float64, int) {
	rng := rand.New(rand.NewSource(99)) // same seed for all variants = same query params
	timings := make([]float64, 0, sampleCount)
	errors := 0

	query := fmt.Sprintf(
		"EXPLAIN (ANALYZE, FORMAT TEXT) SELECT user_id, distance_m, display_name, duplicate_count, needed_count, location_updated_at FROM %s($1, $2, $3)",
		funcName,
	)

	for i := 0; i < sampleCount; i++ {
		callerID := userIDs[rng.Intn(len(userIDs))]
		lat, lng := randomPointInRadius(rng, cfg.CenterLat, cfg.CenterLng, cfg.SpreadKm*0.8)

		tx, err := pool.Begin(ctx)
		if err != nil {
			errors++
			continue
		}

		if _, err := tx.Exec(ctx, "SELECT set_config('request.jwt.claim.sub', $1, true)", callerID); err != nil {
			tx.Rollback(ctx)
			errors++
			continue
		}

		rows, err := tx.Query(ctx, query, lat, lng, cfg.QueryRadiusM)
		if err != nil {
			tx.Rollback(ctx)
			errors++
			if i == 0 {
				t.Logf("  WARNING: %s query error: %v", funcName, err)
			}
			continue
		}

		var executionTimeMs float64
		for rows.Next() {
			var line string
			if err := rows.Scan(&line); err != nil {
				continue
			}
			if strings.Contains(line, "Execution Time:") {
				parts := strings.Fields(line)
				for j, p := range parts {
					if p == "Time:" && j+1 < len(parts) {
						fmt.Sscanf(parts[j+1], "%f", &executionTimeMs)
					}
				}
			}
		}
		rows.Close()
		tx.Commit(ctx)

		if executionTimeMs > 0 {
			timings = append(timings, executionTimeMs)
		}
	}

	sort.Float64s(timings)
	return timings, errors
}

// printBenchmarkReport outputs a comparative table of all variant results.
func printBenchmarkReport(t *testing.T, results []variantResult, cfg loadTestConfig) {
	t.Logf("")
	t.Logf("================================================================")
	t.Logf("  PostGIS Proximity Query Benchmark — Variant Comparison")
	t.Logf("================================================================")
	t.Logf("  Config: %d users, %d samples/variant, %d m radius, %d stickers/user",
		cfg.NumUsers, cfg.SamplesPerVariant, cfg.QueryRadiusM, cfg.StickersPerUser)
	t.Logf("  Target: p95 < %.0f ms", cfg.P95TargetMs)
	t.Logf("================================================================")
	t.Logf("")
	t.Logf("  %-26s %8s %8s %8s %8s %8s %6s", "Variant", "Min", "Avg", "p50", "p95", "p99", "Pass?")
	t.Logf("  %-26s %8s %8s %8s %8s %8s %6s", "-------", "---", "---", "---", "---", "---", "-----")

	var bestVariant string
	bestP95 := math.MaxFloat64

	for _, r := range results {
		if len(r.Timings) == 0 {
			t.Logf("  %-26s  (no data — %d errors)", r.Name, r.Errors)
			continue
		}

		p95 := percentile(r.Timings, 95)
		pass := "FAIL"
		if p95 <= cfg.P95TargetMs {
			pass = "PASS"
		}

		t.Logf("  %-26s %7.1f %7.1f %7.1f %7.1f %7.1f %6s",
			r.Name,
			r.Timings[0],
			avg(r.Timings),
			percentile(r.Timings, 50),
			p95,
			percentile(r.Timings, 99),
			pass,
		)

		if p95 < bestP95 {
			bestP95 = p95
			bestVariant = r.Name
		}
	}

	t.Logf("")
	t.Logf("  WINNER: %s (p95 = %.1f ms)", bestVariant, bestP95)
	t.Logf("================================================================")

	// Test passes if ANY variant meets the target (benchmark mode)
	anyPassed := false
	for _, r := range results {
		if len(r.Timings) > 0 && percentile(r.Timings, 95) <= cfg.P95TargetMs {
			anyPassed = true
			break
		}
	}
	if !anyPassed {
		t.Errorf("no variant achieved p95 < %.0f ms; best was %s at %.1f ms",
			cfg.P95TargetMs, bestVariant, bestP95)
	}
}

// percentile returns the given percentile value from sorted data.
func percentile(sorted []float64, pct float64) float64 {
	if len(sorted) == 0 {
		return 0
	}
	idx := int(math.Ceil(pct/100.0*float64(len(sorted)))) - 1
	if idx < 0 {
		idx = 0
	}
	if idx >= len(sorted) {
		idx = len(sorted) - 1
	}
	return sorted[idx]
}

// avg returns the mean of values.
func avg(data []float64) float64 {
	if len(data) == 0 {
		return 0
	}
	sum := 0.0
	for _, d := range data {
		sum += d
	}
	return sum / float64(len(data))
}

// seedLoadTestData creates test users with locations and inventory.
// Uses fast password hashing (md5 instead of bcrypt) to speed up seeding.
func seedLoadTestData(ctx context.Context, pool *pgxpool.Pool, cfg loadTestConfig) ([]string, error) {
	rng := rand.New(rand.NewSource(42)) // deterministic for reproducibility

	userIDs := make([]string, 0, cfg.NumUsers)

	// Batch insert users in groups of 50 for efficiency
	batchSize := 50
	for batchStart := 0; batchStart < cfg.NumUsers; batchStart += batchSize {
		batchEnd := batchStart + batchSize
		if batchEnd > cfg.NumUsers {
			batchEnd = cfg.NumUsers
		}

		tx, err := pool.Begin(ctx)
		if err != nil {
			return nil, fmt.Errorf("begin user batch tx: %w", err)
		}

		for i := batchStart; i < batchEnd; i++ {
			email := fmt.Sprintf("loadtest_%d@test.local", i)

			var userID string
			// Use md5 instead of bcrypt for speed — test users only
			err := tx.QueryRow(ctx, `
				INSERT INTO auth.users (
					instance_id, id, aud, role, email,
					encrypted_password, email_confirmed_at,
					created_at, updated_at, confirmation_token,
					raw_app_meta_data, raw_user_meta_data
				) VALUES (
					'00000000-0000-0000-0000-000000000000',
					gen_random_uuid(), 'authenticated', 'authenticated', $1::text,
					md5('loadtestpassword'),
					now(), now(), now(), '',
					'{"provider":"email","providers":["email"]}'::jsonb,
					jsonb_build_object('display_name', $2::text)
				) RETURNING id::text
			`, email, fmt.Sprintf("LoadUser%d", i)).Scan(&userID)
			if err != nil {
				tx.Rollback(ctx)
				return nil, fmt.Errorf("create user %d: %w", i, err)
			}
			userIDs = append(userIDs, userID)

			// Mark user as age-verified and NOT under-13
			_, err = tx.Exec(ctx, `
				UPDATE user_profiles
				SET is_under_13 = false,
				    age_verified_at = now(),
				    date_of_birth = '2000-01-01'
				WHERE user_id = $1::uuid
			`, userID)
			if err != nil {
				tx.Rollback(ctx)
				return nil, fmt.Errorf("update profile %d: %w", i, err)
			}
		}

		if err := tx.Commit(ctx); err != nil {
			return nil, fmt.Errorf("commit user batch: %w", err)
		}
	}

	// Batch insert locations
	for batchStart := 0; batchStart < len(userIDs); batchStart += batchSize {
		batchEnd := batchStart + batchSize
		if batchEnd > len(userIDs) {
			batchEnd = len(userIDs)
		}

		tx, err := pool.Begin(ctx)
		if err != nil {
			return nil, fmt.Errorf("begin location batch tx: %w", err)
		}

		for i := batchStart; i < batchEnd; i++ {
			lat, lng := randomPointInRadius(rng, cfg.CenterLat, cfg.CenterLng, cfg.SpreadKm)
			hoursAgo := rng.Intn(48)

			_, err = tx.Exec(ctx, `
				INSERT INTO user_locations (user_id, location, accuracy_m, updated_at)
				VALUES ($1::uuid, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography, 10, now() - ($4 || ' hours')::interval)
			`, userIDs[i], lng, lat, fmt.Sprintf("%d", hoursAgo))
			if err != nil {
				tx.Rollback(ctx)
				return nil, fmt.Errorf("insert location %d: %w", i, err)
			}
		}

		if err := tx.Commit(ctx); err != nil {
			return nil, fmt.Errorf("commit location batch: %w", err)
		}
	}

	// Batch insert inventory using multi-row VALUES
	for i, userID := range userIDs {
		if err := seedUserInventory(ctx, pool, userID, cfg.StickersPerUser, rng); err != nil {
			return nil, fmt.Errorf("seed inventory user %d: %w", i, err)
		}
	}

	// Force ANALYZE to update planner statistics after bulk insert
	_, _ = pool.Exec(ctx, "ANALYZE user_locations")
	_, _ = pool.Exec(ctx, "ANALYZE user_inventory")
	_, _ = pool.Exec(ctx, "ANALYZE user_profiles")

	return userIDs, nil
}

// seedUserInventory inserts a realistic mix of stickers for one user.
func seedUserInventory(ctx context.Context, pool *pgxpool.Pool, userID string, count int, rng *rand.Rand) error {
	// Pick random sticker IDs from 1-980
	stickerIDs := rng.Perm(980)[:count]

	// Build batch values
	var values []string
	var args []any
	argIdx := 2 // $1 is userID

	for _, sid := range stickerIDs {
		stickerID := sid + 1 // 1-indexed

		// 40% OWNED, 30% DUPLICATE, 30% NEEDED
		roll := rng.Float64()
		var status string
		var qty int
		switch {
		case roll < 0.4:
			status = "OWNED"
			qty = 1
		case roll < 0.7:
			status = "DUPLICATE"
			qty = 1 + rng.Intn(3) // 1-3 duplicates
		default:
			status = "NEEDED"
			qty = 1
		}

		values = append(values, fmt.Sprintf("($1::uuid, $%d, $%d::inventory_status, $%d, 'AVAILABLE'::trade_item_status)",
			argIdx, argIdx+1, argIdx+2))
		args = append(args, stickerID, status, qty)
		argIdx += 3
	}

	query := fmt.Sprintf(`
		INSERT INTO user_inventory (user_id, sticker_id, status, quantity, trade_status)
		VALUES %s
		ON CONFLICT (user_id, sticker_id) DO UPDATE
		SET status = EXCLUDED.status, quantity = EXCLUDED.quantity, trade_status = 'AVAILABLE'::trade_item_status
	`, strings.Join(values, ", "))

	allArgs := append([]any{userID}, args...)
	_, err := pool.Exec(ctx, query, allArgs...)
	return err
}

// randomPointInRadius generates a random lat/lng within radiusKm of center.
func randomPointInRadius(rng *rand.Rand, centerLat, centerLng, radiusKm float64) (float64, float64) {
	// Approximate: 1 degree latitude ≈ 111 km
	radiusDeg := radiusKm / 111.0
	angle := rng.Float64() * 2 * math.Pi
	dist := math.Sqrt(rng.Float64()) * radiusDeg // sqrt for uniform distribution in circle

	lat := centerLat + dist*math.Cos(angle)
	// Adjust longitude for latitude (degrees get smaller near poles)
	lngScale := math.Cos(centerLat * math.Pi / 180)
	lng := centerLng + (dist*math.Sin(angle))/lngScale

	return lat, lng
}

// cleanupLoadTestData removes all seeded load test users and their data.
func cleanupLoadTestData(ctx context.Context, pool *pgxpool.Pool, userIDs []string) {
	if len(userIDs) == 0 {
		return
	}

	// Delete in batches of 200 to avoid parameter limits
	batchSize := 200
	for start := 0; start < len(userIDs); start += batchSize {
		end := start + batchSize
		if end > len(userIDs) {
			end = len(userIDs)
		}
		batch := userIDs[start:end]

		queries := []string{
			"DELETE FROM user_locations WHERE user_id = ANY($1::uuid[])",
			"DELETE FROM inventory_locks WHERE user_id = ANY($1::uuid[])",
			"DELETE FROM user_inventory WHERE user_id = ANY($1::uuid[])",
			"DELETE FROM matches WHERE user1_id = ANY($1::uuid[]) OR user2_id = ANY($1::uuid[])",
			"DELETE FROM swipes WHERE swiper_id = ANY($1::uuid[]) OR target_id = ANY($1::uuid[])",
			"DELETE FROM user_profiles WHERE user_id = ANY($1::uuid[])",
			"DELETE FROM auth.users WHERE id = ANY($1::uuid[])",
		}

		for _, q := range queries {
			_, _ = pool.Exec(ctx, q, batch)
		}
	}
}
