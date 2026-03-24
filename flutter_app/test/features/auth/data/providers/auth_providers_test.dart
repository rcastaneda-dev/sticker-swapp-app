import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';

// ── Helpers ───────────────────────────────────────────────────────────────

/// Creates a [ProviderContainer] with [authStateProvider] overridden to
/// return the given [state].
ProviderContainer _createContainer(AppAuthState state) {
  return ProviderContainer(
    overrides: [
      authStateProvider.overrideWith(() => _StubAuthStateNotifier(state)),
    ],
  );
}

/// Returns an [AuthAuthenticated] state with the given user metadata.
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

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('Auth Providers', () {
    // ── isUnder13Provider ──

    group('isUnder13Provider', () {
      test('returns null when unauthenticated', () {
        final container = _createContainer(const AuthUnauthenticated());
        addTearDown(container.dispose);

        expect(container.read(isUnder13Provider), isNull);
      });

      test('returns null when metadata has no is_under_13 field', () {
        final container = _createContainer(_authenticated());
        addTearDown(container.dispose);

        expect(container.read(isUnder13Provider), isNull);
      });

      test('returns true when user is under 13', () {
        final container = _createContainer(
          _authenticated(metadata: {'is_under_13': true}),
        );
        addTearDown(container.dispose);

        expect(container.read(isUnder13Provider), isTrue);
      });

      test('returns false when user is 13 or older', () {
        final container = _createContainer(
          _authenticated(metadata: {'is_under_13': false}),
        );
        addTearDown(container.dispose);

        expect(container.read(isUnder13Provider), isFalse);
      });
    });

    // ── ageVerifiedProvider ──

    group('ageVerifiedProvider', () {
      test('returns null when unauthenticated', () {
        final container = _createContainer(const AuthUnauthenticated());
        addTearDown(container.dispose);

        expect(container.read(ageVerifiedProvider), isNull);
      });

      test('returns false when age_verified_at is not set', () {
        final container = _createContainer(_authenticated());
        addTearDown(container.dispose);

        expect(container.read(ageVerifiedProvider), isFalse);
      });

      test('returns true when age_verified_at is set', () {
        final container = _createContainer(
          _authenticated(metadata: {
            'age_verified_at': '2024-01-01T00:00:00Z',
          }),
        );
        addTearDown(container.dispose);

        expect(container.read(ageVerifiedProvider), isTrue);
      });
    });

    // ── currentUserIdProvider ──

    group('currentUserIdProvider', () {
      test('returns null when unauthenticated', () {
        final container = _createContainer(const AuthUnauthenticated());
        addTearDown(container.dispose);

        expect(container.read(currentUserIdProvider), isNull);
      });

      test('returns user id when authenticated', () {
        final container = _createContainer(_authenticated());
        addTearDown(container.dispose);

        expect(container.read(currentUserIdProvider), 'test-user-id');
      });
    });

    // ── parentalConsentProvider ──

    group('parentalConsentProvider', () {
      test('returns null when unauthenticated', () {
        final container = _createContainer(const AuthUnauthenticated());
        addTearDown(container.dispose);

        expect(container.read(parentalConsentProvider), isNull);
      });

      test('returns false when parental_consent_at is not set', () {
        final container = _createContainer(_authenticated());
        addTearDown(container.dispose);

        // Authenticated but no parental_consent_at → returns false
        expect(container.read(parentalConsentProvider), isFalse);
      });

      test('returns true when parental_consent_at is set', () {
        final container = _createContainer(
          _authenticated(metadata: {
            'parental_consent_at': '2024-06-01T00:00:00Z',
          }),
        );
        addTearDown(container.dispose);

        expect(container.read(parentalConsentProvider), isTrue);
      });
    });

    // ── needsParentalConsentProvider ──

    group('needsParentalConsentProvider', () {
      test('returns false when unauthenticated', () {
        final container = _createContainer(const AuthUnauthenticated());
        addTearDown(container.dispose);

        expect(container.read(needsParentalConsentProvider), isFalse);
      });

      test('returns false when not age-verified', () {
        final container = _createContainer(
          _authenticated(metadata: {'is_under_13': true}),
        );
        addTearDown(container.dispose);

        // Under 13 but not age-verified → doesn't need consent yet
        expect(container.read(needsParentalConsentProvider), isFalse);
      });

      test('returns false when 13 or older', () {
        final container = _createContainer(
          _authenticated(metadata: {
            'is_under_13': false,
            'age_verified_at': '2024-01-01T00:00:00Z',
          }),
        );
        addTearDown(container.dispose);

        expect(container.read(needsParentalConsentProvider), isFalse);
      });

      test('returns true when under 13, age-verified, and no consent', () {
        final container = _createContainer(
          _authenticated(metadata: {
            'is_under_13': true,
            'age_verified_at': '2024-01-01T00:00:00Z',
          }),
        );
        addTearDown(container.dispose);

        expect(container.read(needsParentalConsentProvider), isTrue);
      });

      test('returns false when under 13, age-verified, and has consent', () {
        final container = _createContainer(
          _authenticated(metadata: {
            'is_under_13': true,
            'age_verified_at': '2024-01-01T00:00:00Z',
            'parental_consent_at': '2024-06-01T00:00:00Z',
          }),
        );
        addTearDown(container.dispose);

        expect(container.read(needsParentalConsentProvider), isFalse);
      });
    });
  });
}
