import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/core/services/location_service.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';

/// Singleton provider for [LocationService].
final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

/// Whether location features are available for the current user.
///
/// Returns `true` only for authenticated, age-verified, 13+ users.
/// Under-13, unauthenticated, or age-unverified users get `false`.
final locationEnabledProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  if (authState is! AuthAuthenticated) return false;

  final isUnder13 = ref.watch(isUnder13Provider);
  // Must be explicitly false (verified as 13+), not null (unverified).
  return isUnder13 == false;
});

/// Current permission status, re-checked when auth state changes.
///
/// Returns `null` if location features are disabled (under-13 or unauth).
final locationPermissionProvider =
    FutureProvider<LocationPermissionStatus?>((ref) async {
  final enabled = ref.watch(locationEnabledProvider);
  if (!enabled) return null;

  final service = ref.watch(locationServiceProvider);
  return service.checkPermission();
});

/// Whether the user has granted location permission (whileInUse or always).
final hasLocationPermissionProvider = Provider<bool>((ref) {
  final permissionAsync = ref.watch(locationPermissionProvider);
  return permissionAsync.maybeWhen(
    data: (status) =>
        status == LocationPermissionStatus.granted ||
        status == LocationPermissionStatus.grantedAlways,
    orElse: () => false,
  );
});

/// Manages the location update lifecycle: request permission, fetch
/// position, upsert to database.
///
/// State is `null` initially. Calling [requestAndUpdate] drives the
/// full flow.
class LocationNotifier extends AsyncNotifier<LocationUpdateResult?> {
  @override
  Future<LocationUpdateResult?> build() async => null;

  /// Request permission if needed, then fetch and upsert location.
  ///
  /// Returns the permission status if permission was not granted,
  /// or `null` on successful location update (result is in [state]).
  Future<LocationPermissionStatus?> requestAndUpdate() async {
    final enabled = ref.read(locationEnabledProvider);
    if (!enabled) return LocationPermissionStatus.unsupported;

    final service = ref.read(locationServiceProvider);

    // Request permission.
    final permission = await service.requestPermission();
    if (permission != LocationPermissionStatus.granted &&
        permission != LocationPermissionStatus.grantedAlways) {
      return permission;
    }

    // Permission granted — fetch and upsert.
    state = const AsyncLoading();
    final result = await service.updateLocation();
    state = AsyncData(result);

    // Refresh permission provider so downstream reads are current.
    ref.invalidate(locationPermissionProvider);

    return null;
  }
}

final locationNotifierProvider =
    AsyncNotifierProvider<LocationNotifier, LocationUpdateResult?>(
  LocationNotifier.new,
);
