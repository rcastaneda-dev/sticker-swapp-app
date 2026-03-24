import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/device_integrity_service.dart';

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('DeviceIntegrityService', () {
    test('returns true when device is compromised', () async {
      final service = DeviceIntegrityService(
        checkOverride: () async => true,
      );

      final result = await service.isDeviceCompromised();

      expect(result, isTrue);
    });

    test('returns false when device is clean', () async {
      final service = DeviceIntegrityService(
        checkOverride: () async => false,
      );

      final result = await service.isDeviceCompromised();

      expect(result, isFalse);
    });

    test('returns null when check throws', () async {
      final service = DeviceIntegrityService(
        checkOverride: () async => throw Exception('detection unavailable'),
      );

      final result = await service.isDeviceCompromised();

      expect(result, isNull);
    });

    test('caches result on second call', () async {
      var callCount = 0;
      final service = DeviceIntegrityService(
        checkOverride: () async {
          callCount++;
          return true;
        },
      );

      await service.isDeviceCompromised();
      await service.isDeviceCompromised();

      expect(callCount, 1);
    });

    test('integrityHeaderValue returns "compromised" when rooted', () async {
      final service = DeviceIntegrityService(
        checkOverride: () async => true,
      );

      final value = await service.integrityHeaderValue;

      expect(value, 'compromised');
    });

    test('integrityHeaderValue returns "clean" when not rooted', () async {
      final service = DeviceIntegrityService(
        checkOverride: () async => false,
      );

      final value = await service.integrityHeaderValue;

      expect(value, 'clean');
    });

    test('integrityHeaderValue returns null when check throws', () async {
      final service = DeviceIntegrityService(
        checkOverride: () async => throw Exception('unavailable'),
      );

      final value = await service.integrityHeaderValue;

      expect(value, isNull);
    });
  });
}
