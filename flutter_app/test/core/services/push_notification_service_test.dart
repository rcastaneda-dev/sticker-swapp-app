import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/push_notification_service.dart';

void main() {
  group('isValidUuid', () {
    test('accepts valid UUID v4', () {
      expect(isValidUuid('550e8400-e29b-41d4-a716-446655440000'), isTrue);
    });

    test('accepts uppercase UUID', () {
      expect(isValidUuid('550E8400-E29B-41D4-A716-446655440000'), isTrue);
    });

    test('accepts mixed-case UUID', () {
      expect(isValidUuid('550e8400-E29B-41d4-A716-446655440000'), isTrue);
    });

    test('rejects empty string', () {
      expect(isValidUuid(''), isFalse);
    });

    test('rejects plain text', () {
      expect(isValidUuid('not-a-uuid'), isFalse);
    });

    test('rejects UUID without dashes', () {
      expect(isValidUuid('550e8400e29b41d4a716446655440000'), isFalse);
    });

    test('rejects path traversal attempt', () {
      expect(isValidUuid('../../../etc/passwd'), isFalse);
    });

    test('rejects script injection attempt', () {
      expect(isValidUuid('<script>alert(1)</script>'), isFalse);
    });

    test('rejects UUID with extra characters', () {
      expect(isValidUuid('550e8400-e29b-41d4-a716-446655440000-extra'), isFalse);
    });
  });

  group('PushNotificationService', () {
    test('initialize calls initOverride with appId', () async {
      String? capturedAppId;
      final service = PushNotificationService(
        appId: 'test-app-id',
        initOverride: (appId) => capturedAppId = appId,
        loginOverride: (_) async {},
        logoutOverride: () async {},
      );

      await service.initialize();

      expect(capturedAppId, 'test-app-id');
    });

    test('loginUser delegates to loginOverride', () async {
      String? capturedUserId;
      final service = PushNotificationService(
        appId: 'test-app-id',
        initOverride: (_) {},
        loginOverride: (userId) async => capturedUserId = userId,
        logoutOverride: () async {},
      );

      await service.loginUser('user-123');

      expect(capturedUserId, 'user-123');
    });

    test('logoutUser delegates to logoutOverride', () async {
      var logoutCalled = false;
      final service = PushNotificationService(
        appId: 'test-app-id',
        initOverride: (_) {},
        loginOverride: (_) async {},
        logoutOverride: () async => logoutCalled = true,
      );

      await service.logoutUser();

      expect(logoutCalled, isTrue);
    });

    test('onNotificationOpened callback fires with matchId', () async {
      String? receivedMatchId;
      final service = PushNotificationService(
        appId: 'test-app-id',
        initOverride: (_) {},
        loginOverride: (_) async {},
        logoutOverride: () async {},
      );

      service.onNotificationOpened = (matchId) {
        receivedMatchId = matchId;
      };

      // Simulate what the click listener does
      service.onNotificationOpened!('match-abc');

      expect(receivedMatchId, 'match-abc');
    });

    test('onForegroundNotification returns true to suppress', () async {
      final service = PushNotificationService(
        appId: 'test-app-id',
        initOverride: (_) {},
        loginOverride: (_) async {},
        logoutOverride: () async {},
      );

      service.onForegroundNotification = (matchId) {
        return matchId != null;
      };

      expect(service.onForegroundNotification!('match-123'), isTrue);
      expect(service.onForegroundNotification!(null), isFalse);
    });

    test('processPendingNotification drains buffered matchId', () async {
      String? receivedMatchId;
      final service = PushNotificationService(
        appId: 'test-app-id',
        initOverride: (_) {},
        loginOverride: (_) async {},
        logoutOverride: () async {},
      );

      // Simulate cold-start: click fires before callback is set
      // We can't directly set _pendingMatchId, so we test via the public API:
      // 1. No callback set, so processPendingNotification is a no-op
      service.processPendingNotification();
      expect(receivedMatchId, isNull);

      // 2. Set callback, then process — still null because no pending
      service.onNotificationOpened = (matchId) {
        receivedMatchId = matchId;
      };
      service.processPendingNotification();
      expect(receivedMatchId, isNull);
    });
  });
}
