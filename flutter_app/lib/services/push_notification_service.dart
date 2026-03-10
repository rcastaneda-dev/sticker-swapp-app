import 'package:onesignal_flutter/onesignal_flutter.dart';

/// Push notification service using OneSignal + FCM.
///
/// Initialized at app startup for all users, but user association
/// (login) is gated behind the is_under_13 flag per PRD §7.3.
/// The COPPA-gated login call is wired up in task #44.
class PushNotificationService {
  /// OneSignal App ID — loaded from environment config.
  final String appId;

  PushNotificationService({required this.appId});

  /// Call once at app startup (e.g., in main.dart).
  Future<void> initialize() async {
    // Debug logging — disable in release builds
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);

    // Initialize with the OneSignal App ID
    OneSignal.initialize(appId);

    // Request notification permission (Android 13+ requires runtime permission)
    OneSignal.Notifications.requestPermission(true);
  }

  /// Associate device with an authenticated 13+ user.
  /// Called ONLY after verifying is_under_13 == false.
  /// Wired up in task #44.
  Future<void> loginUser(String userId) async {
    await OneSignal.login(userId);
  }

  /// Disassociate device on logout.
  Future<void> logoutUser() async {
    await OneSignal.logout();
  }
}