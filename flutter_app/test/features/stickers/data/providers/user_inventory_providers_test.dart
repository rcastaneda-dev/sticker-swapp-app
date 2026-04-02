import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/features/stickers/data/services/user_inventory_service.dart';
import 'package:flutter_app/features/stickers/data/providers/user_inventory_providers.dart';

// ── Fake Service ────────────────────────────────────────────────────

class _FakeUserInventoryService extends UserInventoryService {
  Set<int> ownedIds;
  bool shouldThrow;
  int toggleCallCount = 0;
  int? lastToggledId;
  String? lastShareToken;

  _FakeUserInventoryService({
    Set<int>? ownedIds,
  })  : ownedIds = ownedIds ?? {},
        shouldThrow = false,
        super(client: null);

  @override
  Future<Set<int>> fetchOwnedStickerIds() async {
    if (shouldThrow) throw Exception('fetch failed');
    return Set.from(ownedIds);
  }

  @override
  Future<void> toggleSticker(int stickerId) async {
    toggleCallCount++;
    lastToggledId = stickerId;
    if (shouldThrow) throw Exception('toggle failed');
    if (ownedIds.contains(stickerId)) {
      ownedIds = Set.from(ownedIds)..remove(stickerId);
    } else {
      ownedIds = Set.from(ownedIds)..add(stickerId);
    }
  }

  @override
  Future<String> createWishlistShare() async {
    if (shouldThrow) throw Exception('share failed');
    lastShareToken = 'test-token-abc123';
    return lastShareToken!;
  }
}

// ── Tests ───────────────────────────────────────────────────────────

void main() {
  group('UserInventoryNotifier', () {
    late ProviderContainer container;
    late _FakeUserInventoryService fakeService;

    ProviderContainer createContainer({Set<int>? ownedIds}) {
      fakeService = _FakeUserInventoryService(ownedIds: ownedIds);
      return ProviderContainer(
        overrides: [
          userInventoryServiceProvider.overrideWithValue(fakeService),
        ],
      );
    }

    tearDown(() => container.dispose());

    test('build() loads owned IDs from service', () async {
      container = createContainer(ownedIds: {1, 5, 10});

      // Wait for async build to complete.
      await container.read(userInventoryProvider.future);

      final state = container.read(userInventoryProvider);
      expect(state.value, {1, 5, 10});
    });

    test('build() returns empty set when no stickers owned', () async {
      container = createContainer(ownedIds: {});

      await container.read(userInventoryProvider.future);

      final state = container.read(userInventoryProvider);
      expect(state.value, isEmpty);
    });

    test('toggleSticker() adds sticker when not owned (optimistic)', () async {
      container = createContainer(ownedIds: {1, 2});

      await container.read(userInventoryProvider.future);
      await container.read(userInventoryProvider.notifier).toggleSticker(5);

      final state = container.read(userInventoryProvider);
      expect(state.value, contains(5));
      expect(state.value, containsAll([1, 2, 5]));
      expect(fakeService.lastToggledId, 5);
    });

    test('toggleSticker() removes sticker when owned (optimistic)', () async {
      container = createContainer(ownedIds: {1, 2, 3});

      await container.read(userInventoryProvider.future);
      await container.read(userInventoryProvider.notifier).toggleSticker(2);

      final state = container.read(userInventoryProvider);
      expect(state.value, isNot(contains(2)));
      expect(state.value, {1, 3});
    });

    test('toggleSticker() reverts on service failure', () async {
      container = createContainer(ownedIds: {1, 2});

      await container.read(userInventoryProvider.future);

      // Make the service throw on toggle
      fakeService.shouldThrow = true;

      expect(
        () =>
            container.read(userInventoryProvider.notifier).toggleSticker(5),
        throwsException,
      );

      // Wait for the async to settle
      await Future<void>.delayed(Duration.zero);

      // Should revert to original state
      final state = container.read(userInventoryProvider);
      expect(state.value, {1, 2});
      expect(state.value, isNot(contains(5)));
    });

    test('isOwned() returns correct value', () async {
      container = createContainer(ownedIds: {1, 5});

      await container.read(userInventoryProvider.future);

      final notifier = container.read(userInventoryProvider.notifier);
      expect(notifier.isOwned(1), isTrue);
      expect(notifier.isOwned(5), isTrue);
      expect(notifier.isOwned(3), isFalse);
    });

    test('ownedCount returns correct count', () async {
      container = createContainer(ownedIds: {1, 5, 10});

      await container.read(userInventoryProvider.future);

      final notifier = container.read(userInventoryProvider.notifier);
      expect(notifier.ownedCount, 3);
    });
  });
}
