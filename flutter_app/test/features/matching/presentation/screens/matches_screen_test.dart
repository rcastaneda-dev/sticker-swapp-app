import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:flutter_app/core/services/location_service.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/matching/data/models/scored_match.dart';
import 'package:flutter_app/features/matching/data/models/swipe_result.dart';
import 'package:flutter_app/features/matching/data/providers/discovery_providers.dart';
import 'package:flutter_app/features/matching/data/providers/location_providers.dart';
import 'package:flutter_app/features/matching/data/providers/match_notification_providers.dart';
import 'package:flutter_app/features/matching/data/services/match_discovery_service.dart';
import 'package:flutter_app/features/matching/presentation/screens/matches_screen.dart';
import 'package:flutter_app/features/matching/presentation/widgets/trader_card_skeleton.dart';
import 'package:flutter_app/features/stickers/data/models/sticker.dart';
import 'package:flutter_app/features/stickers/data/providers/collection_progress_providers.dart';
import 'package:flutter_app/features/stickers/data/providers/user_inventory_providers.dart';
import 'package:flutter_app/features/stickers/data/services/user_inventory_service.dart';
import 'package:flutter_app/shared/shared.dart';

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

Position _fakePosition() => Position(
      latitude: 13.6929,
      longitude: -89.2182,
      timestamp: DateTime(2026, 3, 30),
      accuracy: 15,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

LocationService _fakeLocationService({
  LocationPermission checkResult = LocationPermission.whileInUse,
}) {
  return LocationService(
    isServiceEnabled: () async => true,
    checkPermission: () async => checkResult,
    requestPermission: () async => checkResult,
    getPosition: ({locationSettings}) async => _fakePosition(),
    openAppSettings: () async => true,
    openLocationSettings: () async => true,
  );
}

class _FakeMatchDiscoveryService extends MatchDiscoveryService {
  _FakeMatchDiscoveryService() : super(baseUrl: 'https://test');

  @override
  Future<MatchPage> fetchMatches({
    required double latitude,
    required double longitude,
    int radiusM = 5000,
    int offset = 0,
    int limit = 10,
  }) async {
    return const MatchPage(matches: [], totalCount: 0);
  }

  @override
  Future<SwipeResult> swipeRight(String targetUserId) async {
    return const SwipeResult(matched: false, swipeRecorded: true);
  }
}

/// Stub notifier that returns a pre-set DiscoveryState.
class _StubDiscoveryNotifier extends DiscoveryNotifier {
  final DiscoveryState _state;
  _StubDiscoveryNotifier(this._state);

  @override
  DiscoveryState build() => _state;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refresh() async {}

  @override
  void swipeLeft() {}

  @override
  Future<SwipeResult?> swipeRight() async => null;

  @override
  void clearLastSwipeResult() {}

  @override
  Future<void> loadMore() async {}
}

class _FakeUserInventoryService extends UserInventoryService {
  _FakeUserInventoryService() : super(client: null);

  @override
  Future<Set<int>> fetchOwnedStickerIds() async => {};

  @override
  Future<void> toggleSticker(int stickerId) async {}

  @override
  Future<String> createWishlistShare() async => 'test-token';
}

Widget _buildSubject({
  Map<String, dynamic>? metadata,
  DiscoveryState? discoveryState,
  List<UnviewedMatch>? unviewedMatches,
}) {
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(
        () => _StubAuthStateNotifier(_authenticated(metadata: metadata)),
      ),
      locationServiceProvider.overrideWithValue(_fakeLocationService()),
      matchDiscoveryServiceProvider
          .overrideWithValue(_FakeMatchDiscoveryService()),
      // Provide sticker data for the Under13WishlistView
      userInventoryServiceProvider
          .overrideWithValue(_FakeUserInventoryService()),
      allStickersProvider.overrideWith(
        (ref) => Future.value(const [
          Sticker(id: 1, stickerNumber: 1, title: 'S1', team: 'Argentina', page: 1, type: 'player'),
          Sticker(id: 2, stickerNumber: 2, title: 'S2', team: 'Brazil', page: 2, type: 'player'),
        ]),
      ),
      if (discoveryState != null)
        discoveryProvider
            .overrideWith(() => _StubDiscoveryNotifier(discoveryState)),
      if (unviewedMatches != null)
        matchNotificationProvider.overrideWith(
          () => _StubMatchNotificationNotifier(unviewedMatches),
        ),
    ],
    child: MaterialApp(
      theme: SwappTheme.light,
      home: const MatchesScreen(),
    ),
  );
}

class _StubMatchNotificationNotifier extends MatchNotificationNotifier {
  final List<UnviewedMatch> _initial;
  _StubMatchNotificationNotifier(this._initial);

  @override
  List<UnviewedMatch> build() => _initial;
}

