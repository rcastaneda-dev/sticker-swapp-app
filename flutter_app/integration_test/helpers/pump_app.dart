import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_app/app.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/chat/data/providers/chat_providers.dart';
import 'package:flutter_app/features/matching/data/providers/discovery_providers.dart';
import 'package:flutter_app/features/matching/data/providers/location_providers.dart';
import 'package:flutter_app/features/matching/data/providers/trade_confirmation_providers.dart';
import 'package:flutter_app/core/services/location_service.dart';
import 'package:flutter_app/features/stickers/data/providers/collection_progress_providers.dart';
import 'package:flutter_app/features/stickers/data/providers/guest_inventory_providers.dart';
import 'package:flutter_app/features/stickers/data/providers/sticker_providers.dart';
import 'package:flutter_app/features/stickers/data/providers/user_inventory_providers.dart';
import 'package:flutter_app/features/matching/data/services/trade_confirmation_service.dart';
import 'package:flutter_app/core/providers/push_notification_providers.dart';

import '../fakes/fake_auth_state_notifier.dart';
import '../fakes/fake_auth_service.dart';
import '../fakes/fake_guest_storage_service.dart';
import '../fakes/fake_sticker_service.dart';
import '../fakes/fake_location_service.dart';
import '../fakes/fake_user_inventory_service.dart';
import '../fakes/fake_match_discovery_service.dart';
import '../fakes/fake_chat_notifier.dart';
import '../fakes/fake_push_notification_service.dart';
import '../fakes/fake_trade_confirmation_notifier.dart';
import '../fakes/fake_ably_service.dart';
import '../fixtures/test_stickers.dart';

/// Centralized test harness holding all fake references and provider overrides.
///
/// Usage:
/// ```dart
/// final harness = TestHarness();
/// await harness.pumpApp(tester);
/// harness.authNotifier.simulateSignIn(metadata: adultVerifiedMetadata());
/// await tester.pumpAndSettle();
/// ```
class TestHarness {
  late final FakeAuthStateNotifier authNotifier;
  late final FakeAuthService authService;
  late final FakeGuestStorageService guestStorage;
  late final FakeStickerService stickerService;
  late final FakeUserInventoryService userInventoryService;
  late final FakeMatchDiscoveryService matchDiscoveryService;
  late final FakePushNotificationService pushNotificationService;
  late final FakeAblyService ablyService;

  /// Guest sticker IDs seeded at startup.
  final Set<int> initialGuestInventory;

  TestHarness({
    this.initialGuestInventory = const {},
    bool verifyAgeReturnsUnder13 = false,
  }) {
    authNotifier = FakeAuthStateNotifier();
    authService = FakeAuthService(
      authNotifier: authNotifier,
      verifyAgeReturnsUnder13: verifyAgeReturnsUnder13,
    );
    guestStorage = FakeGuestStorageService(
      initialInventory: Set.from(initialGuestInventory),
    );
    stickerService = FakeStickerService();
    userInventoryService = FakeUserInventoryService();
    matchDiscoveryService = FakeMatchDiscoveryService();
    pushNotificationService = FakePushNotificationService();
    ablyService = FakeAblyService();
  }

