import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sticker.dart';
import 'collection_progress_providers.dart';
import 'effective_inventory_providers.dart';
import 'user_inventory_providers.dart';

/// Stickers the user does NOT own — their wishlist (needed stickers).
///
/// Derives from [allStickersProvider] minus [effectiveInventoryProvider].
final wishlistProvider = Provider<List<Sticker>>((ref) {
  final allStickers = ref.watch(allStickersProvider).value;
  final ownedIds = ref.watch(effectiveInventoryProvider).value;

  if (allStickers == null || ownedIds == null) return [];

  return allStickers.where((s) => !ownedIds.contains(s.id)).toList();
});

/// Count of stickers the user still needs.
final wishlistCountProvider = Provider<int>((ref) {
  return ref.watch(wishlistProvider).length;
});

/// State for the share-link generation flow.
enum WishlistShareStatus { idle, loading, success, error }

class WishlistShareState {
  final WishlistShareStatus status;
  final String? shareUrl;
  final String? errorMessage;

  const WishlistShareState({
    this.status = WishlistShareStatus.idle,
    this.shareUrl,
    this.errorMessage,
  });
}

/// Manages the share-link generation lifecycle (idle → loading → success/error).
class WishlistShareNotifier extends Notifier<WishlistShareState> {
  @override
  WishlistShareState build() => const WishlistShareState();

  Future<void> generateShareLink() async {
    state = const WishlistShareState(status: WishlistShareStatus.loading);
    try {
      final service = ref.read(userInventoryServiceProvider);
      final token = await service.createWishlistShare();
      const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
      final url = '$supabaseUrl/functions/v1/share-wishlist?token=$token';
      state = WishlistShareState(
        status: WishlistShareStatus.success,
        shareUrl: url,
      );
    } catch (e) {
      state = WishlistShareState(
        status: WishlistShareStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  void reset() {
    state = const WishlistShareState();
  }
}

final wishlistShareProvider =
    NotifierProvider<WishlistShareNotifier, WishlistShareState>(
  WishlistShareNotifier.new,
);
