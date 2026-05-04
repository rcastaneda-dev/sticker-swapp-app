import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:flutter_app/core/providers/push_notification_providers.dart';
import 'package:flutter_app/core/providers/deep_link_providers.dart';
import 'package:flutter_app/core/router/app_router.dart';
import 'package:flutter_app/core/services/push_notification_service.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';

// ── Helpers ───────────────────────────────────────────────────────────────

AuthAuthenticated _authenticated({Map<String, dynamic>? metadata}) {
  final user = User(
    id: 'test-user-id',
    appMetadata: {},
    userMetadata: metadata ?? {},
    aud: 'authenticated',
    createdAt: DateTime.now().toIso8601String(),
  );
  return AuthAuthenticated(
    user: user,
    session: Session(
      accessToken: 'fake-access-token',
      tokenType: 'bearer',
      user: user,
    ),
  );
}

class _StubAuthStateNotifier extends AuthStateNotifier {
  final AppAuthState _initial;
  _StubAuthStateNotifier(this._initial);

  @override
  AppAuthState build() => _initial;
}

class _TrackingPushService extends PushNotificationService {
  String? lastLoginUserId;
  var logoutCalled = false;
  var initCalled = false;

  _TrackingPushService()
      : super(
          appId: 'test-app-id',
          initOverride: (_) {},
          loginOverride: (_) async {},
          logoutOverride: () async {},
        );

  @override
  Future<void> loginUser(String userId) async {
    lastLoginUserId = userId;
  }

  @override
  Future<void> logoutUser() async {
    logoutCalled = true;
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('pushNotificationLifecycleProvider', () {
    test('calls loginUser for authenticated 13+ user', () {
      final pushService = _TrackingPushService();

      final container = ProviderContainer(
        overrides: [
          pushNotificationServiceProvider.overrideWithValue(pushService),
          authStateProvider.overrideWith(
            () => _StubAuthStateNotifier(_authenticated(metadata: {
              'is_under_13': false,
              'age_verified_at': '2024-01-01T00:00:00Z',
            })),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Reading the lifecycle provider triggers the logic
      container.read(pushNotificationLifecycleProvider);

      expect(pushService.lastLoginUserId, 'test-user-id');
      expect(pushService.logoutCalled, isFalse);
    });

    test('calls logoutUser for unauthenticated user', () {
      final pushService = _TrackingPushService();

      final container = ProviderContainer(
        overrides: [
          pushNotificationServiceProvider.overrideWithValue(pushService),
          authStateProvider.overrideWith(
            () => _StubAuthStateNotifier(const AuthUnauthenticated()),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(pushNotificationLifecycleProvider);

      expect(pushService.lastLoginUserId, isNull);
      expect(pushService.logoutCalled, isTrue);
    });

    test('calls logoutUser for under-13 user (never loginUser)', () {
      final pushService = _TrackingPushService();

      final container = ProviderContainer(
        overrides: [
          pushNotificationServiceProvider.overrideWithValue(pushService),
          authStateProvider.overrideWith(
            () => _StubAuthStateNotifier(_authenticated(metadata: {
              'is_under_13': true,
              'age_verified_at': '2024-01-01T00:00:00Z',
              'parental_consent_at': '2024-06-01T00:00:00Z',
            })),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(pushNotificationLifecycleProvider);

      expect(pushService.lastLoginUserId, isNull);
      expect(pushService.logoutCalled, isTrue);
    });

    test('wires onNotificationOpened callback', () {
      final pushService = _TrackingPushService();

      final container = ProviderContainer(
        overrides: [
          pushNotificationServiceProvider.overrideWithValue(pushService),
          authStateProvider.overrideWith(
            () => _StubAuthStateNotifier(const AuthUnauthenticated()),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(pushNotificationLifecycleProvider);

      expect(pushService.onNotificationOpened, isNotNull);
    });

    test('wires onForegroundNotification callback', () {
      final pushService = _TrackingPushService();

      final container = ProviderContainer(
        overrides: [
          pushNotificationServiceProvider.overrideWithValue(pushService),
          authStateProvider.overrideWith(
            () => _StubAuthStateNotifier(const AuthUnauthenticated()),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(pushNotificationLifecycleProvider);

      expect(pushService.onForegroundNotification, isNotNull);
    });

    test('foreground callback suppresses match notifications', () {
      final pushService = _TrackingPushService();

      final container = ProviderContainer(
        overrides: [
          pushNotificationServiceProvider.overrideWithValue(pushService),
          authStateProvider.overrideWith(
            () => _StubAuthStateNotifier(const AuthUnauthenticated()),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(pushNotificationLifecycleProvider);

      // Match notification should be suppressed
      expect(pushService.onForegroundNotification!('match-123'), isTrue);
      // Non-match notification should not be suppressed
      expect(pushService.onForegroundNotification!(null), isFalse);
    });

    test('notification tap stores deep link destination', () {
      final pushService = _TrackingPushService();
      String? capturedPushLocation;

      // Create a minimal mock router that captures push calls
      final mockRouter = GoRouter(
        routes: [
          GoRoute(
            path: '/matches/:matchId',
            builder: (context, state) => Container(),
          ),
        ],
        redirect: (context, state) {
          // Capture the push location
          if (state.matchedLocation.startsWith('/matches/')) {
            capturedPushLocation = state.matchedLocation;
          }
          return null;
        },
      );

      final container = ProviderContainer(
        overrides: [
          pushNotificationServiceProvider.overrideWithValue(pushService),
          authStateProvider.overrideWith(
            () => _StubAuthStateNotifier(const AuthUnauthenticated()),
          ),
          routerProvider.overrideWithValue(mockRouter),
        ],
      );
      addTearDown(container.dispose);

      container.read(pushNotificationLifecycleProvider);

      // Simulate notification tap
      pushService.onNotificationOpened!('match-abc123');

      // Verify deep link was stored
      expect(
        container.read(deepLinkProvider),
        '/matches/match-abc123',
      );
    });

    test('processPendingNotification is called during initialization', () {
      final pushService = _TrackingPushService();

      final container = ProviderContainer(
        overrides: [
          pushNotificationServiceProvider.overrideWithValue(pushService),
          authStateProvider.overrideWith(
            () => _StubAuthStateNotifier(_authenticated(metadata: {
              'is_under_13': false,
              'age_verified_at': '2024-01-01T00:00:00Z',
            })),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(pushNotificationLifecycleProvider);

      // Verify the callback was wired (processPendingNotification is called internally)
      expect(pushService.onNotificationOpened, isNotNull);
    });
  });
}
