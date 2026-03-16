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

/// Whether the current user has parental consent.
/// Returns null if unauthenticated.
final parentalConsentProvider = Provider<bool?>((ref) {
  final authState = ref.watch(authStateProvider);
  if (authState is AuthAuthenticated) {
    return authState.user.userMetadata?['parental_consent_at'] != null;
  }
  return null;
});

/// Whether the current user needs parental consent to proceed.
/// True only if: authenticated + age-verified + under-13 + no consent.
final needsParentalConsentProvider = Provider<bool>((ref) {
  final isUnder13 = ref.watch(isUnder13Provider);
  final isAgeVerified = ref.watch(ageVerifiedProvider);
  final hasConsent = ref.watch(parentalConsentProvider);

  return isUnder13 == true && isAgeVerified == true && hasConsent != true;
});

/// Polls for parental consent every 30 seconds.
/// When consent is detected, refreshes the session so the JWT reflects
/// the updated metadata, then stops polling.
final consentPollingProvider =
    StreamProvider.autoDispose<bool>((ref) async* {
  final authService = ref.watch(authServiceProvider);

  // Initial check
  final initial = await authService.checkParentalConsent();
  yield initial;
  if (initial) return;

  // Poll every 30 seconds
  await for (final _ in Stream.periodic(const Duration(seconds: 30))) {
    final hasConsent = await authService.checkParentalConsent();
    yield hasConsent;

    if (hasConsent) {
      // Refresh session so authStateProvider re-emits with updated metadata
      await Supabase.instance.client.auth.refreshSession();
      return;
    }
  }
});
