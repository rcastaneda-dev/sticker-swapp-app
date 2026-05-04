import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/core/router/app_router.dart';
import 'package:flutter_app/core/services/push_notification_service.dart';
import 'package:flutter_app/core/providers/deep_link_providers.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/matching/data/providers/match_notification_providers.dart';

/// Singleton provider for [PushNotificationService].
///
/// Overridden in main() with the initialized instance.
/// In tests, override with a service using injectable callbacks.
final pushNotificationServiceProvider = Provider<PushNotificationService>(
  (ref) => PushNotificationService(
    appId: const String.fromEnvironment('ONESIGNAL_APP_ID'),
  ),
);

/// Manages OneSignal user association lifecycle and notification handlers.
///
/// Watches auth state + under-13 flag:
/// - Authenticated + 13+ → login(userId)
/// - Unauthenticated or under-13 → logout()
///
/// Wires notification tap → GoRouter navigation and
/// foreground suppression → in-app matchNotificationProvider.
final pushNotificationLifecycleProvider = Provider<void>((ref) {
  final pushService = ref.read(pushNotificationServiceProvider);
  final authState = ref.watch(authStateProvider);
  final isUnder13 = ref.watch(isUnder13Provider);

  // Wire tap handler → navigate to match screen (or store for post-onboarding)
  pushService.onNotificationOpened = (matchId) {
    final destination = '/matches/$matchId';

    // Store the destination in case user needs onboarding first
    ref.read(deepLinkProvider.notifier).setPendingDestination(destination);

    // Try to navigate (router will redirect to onboarding if needed)
    final router = ref.read(routerProvider);
    router.push(destination);
  };

  // Wire foreground handler → feed into in-app notification system
  pushService.onForegroundNotification = (matchId) {
    if (matchId != null) {
      ref.read(matchNotificationProvider.notifier).addMatch(
            UnviewedMatch(matchId: matchId, displayName: 'a trader'),
          );
      return true; // suppress OS notification
    }
    return false;
  };

  // Manage OneSignal user association based on auth + age
  if (authState is AuthAuthenticated && isUnder13 == false) {
    pushService.loginUser(authState.user.id);
  } else {
    pushService.logoutUser();
  }

  // Drain any buffered cold-start notification
  pushService.processPendingNotification();
});
