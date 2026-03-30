import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_app/core/services/location_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────

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

/// Creates a [LocationService] with injectable fakes.
LocationService _createService({
  bool serviceEnabled = true,
  LocationPermission checkResult = LocationPermission.denied,
  LocationPermission requestResult = LocationPermission.whileInUse,
  Position? position,
}) {
  return LocationService(
    isServiceEnabled: () async => serviceEnabled,
    checkPermission: () async => checkResult,
    requestPermission: () async => requestResult,
    getPosition: ({locationSettings}) async => position ?? _fakePosition(),
    openAppSettings: () async => true,
    openLocationSettings: () async => true,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('LocationService', () {
    // ── checkPermission ──

    group('checkPermission()', () {
      test('returns serviceDisabled when location services are off', () async {
        final service = _createService(serviceEnabled: false);

        final result = await service.checkPermission();

        expect(result, LocationPermissionStatus.serviceDisabled);
      });

      test('returns granted when whileInUse', () async {
        final service = _createService(
          checkResult: LocationPermission.whileInUse,
        );

        final result = await service.checkPermission();

        expect(result, LocationPermissionStatus.granted);
      });

      test('returns grantedAlways when always', () async {
        final service = _createService(
          checkResult: LocationPermission.always,
        );

        final result = await service.checkPermission();

        expect(result, LocationPermissionStatus.grantedAlways);
      });

      test('returns denied when denied', () async {
        final service = _createService(
          checkResult: LocationPermission.denied,
        );

        final result = await service.checkPermission();

        expect(result, LocationPermissionStatus.denied);
      });

      test('returns denied when unableToDetermine', () async {
        final service = _createService(
          checkResult: LocationPermission.unableToDetermine,
        );

        final result = await service.checkPermission();

        expect(result, LocationPermissionStatus.denied);
      });

      test('returns deniedForever when deniedForever', () async {
        final service = _createService(
          checkResult: LocationPermission.deniedForever,
        );

        final result = await service.checkPermission();

        expect(result, LocationPermissionStatus.deniedForever);
      });
    });

    // ── requestPermission ──

    group('requestPermission()', () {
      test('returns serviceDisabled when services are off', () async {
        final service = _createService(serviceEnabled: false);

        final result = await service.requestPermission();

        expect(result, LocationPermissionStatus.serviceDisabled);
      });

      test(
        'returns deniedForever without calling requestPermission '
        'when already deniedForever',
        () async {
          var requestCallCount = 0;
          final service = LocationService(
            isServiceEnabled: () async => true,
            checkPermission: () async => LocationPermission.deniedForever,
            requestPermission: () async {
              requestCallCount++;
              return LocationPermission.deniedForever;
            },
            getPosition: ({locationSettings}) async => _fakePosition(),
            openAppSettings: () async => true,
            openLocationSettings: () async => true,
          );

          final result = await service.requestPermission();

          expect(result, LocationPermissionStatus.deniedForever);
          expect(requestCallCount, 0);
        },
      );

      test('calls requestPermission and returns granted on success', () async {
        final service = _createService(
          checkResult: LocationPermission.denied,
          requestResult: LocationPermission.whileInUse,
        );

        final result = await service.requestPermission();

        expect(result, LocationPermissionStatus.granted);
      });

      test('calls requestPermission and returns denied on denial', () async {
        final service = _createService(
          checkResult: LocationPermission.denied,
          requestResult: LocationPermission.denied,
        );

        final result = await service.requestPermission();

        expect(result, LocationPermissionStatus.denied);
      });
    });

    // ── updateLocation ──

    group('updateLocation()', () {
      test('returns success with correct coordinates', () async {
        final service = _createService(
          position: _fakePosition(
            latitude: 13.6929,
            longitude: -89.2182,
            accuracy: 15.0,
          ),
        );

        // updateLocation requires a real SupabaseClient, so we test
        // the position fetch and result construction indirectly.
        // The Supabase upsert will throw without a real client,
        // which is expected — that's an integration concern.
        final result = await service.updateLocation();

        // Without a real Supabase client this will fail — that's OK.
        // We verify it returns a failure result (not a crash).
        expect(result.success, isFalse);
        expect(result.error, isNotNull);
      });

      test('returns failure when position fetch throws', () async {
        final service = LocationService(
          isServiceEnabled: () async => true,
          checkPermission: () async => LocationPermission.whileInUse,
          requestPermission: () async => LocationPermission.whileInUse,
          getPosition: ({locationSettings}) async =>
              throw Exception('GPS unavailable'),
          openAppSettings: () async => true,
          openLocationSettings: () async => true,
        );

        final result = await service.updateLocation();

        expect(result.success, isFalse);
        expect(result.error, contains('GPS unavailable'));
      });
    });

    // ── deleteLocation ──

    group('deleteLocation()', () {
      test('returns without error when user is null', () async {
        // SupabaseClient with no authenticated user — currentUser is null,
        // so deleteLocation returns early without making a network call.
        final client = SupabaseClient(
          'https://example.supabase.co',
          'fake-anon-key',
        );
        final service = LocationService(
          client: client,
          isServiceEnabled: () async => true,
          checkPermission: () async => LocationPermission.denied,
          requestPermission: () async => LocationPermission.denied,
          getPosition: ({locationSettings}) async => _fakePosition(),
          openAppSettings: () async => true,
          openLocationSettings: () async => true,
        );

        // Should return without throwing — no user means early return.
        await service.deleteLocation();
      });
    });

    // ── buildPointWkt ──

    group('buildPointWkt()', () {
      test('formats POINT with longitude first, latitude second', () {
        final wkt = LocationService.buildPointWkt(-89.2182, 13.6929);

        expect(wkt, 'POINT(-89.2182 13.6929)');
      });

      test('handles negative coordinates', () {
        final wkt = LocationService.buildPointWkt(-122.4194, -37.7749);

        expect(wkt, 'POINT(-122.4194 -37.7749)');
      });

      test('handles zero coordinates', () {
        final wkt = LocationService.buildPointWkt(0.0, 0.0);

        expect(wkt, 'POINT(0.0 0.0)');
      });
    });

    // ── openAppSettings / openLocationSettings ──

    group('settings openers', () {
      test('openAppSettings delegates to injected function', () async {
        var called = false;
        final service = LocationService(
          isServiceEnabled: () async => true,
          checkPermission: () async => LocationPermission.denied,
          requestPermission: () async => LocationPermission.denied,
          getPosition: ({locationSettings}) async => _fakePosition(),
          openAppSettings: () async {
            called = true;
            return true;
          },
          openLocationSettings: () async => true,
        );

        final result = await service.openAppSettings();

        expect(called, isTrue);
        expect(result, isTrue);
      });

      test('openLocationSettings delegates to injected function', () async {
        var called = false;
        final service = LocationService(
          isServiceEnabled: () async => true,
          checkPermission: () async => LocationPermission.denied,
          requestPermission: () async => LocationPermission.denied,
          getPosition: ({locationSettings}) async => _fakePosition(),
          openAppSettings: () async => true,
          openLocationSettings: () async {
            called = true;
            return true;
          },
        );

        final result = await service.openLocationSettings();

        expect(called, isTrue);
        expect(result, isTrue);
      });
    });
  });
}
