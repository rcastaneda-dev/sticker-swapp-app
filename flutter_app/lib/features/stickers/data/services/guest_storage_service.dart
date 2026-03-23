import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Encrypted local storage for guest sticker inventory.
///
/// Uses [FlutterSecureStorage] (AES-256-GCM on native, localStorage on web)
/// to persist which stickers a guest user has checked/unchecked.
///
/// A first-launch flag (via [SharedPreferences]) ensures that Keychain data
/// from a previous iOS install is wiped on first launch — preventing stale
/// state from surviving uninstall/reinstall.
class GuestStorageService {
  static const _inventoryKey = 'guest_owned_stickers';
  static const _firstLaunchKey = 'guest_storage_initialized';

  final FlutterSecureStorage _secure;
  final SharedPreferencesAsync _prefs;

  GuestStorageService({
    FlutterSecureStorage? secureStorage,
    SharedPreferencesAsync? prefs,
  })  : _secure = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            ),
        _prefs = prefs ?? SharedPreferencesAsync();

  /// Must be called once at app startup (before reading inventory).
  ///
  /// On first launch after a fresh install, clears any stale Keychain
  /// entries that survived uninstall on iOS.
  Future<void> init() async {
    final hasLaunched = await _prefs.getBool(_firstLaunchKey) ?? false;
    if (!hasLaunched) {
      await _secure.deleteAll();
      await _prefs.setBool(_firstLaunchKey, true);
    }
  }

  /// Load the set of owned sticker IDs from encrypted storage.
  Future<Set<int>> loadOwnedStickers() async {
    final raw = await _secure.read(key: _inventoryKey);
    if (raw == null || raw.isEmpty) return {};
    final list = jsonDecode(raw) as List;
    return list.cast<int>().toSet();
  }

  /// Persist the set of owned sticker IDs to encrypted storage.
  Future<void> saveOwnedStickers(Set<int> stickerIds) async {
    final json = jsonEncode(stickerIds.toList());
    await _secure.write(key: _inventoryKey, value: json);
  }

  /// Remove all guest inventory data.
  Future<void> clearInventory() async {
    await _secure.delete(key: _inventoryKey);
  }
}
