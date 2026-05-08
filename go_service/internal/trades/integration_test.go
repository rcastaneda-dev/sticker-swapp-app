//go:build integration

package trades_test

import (
	"context"
	"sync"
	"testing"

	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/testutil"
	"github.com/wc2026-stickers/sticker-swap-app/go_service/internal/trades"
)

func TestIntegration_ExecuteTrade_HappyPath(t *testing.T) {
	ctx := context.Background()
	pool := testutil.MustPool(t, 0)

	alice, err := testutil.CreateTestUser(ctx, pool, "alice-happy@test.local")
	if err != nil {
		t.Fatalf("create alice: %v", err)
	}
	bob, err := testutil.CreateTestUser(ctx, pool, "bob-happy@test.local")
	if err != nil {
		t.Fatalf("create bob: %v", err)
	}
	t.Cleanup(func() {
		_ = testutil.Cleanup(context.Background(), pool, []string{alice, bob})
	})

	// Alice: sticker #1 DUPLICATE qty 2
	if err := testutil.SeedInventory(ctx, pool, alice, []testutil.InventoryItem{
		{StickerID: 1, Status: "DUPLICATE", Quantity: 2},
	}); err != nil {
		t.Fatalf("seed alice: %v", err)
	}

	// Bob: sticker #10 DUPLICATE qty 2
	if err := testutil.SeedInventory(ctx, pool, bob, []testutil.InventoryItem{
		{StickerID: 10, Status: "DUPLICATE", Quantity: 2},
	}); err != nil {
		t.Fatalf("seed bob: %v", err)
	}

	matchID, err := testutil.CreateMatch(ctx, pool, alice, bob)
	if err != nil {
		t.Fatalf("create match: %v", err)
	}

	if _, err := testutil.LockInventory(ctx, pool, alice, matchID); err != nil {
		t.Fatalf("lock alice: %v", err)
	}
	if _, err := testutil.LockInventory(ctx, pool, bob, matchID); err != nil {
		t.Fatalf("lock bob: %v", err)
	}

	executor := trades.NewTradeExecutor(pool)
	result, err := executor.ExecuteTrade(ctx, alice, trades.TradeRequest{
		MatchID:             matchID,
		InitiatorStickerIDs: []int{1},
		ResponderStickerIDs: []int{10},
		IdempotencyKey:      testutil.NewUUID(),
	})
	if err != nil {
		t.Fatalf("ExecuteTrade error: %v", err)
	}

	if !result.Success {
		errMsg := "<nil>"
		if result.Error != nil {
			errMsg = *result.Error
		}
		t.Fatalf("expected success, got error: %s", errMsg)
	}
	if result.AlreadyCompleted {
		t.Fatal("expected AlreadyCompleted=false for fresh trade")
	}
	if result.TradeID == nil || *result.TradeID == "" {
		t.Fatal("expected non-empty TradeID")
	}
	if result.Status == nil || *result.Status != "COMPLETED" {
		t.Fatalf("expected status COMPLETED, got %v", result.Status)
	}

	// Verify Alice's sticker #1: qty 2 DUPLICATE → qty 1 (status may stay DUPLICATE or become OWNED depending on RPC logic)
	var aliceQty int
	var aliceStatus, aliceTrade string
	err = pool.QueryRow(ctx,
		"SELECT status::text, quantity, trade_status::text FROM user_inventory WHERE user_id = $1::uuid AND sticker_id = $2",
		alice, 1,
	).Scan(&aliceStatus, &aliceQty, &aliceTrade)
	if err != nil {
		t.Fatalf("query alice sticker #1: %v", err)
	}
	if aliceQty != 1 {
		t.Errorf("alice sticker #1 quantity: got %d, want 1", aliceQty)
	}
	if aliceTrade != "AVAILABLE" {
		t.Errorf("alice sticker #1 trade_status: got %s, want AVAILABLE", aliceTrade)
	}

	// Verify Alice received sticker #10
	var aliceNewQty int
	var aliceNewStatus string
	err = pool.QueryRow(ctx,
		"SELECT status::text, quantity FROM user_inventory WHERE user_id = $1::uuid AND sticker_id = $2",
		alice, 10,
	).Scan(&aliceNewStatus, &aliceNewQty)
	if err != nil {
		t.Fatalf("query alice sticker #10: %v", err)
	}
	if aliceNewQty != 1 {
		t.Errorf("alice sticker #10 quantity: got %d, want 1", aliceNewQty)
	}
	if aliceNewStatus != "OWNED" {
		t.Errorf("alice sticker #10 status: got %s, want OWNED", aliceNewStatus)
	}

	// Verify Bob's sticker #10: qty 2 DUPLICATE → qty 1 (sent one away)
	var bobQty int
	err = pool.QueryRow(ctx,
		"SELECT quantity FROM user_inventory WHERE user_id = $1::uuid AND sticker_id = $2",
		bob, 10,
	).Scan(&bobQty)
	if err != nil {
		t.Fatalf("query bob sticker #10: %v", err)
	}
	if bobQty != 1 {
		t.Errorf("bob sticker #10 quantity: got %d, want 1", bobQty)
	}

	// Verify Bob received sticker #1 (didn't have it before — should be OWNED qty 1)
	var bobNewQty int
	var bobNewStatus string
	err = pool.QueryRow(ctx,
		"SELECT status::text, quantity FROM user_inventory WHERE user_id = $1::uuid AND sticker_id = $2",
		bob, 1,
	).Scan(&bobNewStatus, &bobNewQty)
	if err != nil {
		t.Fatalf("query bob sticker #1: %v", err)
	}
	if bobNewQty != 1 {
		t.Errorf("bob sticker #1 quantity: got %d, want 1", bobNewQty)
	}
	if bobNewStatus != "OWNED" {
		t.Errorf("bob sticker #1 status: got %s, want OWNED", bobNewStatus)
	}

	// Verify match status is COMPLETED
	var matchStatus string
	err = pool.QueryRow(ctx,
		"SELECT status::text FROM matches WHERE id = $1::uuid", matchID,
	).Scan(&matchStatus)
	if err != nil {
		t.Fatalf("query match status: %v", err)
	}
	if matchStatus != "COMPLETED" {
		t.Errorf("match status: got %s, want COMPLETED", matchStatus)
	}

	// Verify exactly 1 trade audit record
	var auditCount int
	err = pool.QueryRow(ctx,
		"SELECT count(*) FROM trade_audit_log WHERE match_id = $1::uuid", matchID,
	).Scan(&auditCount)
	if err != nil {
		t.Fatalf("query audit count: %v", err)
	}
	if auditCount != 1 {
		t.Errorf("audit record count: got %d, want 1", auditCount)
	}

	// Verify locks released with TRADE_COMPLETED
	var releasedCount int
	err = pool.QueryRow(ctx,
		"SELECT count(*) FROM inventory_locks WHERE match_id = $1::uuid AND released_at IS NOT NULL AND release_reason = 'TRADE_COMPLETED'",
		matchID,
	).Scan(&releasedCount)
	if err != nil {
		t.Fatalf("query lock release: %v", err)
	}
	if releasedCount != 2 {
		t.Errorf("released lock count: got %d, want 2 (both users)", releasedCount)
	}
}

