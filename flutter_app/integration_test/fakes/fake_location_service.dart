import 'package:flutter_app/core/services/location_service.dart';
import 'package:geolocator/geolocator.dart';

/// Creates a [LocationService] with all platform calls faked.
///
/// Returns San Salvador coordinates (matching the matchmaking test data).
LocationService fakeLocationService({
  LocationPermission checkResult = LocationPermission.whileInUse,
  LocationPermission requestResult = LocationPermission.whileInUse,
}) {
  return LocationService(
    isServiceEnabled: () async => true,
    checkPermission: () async => checkResult,
    requestPermission: () async => requestResult,
    getPosition: ({locationSettings}) async => Position(
      latitude: 13.6929,
      longitude: -89.2182,
      timestamp: DateTime.now(),
      accuracy: 10.0,
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    ),
    openAppSettings: () async => true,
    openLocationSettings: () async => true,
  );
}
