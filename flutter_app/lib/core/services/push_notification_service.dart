import 'package:onesignal_flutter/onesignal_flutter.dart';

/// Callback types for injectable OneSignal calls (testability).
typedef OneSignalInitFn = void Function(String appId);
typedef OneSignalLoginFn = Future<void> Function(String userId);
typedef OneSignalLogoutFn = Future<void> Function();

/// Called when user taps a push notification containing a match_id.
typedef NotificationOpenedCallback = void Function(String matchId);

/// Called when a notification arrives while the app is in the foreground.
/// Return `true` to suppress the OS notification display.
typedef ForegroundNotificationCallback = bool Function(String? matchId);

/// UUID regex for validating match IDs from push notification payloads.
final _uuidRegex = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Returns true if [value] is a valid UUID string.
/// Used to validate match IDs from untrusted sources (push notifications).
bool isValidUuid(String value) => _uuidRegex.hasMatch(value);

/// Push notification service using OneSignal + FCM.
///
/// Initialized at app startup for all users, but user association
/// (login) is gated behind the is_under_13 flag per PRD §7.3.
///
/// When [initOverride] is provided (tests), all OneSignal platform
/// channel calls are skipped — only the override callbacks run.
class PushNotificationService {
  /// OneSignal App ID — loaded from environment config.
  final String appId;

  final OneSignalInitFn? _initOverride;
  final OneSignalLoginFn? _loginOverride;
  final OneSignalLogoutFn? _logoutOverride;

  /// Set by the lifecycle provider to handle notification taps.
  NotificationOpenedCallback? onNotificationOpened;

  /// Set by the lifecycle provider to handle foreground notifications.
  ForegroundNotificationCallback? onForegroundNotification;

  /// Buffered match ID from a cold-start notification tap that fired
  /// before [onNotificationOpened] was wired up.
  String? _pendingMatchId;

  /// Whether overrides are in use (test mode).
  bool get _isTestMode => _initOverride != null;

  PushNotificationService({
    required this.appId,
    OneSignalInitFn? initOverride,
    OneSignalLoginFn? loginOverride,
    OneSignalLogoutFn? logoutOverride,
  })  : _initOverride = initOverride,
        _loginOverride = loginOverride,
        _logoutOverride = logoutOverride;

  /// Call once at app startup (e.g., in main.dart).
  ///
  /// In test mode (overrides provided), skips all OneSignal platform
  /// channel calls and only invokes the init override.
  Future<void> initialize() async {
    if (_isTestMode) {
      _initOverride!(appId);
      return;
    }

    // Debug logging — disable in release builds
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize(appId);

    // Request notification permission (Android 13+ requires runtime permission)
    OneSignal.Notifications.requestPermission(true);

    // Notification tap handler (cold start + background resume)
    OneSignal.Notifications.addClickListener((event) {
      final matchId =
          event.notification.additionalData?['match_id'] as String?;
      if (matchId == null || !_uuidRegex.hasMatch(matchId)) return;

      if (onNotificationOpened != null) {
        onNotificationOpened!(matchId);
      } else {
        _pendingMatchId = matchId;
      }
    });

    // Foreground notification handler
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      final rawMatchId =
          event.notification.additionalData?['match_id'] as String?;
      final matchId =
          (rawMatchId != null && _uuidRegex.hasMatch(rawMatchId))
              ? rawMatchId
              : null;

      if (onForegroundNotification != null) {
        final suppress = onForegroundNotification!(matchId);
        if (suppress) {
          event.preventDefault();
          return;
        }
      }
      event.notification.display();
    });
  }

  /// Drains any buffered cold-start notification. Call once after
  /// [onNotificationOpened] is wired up.
  void processPendingNotification() {
    final pending = _pendingMatchId;
    _pendingMatchId = null;
    if (pending != null && onNotificationOpened != null) {
      onNotificationOpened!(pending);
    }
  }

  /// Associate device with an authenticated 13+ user.
  /// Called ONLY after verifying is_under_13 == false.
  Future<void> loginUser(String userId) async {
    if (_loginOverride != null) {
      await _loginOverride(userId);
    } else {
      await OneSignal.login(userId);
    }
  }

  /// Disassociate device on logout.
  Future<void> logoutUser() async {
    if (_logoutOverride != null) {
      await _logoutOverride();
    } else {
      await OneSignal.logout();
    }
  }
}
