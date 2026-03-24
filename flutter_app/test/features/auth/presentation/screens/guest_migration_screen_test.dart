import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    hide AuthState, AuthException;
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/auth/data/providers/guest_migration_providers.dart';
import 'package:flutter_app/features/auth/data/services/auth_service.dart';
import 'package:flutter_app/features/auth/presentation/screens/guest_migration_screen.dart';
import 'package:flutter_app/features/stickers/data/providers/guest_inventory_providers.dart';
import 'package:flutter_app/features/stickers/data/services/guest_storage_service.dart';
import 'package:flutter_app/shared/shared.dart';

// ── Helpers ───────────────────────────────────────────────────────────────

Widget _buildSubject({
  _FakeAuthService? fakeService,
  _FakeGuestStorageService? fakeStorage,
  Set<int>? inventory,
}) {
  return ProviderScope(
    overrides: [
      authServiceProvider
          .overrideWithValue(fakeService ?? _FakeAuthService()),
      guestStorageServiceProvider
          .overrideWithValue(fakeStorage ?? _FakeGuestStorageService()),
      guestInventoryProvider.overrideWith(
        () => _FakeGuestInventoryNotifier(inventory ?? {1, 2, 3}),
      ),
    ],
    child: MaterialApp(
      theme: SwappTheme.light,
      home: const GuestMigrationScreen(),
    ),
  );
}

// ── Fakes ─────────────────────────────────────────────────────────────────

class _FakeAuthService extends AuthService {
  _FakeAuthService()
      : super(
          client: SupabaseClient(
            'https://fake.supabase.co',
            'fake-anon-key',
            authOptions:
                const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  bool migrateCalled = false;
  int itemsWrittenToReturn = 3;
  AuthException? errorToThrow;
  Completer<void>? migrationCompleter;

  @override
  Future<({int itemsSent, int itemsWritten, bool alreadyMigrated})>
      migrateGuestInventory({
    required String deviceUuid,
    required List<Map<String, dynamic>> items,
  }) async {
    migrateCalled = true;
    if (migrationCompleter != null) {
      await migrationCompleter!.future;
    }
    if (errorToThrow != null) throw errorToThrow!;
    return (
      itemsSent: items.length,
      itemsWritten: itemsWrittenToReturn,
      alreadyMigrated: false,
    );
  }
}

class _FakeGuestStorageService implements GuestStorageService {
  bool clearInventoryCalled = false;
  String deviceUuid = 'test-device-uuid';

  @override
  Future<void> init() async {}

  @override
  Future<Set<int>> loadOwnedStickers() async => {};

  @override
  Future<void> saveOwnedStickers(Set<int> stickerIds) async {}

  @override
  Future<void> clearInventory() async {
    clearInventoryCalled = true;
  }

  @override
  Future<String> getOrCreateDeviceUuid() async => deviceUuid;
}

class _FakeGuestInventoryNotifier extends AsyncNotifier<Set<int>>
    implements GuestInventoryNotifier {
  final Set<int> _initial;
  _FakeGuestInventoryNotifier(this._initial);

  @override
  Future<Set<int>> build() async => _initial;

  @override
  Future<void> toggleSticker(int stickerId) async {}

  @override
  bool isOwned(int stickerId) => _initial.contains(stickerId);

  @override
  int get ownedCount => _initial.length;
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('GuestMigrationScreen', () {
    // ── Prompt State ──

    testWidgets('renders prompt with sticker count', (tester) async {
      await tester.pumpWidget(_buildSubject(inventory: {1, 2, 3, 4, 5}));
      await tester.pumpAndSettle();

      expect(find.text('Transfer Your Collection'), findsOneWidget);
      expect(find.textContaining('5 stickers'), findsOneWidget);
      expect(find.text('Transfer Stickers'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
    });

    testWidgets('renders singular sticker text for count of 1',
        (tester) async {
      await tester.pumpWidget(_buildSubject(inventory: {42}));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 sticker '), findsOneWidget);
    });

    // ── Migrating State ──

    testWidgets('shows progress indicator during migration', (tester) async {
      final fakeService = _FakeAuthService()
        ..migrationCompleter = Completer<void>();

      await tester.pumpWidget(_buildSubject(fakeService: fakeService));
      await tester.pumpAndSettle();

      // Tap transfer
      await tester.tap(find.text('Transfer Stickers'));
      await tester.pump();

      expect(find.text('Transferring Stickers'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(fakeService.migrateCalled, isTrue);

      // Complete the migration to clean up
      fakeService.migrationCompleter!.complete();
      await tester.pumpAndSettle();
    });

    // ── Success State ──

    testWidgets('shows success state after migration', (tester) async {
      final fakeService = _FakeAuthService()..itemsWrittenToReturn = 5;
      final fakeStorage = _FakeGuestStorageService();

      await tester.pumpWidget(_buildSubject(
        fakeService: fakeService,
        fakeStorage: fakeStorage,
        inventory: {1, 2, 3, 4, 5},
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfer Stickers'));
      await tester.pumpAndSettle();

      expect(find.text('Transfer Complete'), findsOneWidget);
      expect(find.textContaining('5 stickers'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(fakeStorage.clearInventoryCalled, isTrue);
    });

    // ── Error State ──

    testWidgets('shows error state on failure', (tester) async {
      final fakeService = _FakeAuthService()
        ..errorToThrow = const AuthException(
          AuthErrorType.unknown,
          'Network error',
        );

      await tester.pumpWidget(_buildSubject(fakeService: fakeService));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transfer Stickers'));
      await tester.pumpAndSettle();

      expect(find.text('Transfer Failed'), findsOneWidget);
      expect(find.text('Network error'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Skip for Now'), findsOneWidget);
    });

    testWidgets('retry re-attempts migration after error', (tester) async {
      final fakeService = _FakeAuthService()
        ..errorToThrow = const AuthException(
          AuthErrorType.unknown,
          'Temporary error',
        );

      await tester.pumpWidget(_buildSubject(fakeService: fakeService));
      await tester.pumpAndSettle();

      // First attempt fails
      await tester.tap(find.text('Transfer Stickers'));
      await tester.pumpAndSettle();
      expect(find.text('Transfer Failed'), findsOneWidget);

      // Clear error and retry
      fakeService.errorToThrow = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Transfer Complete'), findsOneWidget);
    });

    // ── Skip ──

    testWidgets('skip sets migration complete', (tester) async {
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider
                .overrideWithValue(_FakeAuthService()),
            guestStorageServiceProvider
                .overrideWithValue(_FakeGuestStorageService()),
            guestInventoryProvider.overrideWith(
              () => _FakeGuestInventoryNotifier({1, 2, 3}),
            ),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: SwappTheme.light,
                home: const GuestMigrationScreen(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(container.read(guestMigrationCompleteProvider), isTrue);
    });

    testWidgets('continue after success sets migration complete',
        (tester) async {
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider
                .overrideWithValue(_FakeAuthService()),
            guestStorageServiceProvider
                .overrideWithValue(_FakeGuestStorageService()),
            guestInventoryProvider.overrideWith(
              () => _FakeGuestInventoryNotifier({1, 2, 3}),
            ),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: SwappTheme.light,
                home: const GuestMigrationScreen(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Transfer
      await tester.tap(find.text('Transfer Stickers'));
      await tester.pumpAndSettle();

      // Continue
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(container.read(guestMigrationCompleteProvider), isTrue);
    });
  });
}
