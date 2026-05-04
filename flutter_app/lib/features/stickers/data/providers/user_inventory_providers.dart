import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import '../services/user_inventory_service.dart';

/// Singleton provider for [UserInventoryService].
final userInventoryServiceProvider = Provider<UserInventoryService>((ref) {
  return UserInventoryService();
});

/// Manages the set of sticker IDs the authenticated user has marked as owned.
///
/// Loads from Supabase `user_inventory` on first access. Provides the same
/// `Set<int>` interface as [GuestInventoryNotifier] for seamless switching
/// via [effectiveInventoryProvider].
class UserInventoryNotifier extends AsyncNotifier<Set<int>> {
  @override
  Future<Set<int>> build() async {
    final service = ref.watch(userInventoryServiceProvider);
    return service.fetchOwnedStickerIds();
  }

  /// Toggle a sticker between owned and not-owned.
  ///
  /// Uses optimistic update: the UI reflects the change immediately,
  /// and reverts if the server call fails.
  Future<void> toggleSticker(int stickerId) async {
    final current = state.value ?? {};
    final updated = Set<int>.from(current);
    if (updated.contains(stickerId)) {
      updated.remove(stickerId);
    } else {
      updated.add(stickerId);
    }
    state = AsyncData(updated);

    try {
      await ref.read(userInventoryServiceProvider).toggleSticker(stickerId);
    } catch (e) {
      // Revert on failure
      state = AsyncData(current);
      rethrow;
    }
  }

  /// Check if a specific sticker is owned.
  bool isOwned(int stickerId) {
    return state.value?.contains(stickerId) ?? false;
  }

  /// Number of owned stickers.
  int get ownedCount => state.value?.length ?? 0;
}

final userInventoryProvider =
    AsyncNotifierProvider<UserInventoryNotifier, Set<int>>(
  UserInventoryNotifier.new,
);

/// Provides the set of sticker IDs currently reserved for active trades.
///
/// Returns an empty set for unauthenticated users.
/// Auto-invalidates every 60 seconds to pick up lock expiry.
final reservedStickersProvider = FutureProvider<Set<int>>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (authState is! AuthAuthenticated) return {};

  // Auto-invalidate every 60s to pick up lock expiry
  final timer = Timer(const Duration(seconds: 60), () {
    ref.invalidateSelf();
  });
  ref.onDispose(timer.cancel);

  final service = ref.watch(userInventoryServiceProvider);
  return service.fetchReservedStickerIds();
});
