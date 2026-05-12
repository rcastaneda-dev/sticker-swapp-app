import 'package:flutter_app/core/services/push_notification_service.dart';

/// No-op push notification service for integration tests.
///
/// Prevents OneSignal SDK initialization and platform channel calls.
class FakePushNotificationService extends PushNotificationService {
  bool initializeCalled = false;
  bool loginCalled = false;
  bool logoutCalled = false;
  String? lastLoginUserId;

  FakePushNotificationService()
      : super(
          appId: 'fake-onesignal-app-id',
          initOverride: (_) {},
          loginOverride: (_) async {},
          logoutOverride: () async {},
        );

  @override
  Future<void> initialize() async {
    initializeCalled = true;
  }

  @override
  Future<void> loginUser(String userId) async {
    loginCalled = true;
    lastLoginUserId = userId;
  }

  @override
  Future<void> logoutUser() async {
    logoutCalled = true;
  }

  @override
  void processPendingNotification() {
    // No-op
  }
}
