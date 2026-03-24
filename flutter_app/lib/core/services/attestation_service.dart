import 'dart:io' show Platform;

import 'package:app_device_integrity/app_device_integrity.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Provides device attestation tokens using platform-native APIs:
/// - Android: Google Play Integrity
/// - iOS: Apple App Attest
///
/// Returns null on web or when attestation is unavailable (e.g., emulators
/// without Play Store). The Go backend's `ATTESTATION_DISABLED=true` flag
/// allows development without real attestation.
class AttestationService {
  final AppDeviceIntegrity _plugin;
  final int? _googleCloudProjectNumber;

  /// Creates an attestation service.
  ///
  /// [googleCloudProjectNumber] is required for Android Play Integrity
  /// token generation. Pass null or omit for iOS-only usage.
  AttestationService({
    AppDeviceIntegrity? plugin,
    int? googleCloudProjectNumber,
  })  : _plugin = plugin ?? AppDeviceIntegrity(),
        _googleCloudProjectNumber = googleCloudProjectNumber;

  /// Returns the current platform identifier for the attestation header.
  ///
  /// Returns `'android'`, `'ios'`, or `null` on unsupported platforms.
  String? get platform {
    if (kIsWeb) return null;
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return null;
  }

  /// Generates an attestation token for the current device.
  ///
  /// Returns null when:
  /// - Running on web (no attestation APIs)
  /// - Platform is not Android or iOS
  /// - Attestation service is unavailable (emulator, missing Play Store)
  /// - Any platform exception occurs
  Future<String?> getAttestationToken() async {
    if (kIsWeb) return null;

    try {
      if (Platform.isAndroid) {
        return await _plugin.getAttestationServiceSupport(
          challengeString: DateTime.now().millisecondsSinceEpoch.toString(),
          gcp: _googleCloudProjectNumber ?? 0,
        );
      } else if (Platform.isIOS) {
        return await _plugin.getAttestationServiceSupport(
          challengeString: DateTime.now().millisecondsSinceEpoch.toString(),
        );
      }
      return null;
    } on PlatformException {
      // Attestation unavailable (emulator, no Play Store, etc.)
      return null;
    }
  }
}
