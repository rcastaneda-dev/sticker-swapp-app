import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/matching/data/providers/location_providers.dart';
import 'package:flutter_app/core/services/location_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────

/// Stub auth state notifier that returns a fixed state.
class _StubAuthStateNotifier extends AuthStateNotifier {
  final AppAuthState _initial;
  _StubAuthStateNotifier(this._initial);

  @override
  AppAuthState build() => _initial;
}

/// Returns an [AuthAuthenticated] state with the given user metadata.
AuthAuthenticated _authenticated({Map<String, dynamic>? metadata}) {
  final user = User(
    id: 'test-user-id',
    appMetadata: {},
    userMetadata: metadata ?? {},
    aud: 'authenticated',
    createdAt: DateTime.now().toIso8601String(),
  );
  return AuthAuthenticated(
    user: user,
    session: Session(
      accessToken: 'fake-access-token',
      tokenType: 'bearer',
      user: user,
    ),
  );
}

Position _fakePosition({
  double latitude = 13.6929,
  double longitude = -89.2182,
  double accuracy = 15.0,
}) =>
    Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime(2026, 3, 30),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// Creates a [LocationService] with injectable fakes for testing.
LocationService _fakeLocationService({
  LocationPermission checkResult = LocationPermission.whileInUse,
  bool serviceEnabled = true,
}) {
  return LocationService(
    isServiceEnabled: () async => serviceEnabled,
    checkPermission: () async => checkResult,
    requestPermission: () async => checkResult,
    getPosition: ({locationSettings}) async => _fakePosition(),
    openAppSettings: () async => true,
    openLocationSettings: () async => true,
  );
}

/// Creates a [ProviderContainer] with auth state and optional location
/// service overrides.
ProviderContainer _createContainer({
  required AppAuthState authState,
  LocationService? locationService,
}) {
  return ProviderContainer(
    overrides: [
      authStateProvider.overrideWith(() => _StubAuthStateNotifier(authState)),
      if (locationService != null)
        locationServiceProvider.overrideWithValue(locationService),
    ],
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('Location Providers', () {
    // ── locationEnabledProvider ──

    group('locationEnabledProvider', () {
      test('returns false when unauthenticated', () {
        final container = _createContainer(
          authState: const AuthUnauthenticated(),
        );
        addTearDown(container.dispose);

        expect(container.read(locationEnabledProvider), isFalse);
      });

      test('returns false when under-13', () {
        final container = _createContainer(
          authState: _authenticated(metadata: {
            'is_under_13': true,
            'age_verified_at': '2024-01-01T00:00:00Z',
          }),
        );
        addTearDown(container.dispose);

        expect(container.read(locationEnabledProvider), isFalse);
      });

      test('returns false when age not yet verified (is_under_13 is null)',
          () {
        final container = _createContainer(
          authState: _authenticated(),
        );
        addTearDown(container.dispose);

        expect(container.read(locationEnabledProvider), isFalse);
      });

      test('returns true when authenticated and 13+', () {
        final container = _createContainer(
          authState: _authenticated(metadata: {
            'is_under_13': false,
            'age_verified_at': '2024-01-01T00:00:00Z',
          }),
        );
        addTearDown(container.dispose);

        expect(container.read(locationEnabledProvider), isTrue);
      });
    });

    // ── locationPermissionProvider ──

    group('locationPermissionProvider', () {
      test('returns null when location is disabled (under-13)', () async {
        final container = _createContainer(
          authState: _authenticated(metadata: {
            'is_under_13': true,
            'age_verified_at': '2024-01-01T00:00:00Z',
          }),
          locationService: _fakeLocationService(),
        );
        addTearDown(container.dispose);

        final result =
            await container.read(locationPermissionProvider.future);

        expect(result, isNull);
      });

      test('returns null when unauthenticated', () async {
        final container = _createContainer(
          authState: const AuthUnauthenticated(),
          locationService: _fakeLocationService(),
        );
        addTearDown(container.dispose);

        final result =
            await container.read(locationPermissionProvider.future);

        expect(result, isNull);
      });

      test('returns granted when 13+ and permission is whileInUse', () async {
        final container = _createContainer(
          authState: _authenticated(metadata: {
            'is_under_13': false,
            'age_verified_at': '2024-01-01T00:00:00Z',
          }),
          locationService: _fakeLocationService(
            checkResult: LocationPermission.whileInUse,
          ),
        );
        addTearDown(container.dispose);

        final result =
            await container.read(locationPermissionProvider.future);

        expect(result, LocationPermissionStatus.granted);
      });

      test('returns denied when 13+ and permission is denied', () async {
        final container = _createContainer(
          authState: _authenticated(metadata: {
            'is_under_13': false,
            'age_verified_at': '2024-01-01T00:00:00Z',
          }),
          locationService: _fakeLocationService(
            checkResult: LocationPermission.denied,
          ),
        );
        addTearDown(container.dispose);

        final result =
            await container.read(locationPermissionProvider.future);

        expect(result, LocationPermissionStatus.denied);
      });

      test('returns serviceDisabled when services are off', () async {
        final container = _createContainer(
          authState: _authenticated(metadata: {
            'is_under_13': false,
            'age_verified_at': '2024-01-01T00:00:00Z',
          }),
          locationService: _fakeLocationService(
            serviceEnabled: false,
          ),
        );
        addTearDown(container.dispose);

        final result =
            await container.read(locationPermissionProvider.future);

        expect(result, LocationPermissionStatus.serviceDisabled);
      });
    });

    // ── hasLocationPermissionProvider ──

    group('hasLocationPermissionProvider', () {
      test('returns true when granted', () async {
        final container = _createContainer(
          authState: _authenticated(metadata: {
            'is_under_13': false,
            'age_verified_at': '2024-01-01T00:00:00Z',
          }),
          locationService: _fakeLocationService(
            checkResult: LocationPermission.whileInUse,
          ),
        );
        addTearDown(container.dispose);

        // Wait for the FutureProvider to resolve.
        await container.read(locationPermissionProvider.future);

        expect(container.read(hasLocationPermissionProvider), isTrue);
      });

      test('returns true when grantedAlways', () async {
        final container = _createContainer(
          authState: _authenticated(metadata: {
            'is_under_13': false,
            'age_verified_at': '2024-01-01T00:00:00Z',
          }),
          locationService: _fakeLocationService(
            checkResult: LocationPermission.always,
          ),
        );
        addTearDown(container.dispose);

        await container.read(locationPermissionProvider.future);

        expect(container.read(hasLocationPermissionProvider), isTrue);
      });

      test('returns false when denied', () async {
        final container = _createContainer(
          authState: _authenticated(metadata: {
            'is_under_13': false,
            'age_verified_at': '2024-01-01T00:00:00Z',
          }),
          locationService: _fakeLocationService(
            checkResult: LocationPermission.denied,
          ),
        );
        addTearDown(container.dispose);

        await container.read(locationPermissionProvider.future);

        expect(container.read(hasLocationPermissionProvider), isFalse);
      });

      test('returns false when location is disabled (under-13)', () async {
        final container = _createContainer(
          authState: _authenticated(metadata: {
            'is_under_13': true,
            'age_verified_at': '2024-01-01T00:00:00Z',
          }),
          locationService: _fakeLocationService(),
        );
        addTearDown(container.dispose);

        await container.read(locationPermissionProvider.future);

        expect(container.read(hasLocationPermissionProvider), isFalse);
      });
    });
  });
}
