import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'guest_inventory_providers.dart';
import 'user_inventory_providers.dart';

/// Provides the currently-active inventory as a `Set<int>` of owned sticker IDs.
///
/// - Unauthenticated (guest): watches [guestInventoryProvider]
/// - Authenticated: watches [userInventoryProvider]
///
/// All UI that shows owned/unowned state should watch this provider
/// instead of [guestInventoryProvider] directly.
final effectiveInventoryProvider = Provider<AsyncValue<Set<int>>>((ref) {
  final authState = ref.watch(authStateProvider);

  if (authState is AuthAuthenticated) {
    return ref.watch(userInventoryProvider);
  }
  return ref.watch(guestInventoryProvider);
});

/// Toggle a sticker in whichever inventory is active (guest or authenticated).
///
/// Delegates to the appropriate notifier based on auth state.
void toggleEffectiveSticker(WidgetRef ref, int stickerId) {
  final authState = ref.read(authStateProvider);
  if (authState is AuthAuthenticated) {
    ref.read(userInventoryProvider.notifier).toggleSticker(stickerId);
  } else {
    ref.read(guestInventoryProvider.notifier).toggleSticker(stickerId);
  }
}
