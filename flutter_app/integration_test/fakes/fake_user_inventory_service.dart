import 'package:flutter_app/features/stickers/data/services/user_inventory_service.dart';

/// In-memory user inventory for integration tests.
class FakeUserInventoryService extends UserInventoryService {
  final Set<int> _owned;
  bool createWishlistShareCalled = false;

  FakeUserInventoryService({Set<int>? initialOwned})
      : _owned = initialOwned ?? {},
        super(client: null);

  @override
  Future<Set<int>> fetchOwnedStickerIds() async => Set.from(_owned);

  @override
  Future<void> toggleSticker(int stickerId) async {
    if (_owned.contains(stickerId)) {
      _owned.remove(stickerId);
    } else {
      _owned.add(stickerId);
    }
  }

  @override
  Future<Set<int>> fetchReservedStickerIds() async => {};

  @override
  Future<String> createWishlistShare() async {
    createWishlistShareCalled = true;
    return 'fake-share-token-abc123';
  }
}