func TestIntegration_ExecuteTrade_100Concurrent_ZeroDoubleTrades(t *testing.T) {
	const goroutines = 100

	ctx := context.Background()
	pool := testutil.MustPool(t, goroutines+5)

	alice, err := testutil.CreateTestUser(ctx, pool, "alice-concurrent@test.local")
	if err != nil {
		t.Fatalf("create alice: %v", err)
	}
	bob, err := testutil.CreateTestUser(ctx, pool, "bob-concurrent@test.local")
	if err != nil {
		t.Fatalf("create bob: %v", err)
	}
	t.Cleanup(func() {
		_ = testutil.Cleanup(context.Background(), pool, []string{alice, bob})
	})

	if err := testutil.SeedInventory(ctx, pool, alice, []testutil.InventoryItem{
		{StickerID: 1, Status: "DUPLICATE", Quantity: 2},
	}); err != nil {
		t.Fatalf("seed alice: %v", err)
	}
	if err := testutil.SeedInventory(ctx, pool, bob, []testutil.InventoryItem{
		{StickerID: 10, Status: "DUPLICATE", Quantity: 2},
	}); err != nil {
		t.Fatalf("seed bob: %v", err)
	}

	matchID, err := testutil.CreateMatch(ctx, pool, alice, bob)
	if err != nil {
		t.Fatalf("create match: %v", err)
	}

	if _, err := testutil.LockInventory(ctx, pool, alice, matchID); err != nil {
		t.Fatalf("lock alice: %v", err)
	}
	if _, err := testutil.LockInventory(ctx, pool, bob, matchID); err != nil {
		t.Fatalf("lock bob: %v", err)
	}

	executor := trades.NewTradeExecutor(pool)

	type outcome struct {
		result *trades.TradeResult
		err    error
	}

	results := make([]outcome, goroutines)

	// Two-phase barrier: all goroutines ready, then release simultaneously
	var ready sync.WaitGroup
	ready.Add(goroutines)
	var start sync.WaitGroup
	start.Add(1)
	var done sync.WaitGroup
	done.Add(goroutines)

	for i := 0; i < goroutines; i++ {
		go func(idx int) {
			defer done.Done()
			ready.Done() // signal ready
			start.Wait() // wait for all goroutines to line up

			r, e := executor.ExecuteTrade(ctx, alice, trades.TradeRequest{
				MatchID:             matchID,
				InitiatorStickerIDs: []int{1},
				ResponderStickerIDs: []int{10},
				IdempotencyKey:      testutil.NewUUID(),
			})
			results[idx] = outcome{result: r, err: e}
		}(i)
	}

	ready.Wait() // all goroutines are staged
	start.Done() // release them all at once
	done.Wait()  // wait for all to finish

	// Count outcomes
	successCount := 0
	matchNotPendingCount := 0
	otherErrorCount := 0
	pgErrorCount := 0

	for i, o := range results {
		if o.err != nil {
			pgErrorCount++
			t.Logf("goroutine %d: pgx error: %v", i, o.err)
			continue
		}
		if o.result.Success && !o.result.AlreadyCompleted {
			successCount++
		} else if o.result.Error != nil && *o.result.Error == "MATCH_NOT_PENDING" {
			matchNotPendingCount++
		} else {
			otherErrorCount++
			errMsg := "<nil>"
			if o.result.Error != nil {
				errMsg = *o.result.Error
			}
			t.Logf("goroutine %d: other result: success=%v already=%v error=%s",
				i, o.result.Success, o.result.AlreadyCompleted, errMsg)
		}
	}

	t.Logf("results: success=%d matchNotPending=%d pgError=%d other=%d",
		successCount, matchNotPendingCount, pgErrorCount, otherErrorCount)

	// THE critical assertion: exactly 1 trade succeeded
	if successCount != 1 {
		t.Fatalf("ZERO DOUBLE-TRADES VIOLATED: expected exactly 1 success out of %d, got %d", goroutines, successCount)
	}

	// Verify DB state: exactly 1 audit record
	var auditCount int
	err = pool.QueryRow(ctx,
		"SELECT count(*) FROM trade_audit_log WHERE match_id = $1::uuid", matchID,
	).Scan(&auditCount)
	if err != nil {
		t.Fatalf("query audit count: %v", err)
	}
	if auditCount != 1 {
		t.Fatalf("DOUBLE-TRADE DETECTED: audit record count = %d, want 1", auditCount)
	}

	// Verify sender's sticker transferred exactly once (qty 2 → 1)
	var aliceQty int
	err = pool.QueryRow(ctx,
		"SELECT quantity FROM user_inventory WHERE user_id = $1::uuid AND sticker_id = 1",
		alice,
	).Scan(&aliceQty)
	if err != nil {
		t.Fatalf("query alice sticker #1: %v", err)
	}
	if aliceQty != 1 {
		t.Errorf("DOUBLE-TRADE DETECTED: alice sticker #1 quantity = %d, want 1", aliceQty)
	}

	// Verify recipient received exactly 1 sticker (Bob didn't have sticker #1 before)
	var bobQty int
	err = pool.QueryRow(ctx,
		"SELECT quantity FROM user_inventory WHERE user_id = $1::uuid AND sticker_id = 1",
		bob,
	).Scan(&bobQty)
	if err != nil {
		t.Fatalf("query bob sticker #1: %v", err)
	}
	if bobQty != 1 {
		t.Errorf("bob sticker #1 quantity: got %d, want 1", bobQty)
	}

	// Verify match status
	var matchStatus string
	err = pool.QueryRow(ctx,
		"SELECT status::text FROM matches WHERE id = $1::uuid", matchID,
	).Scan(&matchStatus)
	if err != nil {
		t.Fatalf("query match: %v", err)
	}
	if matchStatus != "COMPLETED" {
		t.Errorf("match status: got %s, want COMPLETED", matchStatus)
	}
}

