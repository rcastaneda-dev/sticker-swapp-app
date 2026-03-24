import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:safe_device/safe_device.dart';

/// Callback type for injectable root/jailbreak checks (testability).
typedef RootCheckFn = Future<bool> Function();

/// Detects whether the device is rooted (Android) or jailbroken (iOS).
///
/// This is a client-side signal sent to the Go backend via the
/// `X-Device-Integrity` header. The server treats it as an untrusted
/// advisory signal (defense-in-depth alongside attestation).
///
/// The check runs once at app launch and caches the result for the
/// session lifetime — root/jailbreak status does not change mid-session.
class DeviceIntegrityService {
  final RootCheckFn? _checkOverride;
  bool? _cachedIsCompromised;

  /// Creates a device integrity service.
  ///
  /// [checkOverride] overrides the default `SafeDevice.isJailBroken` call
  /// for unit testing. Production code should omit this parameter.
  DeviceIntegrityService({RootCheckFn? checkOverride})
      : _checkOverride = checkOverride;

  /// Checks device integrity once and caches the result.
  ///
  /// Returns `true` if the device is rooted/jailbroken, `false` if clean,
  /// or `null` if detection is unavailable (web, unsupported platform).
  Future<bool?> isDeviceCompromised() async {
    if (kIsWeb) return null;
    if (_cachedIsCompromised != null) return _cachedIsCompromised;

    try {
      if (_checkOverride != null) {
        // Test override — bypasses platform check.
        _cachedIsCompromised = await _checkOverride();
      } else if (Platform.isAndroid || Platform.isIOS) {
        // SafeDevice.isJailBroken detects both root (Android) and
        // jailbreak (iOS) via platform channels.
        _cachedIsCompromised = await SafeDevice.isJailBroken;
      }
      return _cachedIsCompromised;
    } catch (_) {
      // Detection unavailable — fail open (treat as unknown)
      return null;
    }
  }

  /// Returns the integrity status as a header value string.
  ///
  /// - `"compromised"` if rooted/jailbroken
  /// - `"clean"` if not
  /// - `null` if unknown (header will not be sent)
  Future<String?> get integrityHeaderValue async {
    final result = await isDeviceCompromised();
    if (result == null) return null;
    return result ? 'compromised' : 'clean';
  }
}
