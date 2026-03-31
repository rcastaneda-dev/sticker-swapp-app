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
import 'package:flutter_app/features/matching/data/services/match_discovery_service.dart';
import 'package:flutter_app/features/matching/presentation/screens/matches_screen.dart';
import 'package:flutter_app/features/matching/presentation/widgets/trader_card_skeleton.dart';
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

Widget _buildSubject({
  Map<String, dynamic>? metadata,
  DiscoveryState? discoveryState,
}) {
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(
        () => _StubAuthStateNotifier(_authenticated(metadata: metadata)),
      ),
      locationServiceProvider.overrideWithValue(_fakeLocationService()),
      matchDiscoveryServiceProvider
          .overrideWithValue(_FakeMatchDiscoveryService()),
      if (discoveryState != null)
        discoveryProvider
            .overrideWith(() => _StubDiscoveryNotifier(discoveryState)),
    ],
    child: MaterialApp(
      theme: SwappTheme.light,
      home: const MatchesScreen(),
    ),
  );
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
    testWidgets('shows trading empty state when user is under 13',
        (tester) async {
      await tester.pumpWidget(_buildSubject(metadata: {
        'is_under_13': true,
        'age_verified_at': '2024-01-01T00:00:00Z',
        'parental_consent_at': '2024-06-01T00:00:00Z',
      }));

      expect(find.text('Trading Unlocks Later'), findsOneWidget);
      expect(find.text('Browse Stickers'), findsOneWidget);
      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
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
  });
}
