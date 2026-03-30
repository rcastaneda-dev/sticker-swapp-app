import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Callback type for injectable permission check (testability).
typedef CheckPermissionFn = Future<LocationPermission> Function();

/// Callback type for injectable permission request (testability).
typedef RequestPermissionFn = Future<LocationPermission> Function();

/// Callback type for injectable service-enabled check (testability).
typedef IsServiceEnabledFn = Future<bool> Function();

/// Callback type for injectable position fetch (testability).
typedef GetPositionFn = Future<Position> Function({
  LocationSettings? locationSettings,
});

/// Callback type for injectable settings opener (testability).
typedef OpenSettingsFn = Future<bool> Function();

/// Possible outcomes of a location permission check or request.
enum LocationPermissionStatus {
  /// Permission granted for while-in-use (foreground).
  granted,

  /// Permission granted for always (superset of granted).
  grantedAlways,

  /// User denied the permission (can request again).
  denied,

  /// User denied permanently — must go to app settings.
  deniedForever,

  /// Location services are disabled at the OS level.
  serviceDisabled,

  /// Platform is unsupported (web).
  unsupported,
}

/// Result of a location update attempt.
class LocationUpdateResult {
  final bool success;
  final double? latitude;
  final double? longitude;
  final int? accuracyMeters;
  final String? error;

  const LocationUpdateResult._({
    required this.success,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.error,
  });

  factory LocationUpdateResult.success({
    required double latitude,
    required double longitude,
    required int accuracyMeters,
  }) =>
      LocationUpdateResult._(
        success: true,
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: accuracyMeters,
      );

  factory LocationUpdateResult.failure(String error) =>
      LocationUpdateResult._(success: false, error: error);
}

/// Handles foreground location permission, position fetching, and
/// Supabase `user_locations` upsert.
///
/// Platform calls are injectable for unit testing. Production code
/// should omit optional constructor parameters.
class LocationService {
  final SupabaseClient? _injectedClient;
  final CheckPermissionFn _checkPermission;
  final RequestPermissionFn _requestPermission;
  final IsServiceEnabledFn _isServiceEnabled;
  final GetPositionFn _getPosition;
  final OpenSettingsFn _openAppSettings;
  final OpenSettingsFn _openLocationSettings;

  LocationService({
    SupabaseClient? client,
    CheckPermissionFn? checkPermission,
    RequestPermissionFn? requestPermission,
    IsServiceEnabledFn? isServiceEnabled,
    GetPositionFn? getPosition,
    OpenSettingsFn? openAppSettings,
    OpenSettingsFn? openLocationSettings,
  })  : _injectedClient = client,
        _checkPermission = checkPermission ?? Geolocator.checkPermission,
        _requestPermission = requestPermission ?? Geolocator.requestPermission,
        _isServiceEnabled =
            isServiceEnabled ?? Geolocator.isLocationServiceEnabled,
        _getPosition = getPosition ?? _defaultGetPosition,
        _openAppSettings = openAppSettings ?? Geolocator.openAppSettings,
        _openLocationSettings =
            openLocationSettings ?? Geolocator.openLocationSettings;

  /// Lazily resolved Supabase client — avoids accessing [Supabase.instance]
  /// at construction time so that permission-only tests don't need
  /// Supabase initialization.
  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  /// Check current permission status without requesting.
  Future<LocationPermissionStatus> checkPermission() async {
    if (kIsWeb) return LocationPermissionStatus.unsupported;

    final serviceEnabled = await _isServiceEnabled();
    if (!serviceEnabled) return LocationPermissionStatus.serviceDisabled;

    final permission = await _checkPermission();
    return _mapPermission(permission);
  }

  /// Request foreground location permission.
  ///
  /// If the user has previously denied permanently, this returns
  /// [LocationPermissionStatus.deniedForever] without showing a system
  /// dialog (it's a no-op on iOS). The caller should offer to open
  /// app settings via [openAppSettings].
  Future<LocationPermissionStatus> requestPermission() async {
    if (kIsWeb) return LocationPermissionStatus.unsupported;

    final serviceEnabled = await _isServiceEnabled();
    if (!serviceEnabled) return LocationPermissionStatus.serviceDisabled;

    // If already deniedForever, requesting again is a no-op on iOS.
    // Return early so the UI can prompt the user to open settings.
    final current = await _checkPermission();
    if (current == LocationPermission.deniedForever) {
      return LocationPermissionStatus.deniedForever;
    }

    final permission = await _requestPermission();
    return _mapPermission(permission);
  }

  /// Open the app's system settings page (for deniedForever recovery).
  Future<bool> openAppSettings() => _openAppSettings();

  /// Open the device's location settings (for serviceDisabled recovery).
  Future<bool> openLocationSettings() => _openLocationSettings();

  /// Get the current position and upsert it into `user_locations`.
  ///
  /// The caller is responsible for ensuring permission is granted
  /// before calling this method.
  Future<LocationUpdateResult> updateLocation() async {
    if (kIsWeb) {
      return LocationUpdateResult.failure('Location not supported on web');
    }

    try {
      final position = await _getPosition(
        locationSettings: _platformSettings(),
      );

      final userId = _client.auth.currentUser!.id;

      // PostGIS expects POINT(longitude latitude) — longitude first.
      await _client.from('user_locations').upsert({
        'user_id': userId,
        'location': buildPointWkt(position.longitude, position.latitude),
        'accuracy_m': position.accuracy.round(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      return LocationUpdateResult.success(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy.round(),
      );
    } on PostgrestException catch (e) {
      return LocationUpdateResult.failure(e.message);
    } catch (e) {
      return LocationUpdateResult.failure(e.toString());
    }
  }

  /// Delete the user's location from `user_locations` (opt-out / cleanup).
  Future<void> deleteLocation() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client.from('user_locations').delete().eq('user_id', userId);
  }

  /// Build a PostGIS WKT point string. Exposed for testing.
  static String buildPointWkt(double longitude, double latitude) {
    return 'POINT($longitude $latitude)';
  }

  // ── Private helpers ─────────────────────────────────────────────

  LocationPermissionStatus _mapPermission(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.whileInUse:
        return LocationPermissionStatus.granted;
      case LocationPermission.always:
        return LocationPermissionStatus.grantedAlways;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationPermissionStatus.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionStatus.deniedForever;
    }
  }

  /// Platform-specific location settings for battery efficiency.
  static LocationSettings _platformSettings() {
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50,
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50,
        activityType: ActivityType.other,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50,
    );
  }

  /// Default position getter wrapping Geolocator.getCurrentPosition.
  static Future<Position> _defaultGetPosition({
    LocationSettings? locationSettings,
  }) {
    return Geolocator.getCurrentPosition(locationSettings: locationSettings);
  }
}
