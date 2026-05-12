import 'package:flutter_app/features/stickers/data/services/guest_storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory guest storage for integration tests.
///
/// Avoids `flutter_secure_storage` platform channel calls.
class FakeGuestStorageService extends GuestStorageService {
  Set<int> _ownedStickers;
  final String _deviceUuid = 'fake-device-uuid-1234';
  bool clearInventoryCalled = false;

  FakeGuestStorageService({Set<int>? initialInventory})
      : _ownedStickers = initialInventory ?? {},
        super(
          secureStorage: const FlutterSecureStorage(),
          prefs: SharedPreferencesAsync(),
        );

  @override
  Future<void> init() async {
    // No-op — skip platform channel initialization
  }

  @override
  Future<Set<int>> loadOwnedStickers() async => Set.from(_ownedStickers);

  @override
  Future<void> saveOwnedStickers(Set<int> stickerIds) async {
    _ownedStickers = Set.from(stickerIds);
  }

  @override
  Future<void> clearInventory() async {
    clearInventoryCalled = true;
    _ownedStickers = {};
  }

  @override
  Future<String> getOrCreateDeviceUuid() async => _deviceUuid;
}
