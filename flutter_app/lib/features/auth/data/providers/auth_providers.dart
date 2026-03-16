import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:flutter_app/features/auth/data/services/auth_service.dart';

/// The current authentication state.
sealed class AppAuthState {
  const AppAuthState();
}

class AuthAuthenticated extends AppAuthState {
  final User user;
  final Session session;
  const AuthAuthenticated({required this.user, required this.session});
}

class AuthUnauthenticated extends AppAuthState {
  const AuthUnauthenticated();
}

/// Provider for the AuthService singleton.
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// Provider that listens to Supabase auth state changes and exposes
/// a typed [AppAuthState].
class AuthStateNotifier extends Notifier<AppAuthState> {
  StreamSubscription? _subscription;

  @override
  AppAuthState build() {
    final session = Supabase.instance.client.auth.currentSession;
    final user = Supabase.instance.client.auth.currentUser;

    _subscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        final session = data.session;
        final event = data.event;

        if (session != null && event != AuthChangeEvent.signedOut) {
          state = AuthAuthenticated(
            user: session.user,
            session: session,
          );
        } else {
          state = const AuthUnauthenticated();
        }
      },
    );

    ref.onDispose(() {
      _subscription?.cancel();
    });

    if (session != null && user != null) {
      return AuthAuthenticated(user: user, session: session);
    }
    return const AuthUnauthenticated();
  }
}

final authStateProvider =
    NotifierProvider<AuthStateNotifier, AppAuthState>(AuthStateNotifier.new);

/// Convenience provider: is the current user under 13?
final isUnder13Provider = Provider<bool?>((ref) {
  final authState = ref.watch(authStateProvider);
  if (authState is AuthAuthenticated) {
    return authState.user.userMetadata?['is_under_13'] as bool?;
  }
  return null;
});

/// Whether the current user has completed age verification.
/// Returns null if unauthenticated, true/false if authenticated.
final ageVerifiedProvider = Provider<bool?>((ref) {
  final authState = ref.watch(authStateProvider);
  if (authState is AuthAuthenticated) {
    return authState.user.userMetadata?['age_verified_at'] != null;
  }
  return null;
});

/// Convenience provider: current user ID or null.
final currentUserIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authStateProvider);
  if (authState is AuthAuthenticated) {
    return authState.user.id;
  }
  return null;
});