func TestIntegration_ExecuteTrade_Idempotency(t *testing.T) {
	ctx := context.Background()
	pool := testutil.MustPool(t, 0)

	alice, err := testutil.CreateTestUser(ctx, pool, "alice-idempotent@test.local")
	if err != nil {
		t.Fatalf("create alice: %v", err)
	}
	bob, err := testutil.CreateTestUser(ctx, pool, "bob-idempotent@test.local")
	if err != nil {
		t.Fatalf("create bob: %v", err)
	}
	t.Cleanup(func() {
		_ = testutil.Cleanup(context.Background(), pool, []string{alice, bob})
	})

	if err := testutil.SeedInventory(ctx, pool, alice, []testutil.InventoryItem{
		{StickerID: 1, Status: "DUPLICATE", Quantity: 2},
	}); err != nil {
		t.Fatalf("seed alice: %v", err)
	}
	if err := testutil.SeedInventory(ctx, pool, bob, []testutil.InventoryItem{
		{StickerID: 10, Status: "DUPLICATE", Quantity: 2},
	}); err != nil {
		t.Fatalf("seed bob: %v", err)
	}

	matchID, err := testutil.CreateMatch(ctx, pool, alice, bob)
	if err != nil {
		t.Fatalf("create match: %v", err)
	}
	if _, err := testutil.LockInventory(ctx, pool, alice, matchID); err != nil {
		t.Fatalf("lock alice: %v", err)
	}
	if _, err := testutil.LockInventory(ctx, pool, bob, matchID); err != nil {
		t.Fatalf("lock bob: %v", err)
	}

	executor := trades.NewTradeExecutor(pool)
	idempotencyKey := testutil.NewUUID()
	req := trades.TradeRequest{
		MatchID:             matchID,
		InitiatorStickerIDs: []int{1},
		ResponderStickerIDs: []int{10},
		IdempotencyKey:      idempotencyKey,
	}

	// First call — should execute the trade
	result1, err := executor.ExecuteTrade(ctx, alice, req)
	if err != nil {
		t.Fatalf("first call error: %v", err)
	}
	if !result1.Success {
		t.Fatalf("first call not successful: %v", result1.Error)
	}
	if result1.AlreadyCompleted {
		t.Fatal("first call should not be AlreadyCompleted")
	}

	// Second call — same idempotency key, should return same result
	result2, err := executor.ExecuteTrade(ctx, alice, req)
	if err != nil {
		t.Fatalf("second call error: %v", err)
	}
	if !result2.Success {
		t.Fatalf("second call not successful: %v", result2.Error)
	}
	if !result2.AlreadyCompleted {
		t.Fatal("second call should be AlreadyCompleted")
	}

	// Same trade ID returned
	if result1.TradeID == nil || result2.TradeID == nil {
		t.Fatal("both calls should return trade IDs")
	}
	if *result1.TradeID != *result2.TradeID {
		t.Errorf("trade IDs differ: first=%s second=%s", *result1.TradeID, *result2.TradeID)
	}

	// Enriched idempotent response fields (migration 0022)
	if result2.MatchID == nil || *result2.MatchID != matchID {
		t.Errorf("idempotent response missing match_id")
	}
	if result2.InitiatorID == nil || *result2.InitiatorID != alice {
		t.Errorf("idempotent response missing initiator_id")
	}

	// Verify exactly 1 audit record (not 2)
	var auditCount int
	err = pool.QueryRow(ctx,
		"SELECT count(*) FROM trade_audit_log WHERE match_id = $1::uuid", matchID,
	).Scan(&auditCount)
	if err != nil {
		t.Fatalf("query audit count: %v", err)
	}
	if auditCount != 1 {
		t.Errorf("audit record count: got %d, want 1", auditCount)
	}
}

