import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

/// Mutable auth state notifier for integration tests.
///
/// Starts as [AuthUnauthenticated]. Tests call [simulateSignIn] to switch
/// state, which triggers GoRouter redirect re-evaluation.
class FakeAuthStateNotifier extends AuthStateNotifier {
  AppAuthState _current = const AuthUnauthenticated();

  @override
  AppAuthState build() => _current;

  /// Simulate a user signing in with the given metadata.
  ///
  /// The metadata map controls routing decisions:
  /// - `age_verified_at` (null = not verified)
  /// - `is_under_13` (bool)
  /// - `parental_consent_at` (null = no consent)
  /// - `display_name` (String)
  void simulateSignIn({
    String userId = 'test-user-id',
    Map<String, dynamic> metadata = const {},
  }) {
    final user = User(
      id: userId,
      appMetadata: {},
      userMetadata: metadata,
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
    );
    _current = AuthAuthenticated(
      user: user,
      session: Session(
        accessToken: 'fake-access-token',
        tokenType: 'bearer',
        user: user,
      ),
    );
    state = _current;
  }

  /// Update metadata in-place (e.g., after age verification).
  void updateMetadata(Map<String, dynamic> newMetadata) {
    if (_current is AuthAuthenticated) {
      final auth = _current as AuthAuthenticated;
      final merged = {...auth.user.userMetadata ?? {}, ...newMetadata};
      simulateSignIn(userId: auth.user.id, metadata: merged);
    }
  }

  /// Simulate sign-out.
  void simulateSignOut() {
    _current = const AuthUnauthenticated();
    state = _current;
  }
}
