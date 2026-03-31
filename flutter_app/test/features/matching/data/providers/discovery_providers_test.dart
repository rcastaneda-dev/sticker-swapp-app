import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:flutter_app/core/services/location_service.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/matching/data/models/scored_match.dart';
import 'package:flutter_app/features/matching/data/models/swipe_result.dart';
import 'package:flutter_app/features/matching/data/providers/discovery_providers.dart';
import 'package:flutter_app/features/matching/data/providers/location_providers.dart';
import 'package:flutter_app/features/matching/data/services/match_discovery_service.dart';

// ── Helpers ───────────────────────────────────────────────────────────────

class _StubAuthStateNotifier extends AuthStateNotifier {
  final AppAuthState _initial;
  _StubAuthStateNotifier(this._initial);

  @override
  AppAuthState build() => _initial;
}

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

ScoredMatch _match({String id = 'u1', String name = 'Test'}) => ScoredMatch(
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

// ── Stub LocationNotifier ────────────────────────────────────────────────

class _StubLocationNotifier extends LocationNotifier {
  final LocationPermissionStatus? _permissionResult;

  _StubLocationNotifier({LocationPermissionStatus? permissionResult})
      : _permissionResult = permissionResult;

  @override
  Future<LocationUpdateResult?> build() async {
    if (_permissionResult == null) {
      return LocationUpdateResult.success(
        latitude: 13.6929,
        longitude: -89.2182,
        accuracyMeters: 15,
      );
    }
    return null;
  }

  @override
  Future<LocationPermissionStatus?> requestAndUpdate() async {
    if (_permissionResult != null) {
      return _permissionResult;
    }
    state = AsyncData(LocationUpdateResult.success(
      latitude: 13.6929,
      longitude: -89.2182,
      accuracyMeters: 15,
    ));
    return null;
  }
}

// ── Fake MatchDiscoveryService ───────────────────────────────────────────

class _FakeMatchDiscoveryService extends MatchDiscoveryService {
  List<ScoredMatch> matchesToReturn;
  int totalCountToReturn;
  SwipeResult swipeResultToReturn;
  bool shouldThrow;
  int fetchCallCount = 0;
  int? lastOffset;
  int? lastLimit;

  _FakeMatchDiscoveryService({
    this.matchesToReturn = const [],
    this.totalCountToReturn = 0,
    SwipeResult? swipeResult,
    this.shouldThrow = false,
  })  : swipeResultToReturn = swipeResult ??
            const SwipeResult(matched: false, swipeRecorded: true),
        super(baseUrl: 'https://test');

  @override
  Future<MatchPage> fetchMatches({
    required double latitude,
    required double longitude,
    int radiusM = 5000,
    int offset = 0,
    int limit = 10,
  }) async {
    fetchCallCount++;
    lastOffset = offset;
    lastLimit = limit;
    if (shouldThrow) {
      throw const MatchDiscoveryException('error', statusCode: 500);
    }
    // Simulate pagination: slice matchesToReturn based on offset/limit.
    final start = offset.clamp(0, matchesToReturn.length);
    final end = (offset + limit).clamp(0, matchesToReturn.length);
    final page = matchesToReturn.sublist(start, end);
    return MatchPage(
      matches: page,
      totalCount: totalCountToReturn > 0
          ? totalCountToReturn
          : matchesToReturn.length,
    );
  }

  @override
  Future<SwipeResult> swipeRight(String targetUserId) async {
    if (shouldThrow) {
      throw const MatchDiscoveryException('error', statusCode: 500);
    }
    return swipeResultToReturn;
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('DiscoveryNotifier', () {
    late ProviderContainer container;
    late _FakeMatchDiscoveryService fakeService;

    ProviderContainer createContainer({
      List<ScoredMatch>? matches,
      int? totalCount,
      SwipeResult? swipeResult,
      bool serviceThrows = false,
      LocationPermissionStatus? locationResult,
    }) {
      fakeService = _FakeMatchDiscoveryService(
        matchesToReturn: matches ?? [],
        totalCountToReturn: totalCount ?? 0,
        swipeResult: swipeResult,
        shouldThrow: serviceThrows,
      );

      return ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            () => _StubAuthStateNotifier(
              _authenticated(metadata: {
                'is_under_13': false,
                'age_verified_at': '2024-01-01T00:00:00Z',
              }),
            ),
          ),
          locationNotifierProvider.overrideWith(
            () => _StubLocationNotifier(permissionResult: locationResult),
          ),
          matchDiscoveryServiceProvider.overrideWithValue(fakeService),
        ],
      );
    }

    tearDown(() => container.dispose());

    test('initial state is awaitingLocation', () {
      container = createContainer();
      final state = container.read(discoveryProvider);
      expect(state.status, DiscoveryStatus.awaitingLocation);
    });

    test('initialize transitions to ready when matches found', () async {
      container = createContainer(
        matches: [_match(id: 'u1'), _match(id: 'u2')],
      );

      await container.read(discoveryProvider.notifier).initialize();

      final state = container.read(discoveryProvider);
      expect(state.status, DiscoveryStatus.ready);
      expect(state.matches, hasLength(2));
      expect(state.currentIndex, 0);
      expect(state.currentMatch!.userId, 'u1');
    });

    test('initialize transitions to empty when no matches', () async {
      container = createContainer(matches: []);

      await container.read(discoveryProvider.notifier).initialize();

      final state = container.read(discoveryProvider);
      expect(state.status, DiscoveryStatus.empty);
    });

    test('initialize transitions to error on permission denied', () async {
      container = createContainer(
        locationResult: LocationPermissionStatus.denied,
      );

      await container.read(discoveryProvider.notifier).initialize();

      final state = container.read(discoveryProvider);
      expect(state.status, DiscoveryStatus.error);
      expect(state.errorMessage, isNotNull);
    });

    test('initialize transitions to error on service failure', () async {
      container = createContainer(
        matches: [],
        serviceThrows: true,
      );

      await container.read(discoveryProvider.notifier).initialize();

      final state = container.read(discoveryProvider);
      expect(state.status, DiscoveryStatus.error);
    });

    test('swipeRight advances card and sets lastSwipeResult', () async {
      container = createContainer(
        matches: [_match(id: 'u1'), _match(id: 'u2')],
        swipeResult: const SwipeResult(matched: false, swipeRecorded: true),
      );

      await container.read(discoveryProvider.notifier).initialize();
      final result =
          await container.read(discoveryProvider.notifier).swipeRight();

      final state = container.read(discoveryProvider);
      expect(state.currentIndex, 1);
      expect(state.currentMatch!.userId, 'u2');
      expect(result, isNotNull);
      expect(result!.matched, isFalse);
    });

    test('swipeRight with mutual match sets matched result', () async {
      container = createContainer(
        matches: [_match(id: 'u1'), _match(id: 'u2')],
        swipeResult: const SwipeResult(
          matched: true,
          matchId: 'match-1',
          status: 'PENDING',
        ),
      );

      await container.read(discoveryProvider.notifier).initialize();
      final result =
          await container.read(discoveryProvider.notifier).swipeRight();

      expect(result!.matched, isTrue);
      expect(result.matchId, 'match-1');

      final state = container.read(discoveryProvider);
      expect(state.lastSwipeResult?.matched, isTrue);
    });

    test('swipeLeft advances card without API call', () async {
      container = createContainer(
        matches: [_match(id: 'u1'), _match(id: 'u2')],
      );

      await container.read(discoveryProvider.notifier).initialize();
      container.read(discoveryProvider.notifier).swipeLeft();

      final state = container.read(discoveryProvider);
      expect(state.currentIndex, 1);
      expect(state.currentMatch!.userId, 'u2');
    });

    test('last card swiped transitions to empty when no more pages',
        () async {
      container = createContainer(matches: [_match(id: 'u1')]);

      await container.read(discoveryProvider.notifier).initialize();
      container.read(discoveryProvider.notifier).swipeLeft();

      final state = container.read(discoveryProvider);
      expect(state.status, DiscoveryStatus.empty);
      expect(state.currentMatch, isNull);
    });

    test('clearLastSwipeResult removes the result', () async {
      container = createContainer(
        matches: [_match(id: 'u1'), _match(id: 'u2')],
        swipeResult: const SwipeResult(matched: true, matchId: 'match-1'),
      );

      await container.read(discoveryProvider.notifier).initialize();
      await container.read(discoveryProvider.notifier).swipeRight();
      expect(
        container.read(discoveryProvider).lastSwipeResult?.matched,
        isTrue,
      );

      container.read(discoveryProvider.notifier).clearLastSwipeResult();
      expect(container.read(discoveryProvider).lastSwipeResult, isNull);
    });

    test('upcomingMatches returns next 1-2 cards', () async {
      container = createContainer(
        matches: [
          _match(id: 'u1'),
          _match(id: 'u2'),
          _match(id: 'u3'),
        ],
      );

      await container.read(discoveryProvider.notifier).initialize();

      final state = container.read(discoveryProvider);
      expect(state.upcomingMatches, hasLength(2));
      expect(state.upcomingMatches[0].userId, 'u2');
      expect(state.upcomingMatches[1].userId, 'u3');
    });

    test('remainingCount is correct', () async {
      container = createContainer(
        matches: [_match(id: 'u1'), _match(id: 'u2'), _match(id: 'u3')],
      );

      await container.read(discoveryProvider.notifier).initialize();
      expect(container.read(discoveryProvider).remainingCount, 3);

      container.read(discoveryProvider.notifier).swipeLeft();
      expect(container.read(discoveryProvider).remainingCount, 2);
    });

    // ── Pagination tests ──────────────────────────────────────────────────

    test('initialize sets hasMore when totalCount > page size', () async {
      container = createContainer(
        matches: List.generate(
          15,
          (i) => _match(id: 'u$i', name: 'User $i'),
        ),
        totalCount: 15,
      );

      await container.read(discoveryProvider.notifier).initialize();

      final state = container.read(discoveryProvider);
      expect(state.status, DiscoveryStatus.ready);
      expect(state.matches, hasLength(10));
      expect(state.hasMore, isTrue);
      expect(state.totalCount, 15);
    });

    test('initialize passes offset 0 to service', () async {
      container = createContainer(
        matches: [_match(id: 'u1')],
      );

      await container.read(discoveryProvider.notifier).initialize();

      expect(fakeService.lastOffset, 0);
    });

    test('loadMore appends next page of matches', () async {
      container = createContainer(
        matches: List.generate(
          15,
          (i) => _match(id: 'u$i', name: 'User $i'),
        ),
        totalCount: 15,
      );

      await container.read(discoveryProvider.notifier).initialize();
      expect(container.read(discoveryProvider).matches, hasLength(10));

      await container.read(discoveryProvider.notifier).loadMore();

      final state = container.read(discoveryProvider);
      expect(state.matches, hasLength(15));
      expect(state.hasMore, isFalse);
    });

    test('loadMore does nothing when hasMore is false', () async {
      container = createContainer(
        matches: [_match(id: 'u1')],
      );

      await container.read(discoveryProvider.notifier).initialize();
      final callsBefore = fakeService.fetchCallCount;

      await container.read(discoveryProvider.notifier).loadMore();

      expect(fakeService.fetchCallCount, callsBefore);
    });

    test('loadMore does nothing when already loading', () async {
      container = createContainer(
        matches: List.generate(
          15,
          (i) => _match(id: 'u$i', name: 'User $i'),
        ),
        totalCount: 15,
      );

      await container.read(discoveryProvider.notifier).initialize();

      final future1 = container.read(discoveryProvider.notifier).loadMore();
      final callsDuringFirst = fakeService.fetchCallCount;
      final future2 = container.read(discoveryProvider.notifier).loadMore();

      await Future.wait([future1, future2]);

      expect(fakeService.fetchCallCount, callsDuringFirst);
    });

    test('loadMore failure does not crash, sets isLoadingMore false',
        () async {
      container = createContainer(
        matches: List.generate(
          15,
          (i) => _match(id: 'u$i', name: 'User $i'),
        ),
        totalCount: 15,
      );

      await container.read(discoveryProvider.notifier).initialize();
      expect(container.read(discoveryProvider).hasMore, isTrue);

      fakeService.shouldThrow = true;

      await container.read(discoveryProvider.notifier).loadMore();

      final state = container.read(discoveryProvider);
      expect(state.status, DiscoveryStatus.ready);
      expect(state.isLoadingMore, isFalse);
    });

    test('swiping near end triggers prefetch', () async {
      final allMatches = List.generate(
        20,
        (i) => _match(id: 'u$i', name: 'User $i'),
      );
      container = createContainer(
        matches: allMatches,
        totalCount: 20,
      );

      await container.read(discoveryProvider.notifier).initialize();
      final callsAfterInit = fakeService.fetchCallCount;

      final notifier = container.read(discoveryProvider.notifier);
      for (int i = 0; i < 7; i++) {
        notifier.swipeLeft();
      }

      final state = container.read(discoveryProvider);
      expect(state.currentIndex, 7);
      expect(fakeService.fetchCallCount, greaterThan(callsAfterInit));
    });

    test('totalCount reflects server total in state', () async {
      container = createContainer(
        matches: [_match(id: 'u1'), _match(id: 'u2')],
        totalCount: 25,
      );

      await container.read(discoveryProvider.notifier).initialize();

      expect(container.read(discoveryProvider).totalCount, 25);
    });
  });
}