func TestIntegration_ExecuteTrade_SharedSticker_TwoMatches(t *testing.T) {
	ctx := context.Background()
	pool := testutil.MustPool(t, 0)

	alice, err := testutil.CreateTestUser(ctx, pool, "alice-shared@test.local")
	if err != nil {
		t.Fatalf("create alice: %v", err)
	}
	bob, err := testutil.CreateTestUser(ctx, pool, "bob-shared@test.local")
	if err != nil {
		t.Fatalf("create bob: %v", err)
	}
	charlie, err := testutil.CreateTestUser(ctx, pool, "charlie-shared@test.local")
	if err != nil {
		t.Fatalf("create charlie: %v", err)
	}
	t.Cleanup(func() {
		_ = testutil.Cleanup(context.Background(), pool, []string{alice, bob, charlie})
	})

	// Alice: sticker #1 DUPLICATE qty 2 (only 1 extra copy to trade)
	if err := testutil.SeedInventory(ctx, pool, alice, []testutil.InventoryItem{
		{StickerID: 1, Status: "DUPLICATE", Quantity: 2},
	}); err != nil {
		t.Fatalf("seed alice: %v", err)
	}
	// Bob: sticker #10 DUPLICATE qty 2
	if err := testutil.SeedInventory(ctx, pool, bob, []testutil.InventoryItem{
		{StickerID: 10, Status: "DUPLICATE", Quantity: 2},
	}); err != nil {
		t.Fatalf("seed bob: %v", err)
	}
	// Charlie: sticker #20 DUPLICATE qty 2
	if err := testutil.SeedInventory(ctx, pool, charlie, []testutil.InventoryItem{
		{StickerID: 20, Status: "DUPLICATE", Quantity: 2},
	}); err != nil {
		t.Fatalf("seed charlie: %v", err)
	}

	// Match A: Alice + Bob
	matchA, err := testutil.CreateMatch(ctx, pool, alice, bob)
	if err != nil {
		t.Fatalf("create match A: %v", err)
	}
	// Match B: Alice + Charlie
	matchB, err := testutil.CreateMatch(ctx, pool, alice, charlie)
	if err != nil {
		t.Fatalf("create match B: %v", err)
	}

	// Lock Match A for both participants — should succeed
	if _, err := testutil.LockInventory(ctx, pool, alice, matchA); err != nil {
		t.Fatalf("lock alice for match A: %v", err)
	}
	if _, err := testutil.LockInventory(ctx, pool, bob, matchA); err != nil {
		t.Fatalf("lock bob for match A: %v", err)
	}

	// Attempt to lock Alice for Match B — should FAIL because sticker #1 is already RESERVED
	success, errCode, err := testutil.LockInventoryRaw(ctx, pool, alice, matchB)
	if err != nil {
		t.Fatalf("lock alice for match B (raw): %v", err)
	}
	if success {
		t.Fatal("lock for match B should have failed — Alice's sticker #1 is already locked for match A")
	}
	// The RPC should return STICKERS_NOT_AVAILABLE or STICKERS_ALREADY_LOCKED
	if errCode != "STICKERS_NOT_AVAILABLE" && errCode != "STICKERS_ALREADY_LOCKED" && errCode != "NO_DUPLICATES" {
		t.Errorf("unexpected lock error code: %s (expected STICKERS_NOT_AVAILABLE or STICKERS_ALREADY_LOCKED)", errCode)
	}
	t.Logf("lock for match B correctly rejected with: %s", errCode)

	// Execute trade on Match A — should succeed
	executor := trades.NewTradeExecutor(pool)
	result, err := executor.ExecuteTrade(ctx, alice, trades.TradeRequest{
		MatchID:             matchA,
		InitiatorStickerIDs: []int{1},
		ResponderStickerIDs: []int{10},
		IdempotencyKey:      testutil.NewUUID(),
	})
	if err != nil {
		t.Fatalf("execute trade A error: %v", err)
	}
	if !result.Success {
		errMsg := "<nil>"
		if result.Error != nil {
			errMsg = *result.Error
		}
		t.Fatalf("trade A should succeed: %s", errMsg)
	}

	// Verify Alice's sticker #1 was transferred exactly once
	var aliceQty int
	err = pool.QueryRow(ctx,
		"SELECT quantity FROM user_inventory WHERE user_id = $1::uuid AND sticker_id = 1",
		alice,
	).Scan(&aliceQty)
	if err != nil {
		t.Fatalf("query alice sticker #1: %v", err)
	}
	if aliceQty != 1 {
		t.Errorf("alice sticker #1 quantity: got %d, want 1 (transferred once)", aliceQty)
	}

	// Verify only 1 trade audit record across both matches
	var totalAudits int
	err = pool.QueryRow(ctx,
		"SELECT count(*) FROM trade_audit_log WHERE initiator_id = $1::uuid OR responder_id = $1::uuid",
		alice,
	).Scan(&totalAudits)
	if err != nil {
		t.Fatalf("query total audits: %v", err)
	}
	if totalAudits != 1 {
		t.Errorf("total audit records for alice: got %d, want 1", totalAudits)
	}
}
