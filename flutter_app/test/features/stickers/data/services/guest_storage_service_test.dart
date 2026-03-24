import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:flutter_app/features/stickers/data/services/guest_storage_service.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = {};
  int deleteAllCallCount = 0;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deleteAllCallCount++;
    _data.clear();
  }

  Map<String, String> get data => Map.unmodifiable(_data);
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('GuestStorageService', () {
    late _FakeSecureStorage secureStorage;
    late SharedPreferencesAsync prefs;
    late GuestStorageService service;

    setUp(() {
      // Set up in-memory platform for SharedPreferencesAsync.
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();

      secureStorage = _FakeSecureStorage();
      prefs = SharedPreferencesAsync();
      service = GuestStorageService(
        secureStorage: secureStorage,
        prefs: prefs,
      );
    });

    // ── init() — first-launch Keychain wipe ───────────────────────────

    group('init()', () {
      test('clears secure storage on first launch (fresh install)', () async {
        // Pre-populate secure storage with stale data (simulates iOS Keychain
        // surviving uninstall).
        await secureStorage.write(key: 'guest_owned_stickers', value: '[1,2]');
        await secureStorage.write(
            key: 'guest_device_uuid', value: 'old-uuid');

        await service.init();

        expect(secureStorage.deleteAllCallCount, 1);
        expect(secureStorage.data, isEmpty);
      });

      test('sets first-launch flag after clearing', () async {
        await service.init();

        final flag = await prefs.getBool('guest_storage_initialized');
        expect(flag, isTrue);
      });

      test('does NOT clear secure storage on subsequent launches', () async {
        // Simulate a previous launch that already set the flag.
        await prefs.setBool('guest_storage_initialized', true);

        await secureStorage.write(key: 'guest_owned_stickers', value: '[5,6]');

        await service.init();

        expect(secureStorage.deleteAllCallCount, 0);
        // Existing data should survive.
        expect(secureStorage.data['guest_owned_stickers'], '[5,6]');
      });
    });

    // ── loadOwnedStickers() ───────────────────────────────────────────

    group('loadOwnedStickers()', () {
      test('returns empty set when nothing stored', () async {
        final result = await service.loadOwnedStickers();

        expect(result, isEmpty);
      });

      test('returns empty set for empty string', () async {
        await secureStorage.write(key: 'guest_owned_stickers', value: '');

        final result = await service.loadOwnedStickers();

        expect(result, isEmpty);
      });

      test('returns persisted sticker IDs', () async {
        await secureStorage.write(
            key: 'guest_owned_stickers', value: '[10,42,99]');

        final result = await service.loadOwnedStickers();

        expect(result, {10, 42, 99});
      });
    });

    // ── saveOwnedStickers() ───────────────────────────────────────────

    group('saveOwnedStickers()', () {
      test('round-trips through save and load', () async {
        final ids = {1, 50, 980};

        await service.saveOwnedStickers(ids);
        final loaded = await service.loadOwnedStickers();

        expect(loaded, ids);
      });

      test('overwrites previous data', () async {
        await service.saveOwnedStickers({1, 2, 3});
        await service.saveOwnedStickers({4, 5});

        final loaded = await service.loadOwnedStickers();

        expect(loaded, {4, 5});
      });
    });

    // ── clearInventory() ──────────────────────────────────────────────

    group('clearInventory()', () {
      test('removes inventory key from secure storage', () async {
        await service.saveOwnedStickers({1, 2, 3});

        await service.clearInventory();
        final loaded = await service.loadOwnedStickers();

        expect(loaded, isEmpty);
      });

      test('does not affect device UUID', () async {
        final uuid = await service.getOrCreateDeviceUuid();
        await service.saveOwnedStickers({1, 2});

        await service.clearInventory();
        final uuidAfter = await service.getOrCreateDeviceUuid();

        expect(uuidAfter, uuid);
      });
    });

    // ── getOrCreateDeviceUuid() ───────────────────────────────────────

    group('getOrCreateDeviceUuid()', () {
      test('generates a valid UUID v4 on first call', () async {
        final uuid = await service.getOrCreateDeviceUuid();

        // UUID v4 format: 8-4-4-4-12 hex chars
        final uuidRegex = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        );
        expect(uuid, matches(uuidRegex));
      });

      test('returns the same UUID on subsequent calls', () async {
        final first = await service.getOrCreateDeviceUuid();
        final second = await service.getOrCreateDeviceUuid();

        expect(second, first);
      });

      test('generates new UUID after init() clears storage on reinstall',
          () async {
        final originalUuid = await service.getOrCreateDeviceUuid();

        // Simulate reinstall: SharedPreferences is cleared (new platform),
        // but Keychain (secure storage) retains the old UUID.
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.empty();
        final freshPrefs = SharedPreferencesAsync();
        final freshService = GuestStorageService(
          secureStorage: secureStorage,
          prefs: freshPrefs,
        );
        await freshService.init();

        final newUuid = await freshService.getOrCreateDeviceUuid();

        expect(newUuid, isNot(originalUuid));
      });
    });
  });
}
