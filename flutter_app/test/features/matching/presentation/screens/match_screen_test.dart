import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/matching/data/providers/match_notification_providers.dart';
import 'package:flutter_app/features/matching/data/providers/trade_confirmation_providers.dart';
import 'package:flutter_app/features/matching/presentation/screens/match_screen.dart';
import 'package:flutter_app/shared/shared.dart';

// ── Helpers ───────────────────────────────────────────────────────────────

AuthAuthenticated _authenticated({Map<String, dynamic>? metadata}) {
  final user = User(
    id: 'test-user-id',
    appMetadata: {},
    userMetadata: metadata ?? {},
    aud: 'authenticated',
    createdAt: DateTime.now().toIso8601String(),
  );
  return AuthAuthenticated(
    user: user,
    session: Session(
      accessToken: 'fake-access-token',
      tokenType: 'bearer',
      user: user,
    ),
  );
}

class _StubAuthStateNotifier extends AuthStateNotifier {
  final AppAuthState _initial;
  _StubAuthStateNotifier(this._initial);

  @override
  AppAuthState build() => _initial;
}

class _StubMatchNotificationNotifier extends MatchNotificationNotifier {
  final List<UnviewedMatch> _initial;
  _StubMatchNotificationNotifier(this._initial);

  @override
  List<UnviewedMatch> build() => _initial;
}

class _StubTradeConfirmationNotifier extends TradeConfirmationNotifier {
  final TradeConfirmationState _initial;
  bool initializeCalled = false;
  bool confirmCalled = false;

  _StubTradeConfirmationNotifier(super.matchId, this._initial);

  @override
  TradeConfirmationState build() => _initial;

  @override
  Future<void> initialize() async {
    initializeCalled = true;
  }

  @override
  Future<void> confirm() async {
    confirmCalled = true;
  }
}

Widget _buildSubject({
  Map<String, dynamic>? metadata,
  List<UnviewedMatch>? unviewedMatches,
  TradeConfirmationState? confirmationState,
}) {
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(
        () => _StubAuthStateNotifier(_authenticated(metadata: metadata)),
      ),
      if (unviewedMatches != null)
        matchNotificationProvider.overrideWith(
          () => _StubMatchNotificationNotifier(unviewedMatches),
        ),
      tradeConfirmationProvider.overrideWith2(
        (matchId) => _StubTradeConfirmationNotifier(
          matchId,
          confirmationState ??
              const TradeConfirmationState(
                status: ConfirmationStatus.idle,
              ),
        ),
      ),
    ],
    child: MaterialApp(
      theme: SwappTheme.light,
      home: const MatchScreen(matchId: 'test-match-123'),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('MatchScreen', () {
    testWidgets('shows restricted empty state for under-13 users',
        (tester) async {
      await tester.pumpWidget(_buildSubject(metadata: {
        'is_under_13': true,
        'age_verified_at': '2024-01-01T00:00:00Z',
        'parental_consent_at': '2024-06-01T00:00:00Z',
      }));

      expect(find.text('Trading Not Available'), findsOneWidget);
      expect(find.text('Open Chat'), findsNothing);
      expect(find.text('Mark as Done'), findsNothing);
    });

    testWidgets('shows Mark as Done button when neither confirmed',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': false,
          'age_verified_at': '2024-01-01T00:00:00Z',
        },
        confirmationState: const TradeConfirmationState(
          status: ConfirmationStatus.idle,
          callerConfirmed: false,
          otherConfirmed: false,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Mark as Done'), findsOneWidget);
      expect(find.text('Trade Confirmation'), findsOneWidget);
      expect(find.text('Open Chat'), findsOneWidget);
    });

    testWidgets('shows loading spinner during initial load', (tester) async {
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': false,
          'age_verified_at': '2024-01-01T00:00:00Z',
        },
        confirmationState: const TradeConfirmationState(
          status: ConfirmationStatus.loading,
        ),
      ));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Mark as Done'), findsNothing);
    });

    testWidgets('shows loading spinner during confirm', (tester) async {
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': false,
          'age_verified_at': '2024-01-01T00:00:00Z',
        },
        confirmationState: const TradeConfirmationState(
          status: ConfirmationStatus.confirming,
          callerConfirmed: false,
          otherConfirmed: false,
        ),
      ));

      // SwappButton with isLoading shows a CircularProgressIndicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows waiting state when caller confirmed but not other',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': false,
          'age_verified_at': '2024-01-01T00:00:00Z',
        },
        confirmationState: const TradeConfirmationState(
          status: ConfirmationStatus.waitingForOther,
          callerConfirmed: true,
          otherConfirmed: false,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Waiting for partner...'), findsOneWidget);
      expect(find.text('Mark as Done'), findsNothing);
    });

    testWidgets('shows Trade Complete when both confirmed', (tester) async {
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': false,
          'age_verified_at': '2024-01-01T00:00:00Z',
        },
        confirmationState: const TradeConfirmationState(
          status: ConfirmationStatus.completed,
          callerConfirmed: true,
          otherConfirmed: true,
        ),
      ));
      // Pump past elastic animation
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('Trade Complete!'), findsOneWidget);
      expect(find.text('Mark as Done'), findsNothing);

      // Clean up animation controller
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('shows Open Chat button in all non-error states',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': false,
          'age_verified_at': '2024-01-01T00:00:00Z',
        },
        confirmationState: const TradeConfirmationState(
          status: ConfirmationStatus.waitingForOther,
          callerConfirmed: true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Open Chat'), findsOneWidget);
    });

    testWidgets('shows error state with retry button', (tester) async {
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': false,
          'age_verified_at': '2024-01-01T00:00:00Z',
        },
        confirmationState: const TradeConfirmationState(
          status: ConfirmationStatus.error,
          errorMessage: 'Network error',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Network error'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('marks match as viewed on build', (tester) async {
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': false,
          'age_verified_at': '2024-01-01T00:00:00Z',
        },
        unviewedMatches: const [
          UnviewedMatch(matchId: 'test-match-123', displayName: 'Carlos'),
          UnviewedMatch(matchId: 'other-match', displayName: 'Diego'),
        ],
      ));
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(MatchScreen));
      final container = ProviderScope.containerOf(element);
      final remaining = container.read(matchNotificationProvider);
      expect(remaining.length, 1);
      expect(remaining.first.matchId, 'other-match');
    });

    testWidgets('shows confirmation chips for both users', (tester) async {
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': false,
          'age_verified_at': '2024-01-01T00:00:00Z',
        },
        confirmationState: const TradeConfirmationState(
          status: ConfirmationStatus.idle,
          callerConfirmed: false,
          otherConfirmed: false,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('You'), findsOneWidget);
      expect(find.text('Partner'), findsOneWidget);
    });
  });
}