ScoredMatch _match({String id = 'u1', String name = 'Test User'}) =>
    ScoredMatch(
      userId: id,
      displayName: name,
      distanceM: 500,
      duplicateCount: 10,
      neededCount: 5,
      theyHaveINeed: 3,
      iHaveTheyNeed: 2,
      proximityScore: 0.9,
      reciprocalScore: 0.5,
      activityScore: 0.8,
      totalScore: 0.76,
    );

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('MatchesScreen', () {
    testWidgets('shows wishlist view when user is under 13',
        (tester) async {
      await tester.pumpWidget(_buildSubject(metadata: {
        'is_under_13': true,
        'age_verified_at': '2024-01-01T00:00:00Z',
        'parental_consent_at': '2024-06-01T00:00:00Z',
      }));
      await tester.pumpAndSettle();

      expect(find.text('My Wishlist'), findsWidgets);
      expect(find.text('Share Wishlist'), findsOneWidget);
    });

    testWidgets('13+ user sees location loading state initially',
        (tester) async {
      await tester.pumpWidget(_buildSubject(metadata: {
        'is_under_13': false,
        'age_verified_at': '2024-01-01T00:00:00Z',
      }));

      expect(find.text('Trading Unlocks Later'), findsNothing);
      expect(find.text('Getting your location...'), findsOneWidget);
    });

    testWidgets('shows skeleton cards during loading state', (tester) async {
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': false,
          'age_verified_at': '2024-01-01T00:00:00Z',
        },
        discoveryState: const DiscoveryState(status: DiscoveryStatus.loading),
      ));
      await tester.pump();

      expect(find.byType(TraderCardSkeleton), findsWidgets);
    });

    testWidgets('shows card stack when discovery state is ready',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': false,
          'age_verified_at': '2024-01-01T00:00:00Z',
        },
        discoveryState: DiscoveryState(
          status: DiscoveryStatus.ready,
          matches: [_match(id: 'u1', name: 'Carlos'), _match(id: 'u2')],
          currentIndex: 0,
          totalCount: 2,
        ),
      ));
      await tester.pump();

      expect(find.text('Carlos'), findsOneWidget);
      expect(find.text('2 traders nearby'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('shows totalCount in header instead of remainingCount',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': false,
          'age_verified_at': '2024-01-01T00:00:00Z',
        },
        discoveryState: DiscoveryState(
          status: DiscoveryStatus.ready,
          matches: [_match(id: 'u1'), _match(id: 'u2')],
          currentIndex: 0,
          totalCount: 25,
        ),
      ));
      await tester.pump();

      expect(find.text('25 traders nearby'), findsOneWidget);
    });

    testWidgets('shows empty state when no traders nearby', (tester) async {
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': false,
          'age_verified_at': '2024-01-01T00:00:00Z',
        },
        discoveryState: const DiscoveryState(status: DiscoveryStatus.empty),
      ));
      await tester.pump();

      expect(find.text('No Traders Nearby'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
    });

    testWidgets('shows error state with retry button', (tester) async {
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': false,
          'age_verified_at': '2024-01-01T00:00:00Z',
        },
        discoveryState: const DiscoveryState(
          status: DiscoveryStatus.error,
          errorMessage: 'Network error',
        ),
      ));
      await tester.pump();

      expect(find.text('Oops!'), findsOneWidget);
      expect(find.text('Network error'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('treats null is_under_13 as non-restricted', (tester) async {
      await tester.pumpWidget(_buildSubject(metadata: {
        'age_verified_at': '2024-01-01T00:00:00Z',
      }));

      expect(find.text('Trading Unlocks Later'), findsNothing);
      expect(find.text('Getting your location...'), findsOneWidget);
    });

    testWidgets('shows spinner when ready but currentMatch is null',
        (tester) async {
      // This happens when all loaded cards are swiped but hasMore is true
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': false,
          'age_verified_at': '2024-01-01T00:00:00Z',
        },
        discoveryState: DiscoveryState(
          status: DiscoveryStatus.ready,
          matches: [_match(id: 'u1')],
          currentIndex: 1, // Past last match
          hasMore: true,
          isLoadingMore: true,
        ),
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('has RefreshIndicator wrapping the body', (tester) async {
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': false,
          'age_verified_at': '2024-01-01T00:00:00Z',
        },
        discoveryState: const DiscoveryState(status: DiscoveryStatus.empty),
      ));
      await tester.pump();

      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('shows badge with count when unviewed matches exist',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': false,
          'age_verified_at': '2024-01-01T00:00:00Z',
        },
        discoveryState: const DiscoveryState(status: DiscoveryStatus.empty),
        unviewedMatches: const [
          UnviewedMatch(matchId: 'm1', displayName: 'Carlos'),
          UnviewedMatch(matchId: 'm2', displayName: 'Diego'),
        ],
      ));
      await tester.pump();

      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      expect(find.byType(Badge), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('badge icon present but disabled when no unviewed matches',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': false,
          'age_verified_at': '2024-01-01T00:00:00Z',
        },
        discoveryState: const DiscoveryState(status: DiscoveryStatus.empty),
        unviewedMatches: const [],
      ));
      await tester.pump();

      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      final iconButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chat_bubble_outline),
      );
      expect(iconButton.onPressed, isNull);
    });

    testWidgets('badge icon hidden for under-13 users', (tester) async {
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': true,
          'age_verified_at': '2024-01-01T00:00:00Z',
          'parental_consent_at': '2024-06-01T00:00:00Z',
        },
        unviewedMatches: const [
          UnviewedMatch(matchId: 'm1', displayName: 'Carlos'),
        ],
      ));

      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
    });

    testWidgets(
        'shows SnackBar when Keep Swiping tapped on match celebration',
        (tester) async {
      await tester.pumpWidget(_buildSubject(
        metadata: {
          'is_under_13': false,
          'age_verified_at': '2024-01-01T00:00:00Z',
        },
        discoveryState: DiscoveryState(
          status: DiscoveryStatus.ready,
          matches: [_match(id: 'u1', name: 'Carlos')],
          currentIndex: 0,
          totalCount: 1,
          lastSwipeResult: SwipeResult(
            matched: true,
            swipeRecorded: true,
            matchId: 'match-123',
            user1Id: 'test-user-id',
            user2Id: 'u1',
            status: 'PENDING',
            createdAt: DateTime(2026, 3, 30),
          ),
        ),
      ));
      await tester.pump();

      // Celebration overlay should be visible
      expect(find.text("It's a Match!"), findsOneWidget);

      // Tap "Keep Swiping"
      await tester.tap(find.text('Keep Swiping'));
      await tester.pump();

      // SnackBar should appear
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('View'), findsOneWidget);
    });
  });
}
