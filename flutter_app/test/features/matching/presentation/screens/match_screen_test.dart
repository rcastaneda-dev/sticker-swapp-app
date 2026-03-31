import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/matching/data/providers/match_notification_providers.dart';
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

Widget _buildSubject({
  Map<String, dynamic>? metadata,
  List<UnviewedMatch>? unviewedMatches,
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
    ],
    child: MaterialApp(
      theme: SwappTheme.light,
      home: const MatchScreen(matchId: 'test-match-123'),
    ),
  );
}

class _StubMatchNotificationNotifier extends MatchNotificationNotifier {
  final List<UnviewedMatch> _initial;
  _StubMatchNotificationNotifier(this._initial);

  @override
  List<UnviewedMatch> build() => _initial;
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
    });

    testWidgets('shows normal content for 13+ users', (tester) async {
      await tester.pumpWidget(_buildSubject(metadata: {
        'is_under_13': false,
        'age_verified_at': '2024-01-01T00:00:00Z',
      }));

      expect(find.text('Open Chat'), findsOneWidget);
      expect(find.text('Trading Not Available'), findsNothing);
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

      // The match_screen calls markViewed via addPostFrameCallback,
      // so after pumpAndSettle the 'test-match-123' entry should be removed.
      // We verify by checking the notification provider state through
      // the ProviderScope — find the container and read the provider.
      final element = tester.element(find.byType(MatchScreen));
      final container = ProviderScope.containerOf(element);
      final remaining = container.read(matchNotificationProvider);
      expect(remaining.length, 1);
      expect(remaining.first.matchId, 'other-match');
    });
  });
}
