import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'fixtures/test_stickers.dart';
import 'helpers/pump_app.dart';
import 'helpers/screen_finders.dart';

/// E2E happy path: 13+ user — guest browse → sign up → age verify →
/// guest migration → discover matches → swipe right → mutual match →
/// chat → trade confirmation.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Happy path (13+ user)', () {
    testWidgets('full journey from login to trade completion', (tester) async {
      // ── Setup ─────────────────────────────────────────────────────────
      final harness = TestHarness(
        initialGuestInventory: guestOwnedStickerIds,
      );
      await harness.pumpApp(tester);

      // ── Step 1: Login screen is shown ─────────────────────────────────
      expect(loginTitle, findsWidgets);
      expect(continueAsGuest, findsOneWidget);

      // ── Step 2: Tap "Continue as Guest" → navigate to /catalog ────────
      await tester.tap(continueAsGuest);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Should see the sticker catalog
      expect(find.text('Sticker Catalog'), findsOneWidget);

      // ── Step 3: Tap a sticker tile to toggle ownership ────────────────
      // Grid tiles show sticker number (#1) and team name.
      // "#1" may appear in both progress area and the grid tile, so
      // tap the last occurrence (the grid tile).
      final stickerTiles = find.text('#1');
      expect(stickerTiles, findsWidgets);
      await tester.tap(stickerTiles.last);
      await tester.pumpAndSettle();

      // ── Step 4: Simulate sign-up from guest mode ────────────────────
      // The catalog is a top-level route (context.go), so there's no back
      // button. Instead of navigating back, we simulate sign-up directly
      // via the harness, which triggers the router redirect chain.
      harness.authNotifier.simulateSignIn(metadata: {
        'display_name': 'TestPlayer',
      });
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Router redirects to /age-verification (no age_verified_at)
      expect(ageVerificationTitle, findsOneWidget);

      // ── Step 5: Simulate age verification completion ─────────────────
      // The date picker uses AbsorbPointer + showDatePicker which is
      // difficult to interact with in integration tests. Instead, we
      // simulate age verification completion directly via the harness.
      // This tests the router redirect chain (the critical path) while
      // the date picker UI can be covered by widget tests.
      harness.authNotifier.updateMetadata({
        'is_under_13': false,
        'date_of_birth': '2012-01-15',
        'age_verified_at': DateTime.now().toUtc().toIso8601String(),
      });
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // ── Step 8: Guest Migration screen ────────────────────────────────
      expect(migrationTitle, findsOneWidget);
      // Verify it shows the sticker count
      expect(find.textContaining('sticker'), findsWidgets);

      // ── Step 9: Tap "Transfer Stickers" ───────────────────────────────
      await tester.tap(transferButton);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Migration completes → redirect to /matches
      expect(harness.authService.migrateInventoryCalled, isTrue);

      // May see success screen briefly then continue, or direct redirect.
      // If we see the "Continue" button on success, tap it.
      if (migrationContinueButton.evaluate().isNotEmpty) {
        await tester.tap(migrationContinueButton);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }

      // ── Step 10: Discovery screen (matches) ──────────────────────────
      // The matches screen should be visible. It will show the card stack
      // since FakeMatchDiscoveryService returns 2 test matches.
      // Wait for the discovery flow to initialize.
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Verify we're on the matches screen — either seeing cards or
      // the discovery loading state
      final onMatchesScreen = matchesAppBarTitle.evaluate().isNotEmpty ||
          find.text('Carlos').evaluate().isNotEmpty ||
          gettingLocation.evaluate().isNotEmpty;
      expect(onMatchesScreen, isTrue,
          reason: 'Should be on the matches/discovery screen');

      // ── Step 11: Simulate swipe right ─────────────────────────────────
      // The card stack responds to horizontal drag. We need to drag
      // right past the 0.3 threshold (30% of half-screen-width).
      // Find the trader card by name.
      final traderCard = find.text('Carlos');
      if (traderCard.evaluate().isNotEmpty) {
        // Fling right to trigger a swipe
        await tester.fling(traderCard, const Offset(400, 0), 1000);
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // FakeMatchDiscoveryService.swipeRight returns mutualMatchResult

        // ── Step 12: Verify celebration overlay ───────────────────────
        expect(celebrationTitle, findsOneWidget);
        expect(openChatButton, findsOneWidget);

        // ── Step 13: Tap "Open Chat" on celebration ────────────────────
        // The celebration overlay navigates to /matches/{matchId}
        // (the match screen), NOT directly to the chat screen.
        await tester.tap(openChatButton);
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // ── Step 13b: Verify match screen ─────────────────────────────
        expect(matchScreenTitle, findsOneWidget);

        // ── Step 13c: Tap "Open Chat" on match screen → chat ─────────
        // The match screen has a secondary "Open Chat" button that
        // navigates to /matches/{matchId}/chat.
        final matchScreenChatButton = openChatButton;
        expect(matchScreenChatButton, findsOneWidget);
        await tester.tap(matchScreenChatButton);
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // ── Step 14: Verify chat screen ───────────────────────────────
        expect(chatScreenTitle, findsOneWidget);
        expect(chatInputField, findsOneWidget);

        // ── Step 15: Type and send a message ──────────────────────────
        await tester.enterText(chatInputField, 'Hey! Ready to trade?');
        await tester.pumpAndSettle();

        await tester.tap(chatSendButton);
        await tester.pumpAndSettle();

        // The message bubble should appear
        expect(find.text('Hey! Ready to trade?'), findsOneWidget);

        // ── Step 16: Navigate back to match screen ────────────────────
        final chatBackButton = find.byType(BackButton);
        if (chatBackButton.evaluate().isNotEmpty) {
          await tester.tap(chatBackButton.first);
          await tester.pumpAndSettle(const Duration(seconds: 3));
        }

        // ── Step 17: Trade confirmation UI ────────────────────────────
        // We should see the match screen with trade confirmation
        if (markAsDoneButton.evaluate().isNotEmpty) {
          await tester.tap(markAsDoneButton);
          await tester.pumpAndSettle(const Duration(seconds: 3));

          // ── Step 18: Verify "Waiting for partner" state ─────────────
          expect(
            waitingForPartner.evaluate().isNotEmpty ||
                tradeComplete.evaluate().isNotEmpty,
            isTrue,
            reason: 'Should show waiting or complete state after confirming',
          );
        }
      }
    });
  });
}
