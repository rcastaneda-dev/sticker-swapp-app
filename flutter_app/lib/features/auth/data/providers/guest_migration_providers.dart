import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/stickers/data/providers/guest_inventory_providers.dart';

/// Tracks whether the guest-to-member migration has been completed or skipped
/// during the current session. The router watches this to decide whether to
/// show the `/guest-migration` screen.
class GuestMigrationCompleteNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void complete() => state = true;
}

final guestMigrationCompleteProvider =
    NotifierProvider<GuestMigrationCompleteNotifier, bool>(
  GuestMigrationCompleteNotifier.new,
);

/// Whether the current user needs to go through the guest migration flow.
///
/// True when: authenticated + age-verified + local guest inventory is
/// non-empty + migration not yet completed/skipped this session.
final needsGuestMigrationProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  final isAgeVerified = ref.watch(ageVerifiedProvider) ?? false;
  final migrationComplete = ref.watch(guestMigrationCompleteProvider);

  if (authState is! AuthAuthenticated || !isAgeVerified || migrationComplete) {
    return false;
  }

  final inventoryAsync = ref.watch(guestInventoryProvider);
  final inventory = inventoryAsync.value ?? {};
  return inventory.isNotEmpty;
});
