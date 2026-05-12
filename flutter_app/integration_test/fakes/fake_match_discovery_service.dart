import 'package:flutter_app/features/matching/data/models/swipe_result.dart';
import 'package:flutter_app/features/matching/data/services/match_discovery_service.dart';

import '../fixtures/test_matches.dart';

/// Controllable match discovery service for integration tests.
class FakeMatchDiscoveryService extends MatchDiscoveryService {
  /// The match page returned by [fetchMatches].
  MatchPage matchPage;

  /// The result returned by [swipeRight].
  SwipeResult swipeResult;

  bool fetchMatchesCalled = false;
  bool swipeRightCalled = false;
  String? lastSwipedUserId;

  FakeMatchDiscoveryService({
    MatchPage? matchPage,
    SwipeResult? swipeResult,
  })  : matchPage = matchPage ??
            MatchPage(
              matches: [testMatch(), secondTestMatch()],
              totalCount: 2,
            ),
        swipeResult = swipeResult ?? mutualMatchResult,
        super(baseUrl: 'https://fake-go-service');

  @override
  Future<MatchPage> fetchMatches({
    required double latitude,
    required double longitude,
    int radiusM = 5000,
    int offset = 0,
    int limit = 10,
  }) async {
    fetchMatchesCalled = true;
    return matchPage;
  }

  @override
  Future<SwipeResult> swipeRight(String targetUserId) async {
    swipeRightCalled = true;
    lastSwipedUserId = targetUserId;
    return swipeResult;
  }
}
