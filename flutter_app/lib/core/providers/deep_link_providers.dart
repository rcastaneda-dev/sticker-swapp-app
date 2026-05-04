import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stores a pending deep link destination (e.g., from push notification tap).
///
/// When a notification tap tries to navigate to a protected route but the user
/// needs to complete onboarding first, the destination is stored here and
/// consumed after onboarding completes.
class DeepLinkNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Store a pending destination (e.g., '/matches/abc123').
  void setPendingDestination(String destination) {
    state = destination;
  }

  /// Consume and clear the pending destination.
  String? consume() {
    final destination = state;
    state = null;
    return destination;
  }

  /// Clear without consuming (e.g., if user manually navigates elsewhere).
  void clear() {
    state = null;
  }
}

final deepLinkProvider = NotifierProvider<DeepLinkNotifier, String?>(
  DeepLinkNotifier.new,
);