  /// Build the list of provider overrides that replace all external services.
  List<Object> get _overrides => [
        // Auth
        authStateProvider.overrideWith(() => authNotifier),
        authServiceProvider.overrideWithValue(authService),

        // Guest storage (avoids flutter_secure_storage platform channel)
        guestStorageServiceProvider.overrideWithValue(guestStorage),
        guestInventoryProvider.overrideWith(() => _FakeGuestInventoryNotifier(
              initialGuestInventory,
            )),

        // Sticker service (avoids Supabase query)
        stickerServiceProvider.overrideWithValue(stickerService),
        allStickersProvider.overrideWith((ref) async => testStickers.toList()),
        stickerListProvider.overrideWith((ref) async {
          final filter = ref.watch(stickerFilterProvider);
          return stickerService.fetchStickers(
            team: filter.team,
            type: filter.type,
          );
        }),
        teamListProvider.overrideWith(
          (ref) async => stickerService.fetchTeams(),
        ),

        // User inventory (avoids Supabase query)
        userInventoryServiceProvider.overrideWithValue(userInventoryService),
        userInventoryProvider.overrideWith(() => _FakeUserInventoryNotifier(
              userInventoryService,
            )),
        reservedStickersProvider.overrideWith((ref) async => <int>{}),

        // Location (avoids geolocator platform channel + Supabase upsert)
        locationServiceProvider.overrideWithValue(fakeLocationService()),
        locationNotifierProvider
            .overrideWith(() => _FakeLocationNotifier()),

        // Match discovery (avoids Go backend HTTP)
        matchDiscoveryServiceProvider
            .overrideWithValue(matchDiscoveryService),

        // Chat (avoids Ably WebSocket)
        ablyServiceProvider.overrideWithValue(ablyService),
        chatProvider.overrideWith(
          () => FakeChatNotifier(''),
        ),

        // Trade confirmation (avoids Go backend HTTP)
        tradeConfirmationServiceProvider.overrideWithValue(
          _noopTradeConfirmationService(),
        ),
        tradeConfirmationProvider.overrideWith(
          () => FakeTradeConfirmationNotifier(''),
        ),

        // Push notifications (avoids OneSignal SDK)
        pushNotificationServiceProvider
            .overrideWithValue(pushNotificationService),
        pushNotificationLifecycleProvider.overrideWith((ref) {}),

        // Consent polling (avoids Supabase.instance.client access)
        consentPollingProvider.overrideWith(
          (ref) => Stream.value(false),
        ),
      ];

  /// Pump the full [App] widget tree inside a [ProviderScope] with all
  /// fake overrides applied.
  Future<void> pumpApp(WidgetTester tester) async {
    IntegrationTestWidgetsFlutterBinding.ensureInitialized();

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides.cast(),
        child: const App(),
      ),
    );

    // Let the initial build + GoRouter redirect settle.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  }
}

/// In-memory guest inventory notifier for test harness.
class _FakeGuestInventoryNotifier extends GuestInventoryNotifier {
  final Set<int> _initial;

  _FakeGuestInventoryNotifier(this._initial);

  @override
  Future<Set<int>> build() async => Set.from(_initial);
}

/// In-memory user inventory notifier for test harness.
class _FakeUserInventoryNotifier extends UserInventoryNotifier {
  final FakeUserInventoryService _service;

  _FakeUserInventoryNotifier(this._service);

  @override
  Future<Set<int>> build() async => _service.fetchOwnedStickerIds();

  @override
  Future<void> toggleSticker(int stickerId) async {
    await _service.toggleSticker(stickerId);
    state = AsyncData(await _service.fetchOwnedStickerIds());
  }
}

/// Fake location notifier that returns San Salvador coordinates immediately.
///
/// Avoids the real [LocationNotifier.requestAndUpdate] which calls
/// [LocationService.updateLocation] → Supabase `user_locations` upsert.
class _FakeLocationNotifier extends LocationNotifier {
  static LocationUpdateResult _sanSalvador() =>
      LocationUpdateResult.success(
        latitude: 13.6929,
        longitude: -89.2182,
        accuracyMeters: 10,
      );

  @override
  Future<LocationUpdateResult?> build() async => _sanSalvador();

  @override
  Future<LocationPermissionStatus?> requestAndUpdate() async {
    state = AsyncData(_sanSalvador());
    return null; // null = permission granted, location updated
  }
}

/// Create a no-op trade confirmation service that won't hit the Go backend.
TradeConfirmationService _noopTradeConfirmationService() {
  return TradeConfirmationService(baseUrl: 'https://fake-go-service');
}
