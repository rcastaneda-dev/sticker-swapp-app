import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
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

Widget _buildSubject({Map<String, dynamic>? metadata}) {
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(
        () => _StubAuthStateNotifier(_authenticated(metadata: metadata)),
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
    });

    testWidgets('shows normal content for 13+ users', (tester) async {
      await tester.pumpWidget(_buildSubject(metadata: {
        'is_under_13': false,
        'age_verified_at': '2024-01-01T00:00:00Z',
      }));

      expect(find.text('Open Chat'), findsOneWidget);
      expect(find.text('Trading Not Available'), findsNothing);
    });
  });
}
