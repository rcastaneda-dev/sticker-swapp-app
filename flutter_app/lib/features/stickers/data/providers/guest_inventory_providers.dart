import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/guest_storage_service.dart';

/// Singleton provider for [GuestStorageService].
///
/// Call `ref.read(guestStorageServiceProvider).init()` once at startup
/// before accessing inventory data.
final guestStorageServiceProvider = Provider<GuestStorageService>((ref) {
  return GuestStorageService();
});

/// Manages the set of sticker IDs the guest has marked as "owned."
///
/// Loads from encrypted storage on first access, then writes through
/// on every toggle. The UI watches this provider to render check state.
class GuestInventoryNotifier extends AsyncNotifier<Set<int>> {
  @override
  Future<Set<int>> build() async {
    final service = ref.watch(guestStorageServiceProvider);
    return service.loadOwnedStickers();
  }

  /// Toggle a sticker between owned and not-owned.
  Future<void> toggleSticker(int stickerId) async {
    final current = state.value ?? {};
    final updated = Set<int>.from(current);
    if (updated.contains(stickerId)) {
      updated.remove(stickerId);
    } else {
      updated.add(stickerId);
    }
    state = AsyncData(updated);
    await ref.read(guestStorageServiceProvider).saveOwnedStickers(updated);
  }

  /// Check if a specific sticker is owned.
  bool isOwned(int stickerId) {
    return state.value?.contains(stickerId) ?? false;
  }

  /// Number of owned stickers.
  int get ownedCount => state.value?.length ?? 0;
}

final guestInventoryProvider =
    AsyncNotifierProvider<GuestInventoryNotifier, Set<int>>(
  GuestInventoryNotifier.new,
);
