import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/stickers/data/providers/guest_inventory_providers.dart';
import 'package:flutter_app/features/stickers/data/providers/user_inventory_providers.dart';
import 'package:flutter_app/features/stickers/data/providers/effective_inventory_providers.dart';
import 'package:flutter_app/features/stickers/data/services/user_inventory_service.dart';
import 'package:flutter_app/features/stickers/data/services/guest_storage_service.dart';

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
  _FakeUserInventoryService(this._owned) : super(client: null);

  @override
  Future<Set<int>> fetchOwnedStickerIds() async => Set.from(_owned);

  @override
  Future<void> toggleSticker(int stickerId) async {}

  @override
  Future<String> createWishlistShare() async => 'token';
}

class _FakeGuestStorageService implements GuestStorageService {
  final Set<int> _owned;
  _FakeGuestStorageService(this._owned);

  @override
  Future<Set<int>> loadOwnedStickers() async => Set.from(_owned);

  @override
  Future<void> saveOwnedStickers(Set<int> ids) async {}

  @override
  Future<void> init() async {}

  @override
  Future<void> clearInventory() async {}

  @override
  Future<String> getOrCreateDeviceUuid() async => 'test-uuid';
}

// ── Tests ───────────────────────────────────────────────────────────

void main() {
  group('effectiveInventoryProvider', () {
    test('returns guest inventory when unauthenticated', () async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            () => _StubAuthStateNotifier(const AuthUnauthenticated()),
          ),
          guestStorageServiceProvider.overrideWithValue(
            _FakeGuestStorageService({10, 20, 30}),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Wait for guest inventory to load
      await container.read(guestInventoryProvider.future);

      final result = container.read(effectiveInventoryProvider);
      expect(result.value, {10, 20, 30});
    });

    test('returns user inventory when authenticated', () async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            () => _StubAuthStateNotifier(_authenticated()),
          ),
          userInventoryServiceProvider.overrideWithValue(
            _FakeUserInventoryService({100, 200}),
          ),
          // Guest storage should NOT be used
          guestStorageServiceProvider.overrideWithValue(
            _FakeGuestStorageService({999}),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Wait for user inventory to load
      await container.read(userInventoryProvider.future);

      final result = container.read(effectiveInventoryProvider);
      expect(result.value, {100, 200});
      expect(result.value, isNot(contains(999)));
    });
  });
}
