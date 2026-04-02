import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/stickers/data/models/sticker.dart';
import 'package:flutter_app/features/stickers/data/providers/collection_progress_providers.dart';
import 'package:flutter_app/features/stickers/data/providers/user_inventory_providers.dart';
import 'package:flutter_app/features/stickers/data/providers/wishlist_providers.dart';
import 'package:flutter_app/features/stickers/data/services/user_inventory_service.dart';

// ── Helpers ──────────────────────────────────────────────────────────

class _StubAuthStateNotifier extends AuthStateNotifier {
  final AppAuthState _initial;
  _StubAuthStateNotifier(this._initial);

  @override
  AppAuthState build() => _initial;
}

AuthAuthenticated _authenticated() {
  final user = User(
    id: 'test-user-id',
    appMetadata: {},
    userMetadata: {'is_under_13': true, 'age_verified_at': '2024-01-01'},
    aud: 'authenticated',
    createdAt: DateTime.now().toIso8601String(),
  );
  return AuthAuthenticated(
    user: user,
    session: Session(
      accessToken: 'fake-token',
      tokenType: 'bearer',
      user: user,
    ),
  );
}

class _FakeUserInventoryService extends UserInventoryService {
  final Set<int> _owned;
  bool shouldThrow;
  _FakeUserInventoryService(this._owned, {this.shouldThrow = false})
      : super(client: null);

  @override
  Future<Set<int>> fetchOwnedStickerIds() async => Set.from(_owned);

  @override
  Future<void> toggleSticker(int stickerId) async {}

  @override
  Future<String> createWishlistShare() async {
    if (shouldThrow) throw Exception('share failed');
    return 'test-token-abc';
  }
}

List<Sticker> _testStickers() => [
      const Sticker(
          id: 1, stickerNumber: 1, title: 'S1', team: 'Argentina', page: 1, type: 'player'),
      const Sticker(
          id: 2, stickerNumber: 2, title: 'S2', team: 'Argentina', page: 1, type: 'player'),
      const Sticker(
          id: 3, stickerNumber: 3, title: 'S3', team: 'Brazil', page: 2, type: 'player'),
      const Sticker(
          id: 4, stickerNumber: 4, title: 'S4', team: 'Brazil', page: 2, type: 'player'),
      const Sticker(
          id: 5, stickerNumber: 5, title: 'S5', page: 3, type: 'stadium'),
    ];

// ── Tests ───────────────────────────────────────────────────────────

void main() {
  group('wishlistProvider', () {
    ProviderContainer createContainer({Set<int> owned = const {}}) {
      return ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            () => _StubAuthStateNotifier(_authenticated()),
          ),
          userInventoryServiceProvider.overrideWithValue(
            _FakeUserInventoryService(owned),
          ),
          allStickersProvider.overrideWith(
            (ref) => Future.value(_testStickers()),
          ),
        ],
      );
    }

    test('returns all stickers when none owned', () async {
      final container = createContainer(owned: {});
      addTearDown(container.dispose);

      await container.read(userInventoryProvider.future);
      await container.read(allStickersProvider.future);

      final wishlist = container.read(wishlistProvider);
      expect(wishlist, hasLength(5));
    });

    test('returns empty list when all owned', () async {
      final container = createContainer(owned: {1, 2, 3, 4, 5});
      addTearDown(container.dispose);

      await container.read(userInventoryProvider.future);
      await container.read(allStickersProvider.future);

      final wishlist = container.read(wishlistProvider);
      expect(wishlist, isEmpty);
    });

    test('returns correct subset of unowned stickers', () async {
      final container = createContainer(owned: {1, 3});
      addTearDown(container.dispose);

      await container.read(userInventoryProvider.future);
      await container.read(allStickersProvider.future);

      final wishlist = container.read(wishlistProvider);
      expect(wishlist, hasLength(3));
      expect(wishlist.map((s) => s.id), containsAll([2, 4, 5]));
      expect(wishlist.map((s) => s.id), isNot(contains(1)));
      expect(wishlist.map((s) => s.id), isNot(contains(3)));
    });
  });

  group('wishlistCountProvider', () {
    test('returns count of needed stickers', () async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            () => _StubAuthStateNotifier(_authenticated()),
          ),
          userInventoryServiceProvider.overrideWithValue(
            _FakeUserInventoryService({1, 2}),
          ),
          allStickersProvider.overrideWith(
            (ref) => Future.value(_testStickers()),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(userInventoryProvider.future);
      await container.read(allStickersProvider.future);

      expect(container.read(wishlistCountProvider), 3);
    });
  });

  group('WishlistShareNotifier', () {
    test('initial state is idle', () {
      final container = ProviderContainer(
        overrides: [
          userInventoryServiceProvider.overrideWithValue(
            _FakeUserInventoryService({}),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(wishlistShareProvider);
      expect(state.status, WishlistShareStatus.idle);
      expect(state.shareUrl, isNull);
    });

    test('generateShareLink transitions to success', () async {
      final container = ProviderContainer(
        overrides: [
          userInventoryServiceProvider.overrideWithValue(
            _FakeUserInventoryService({}),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(wishlistShareProvider.notifier)
          .generateShareLink();

      final state = container.read(wishlistShareProvider);
      expect(state.status, WishlistShareStatus.success);
      expect(state.shareUrl, contains('test-token-abc'));
      expect(state.shareUrl, contains('share-wishlist'));
    });

    test('generateShareLink transitions to error on failure', () async {
      final service = _FakeUserInventoryService({}, shouldThrow: true);
      final container = ProviderContainer(
        overrides: [
          userInventoryServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(wishlistShareProvider.notifier)
          .generateShareLink();

      final state = container.read(wishlistShareProvider);
      expect(state.status, WishlistShareStatus.error);
      expect(state.errorMessage, isNotNull);
    });

    test('reset returns to idle', () async {
      final container = ProviderContainer(
        overrides: [
          userInventoryServiceProvider.overrideWithValue(
            _FakeUserInventoryService({}),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(wishlistShareProvider.notifier)
          .generateShareLink();
      expect(
        container.read(wishlistShareProvider).status,
        WishlistShareStatus.success,
      );

      container.read(wishlistShareProvider.notifier).reset();
      expect(
        container.read(wishlistShareProvider).status,
        WishlistShareStatus.idle,
      );
    });
  });
}
