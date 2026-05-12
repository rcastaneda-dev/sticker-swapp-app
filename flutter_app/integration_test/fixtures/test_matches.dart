import 'package:flutter_app/features/matching/data/models/scored_match.dart';
import 'package:flutter_app/features/matching/data/models/swipe_result.dart';

/// A canned match candidate for the swipe card stack.
ScoredMatch testMatch({
  String id = 'match-user-1',
  String name = 'Carlos',
  double distance = 500,
}) =>
    ScoredMatch(
      userId: id,
      displayName: name,
      distanceM: distance,
      duplicateCount: 15,
      neededCount: 20,
      theyHaveINeed: 5,
      iHaveTheyNeed: 3,
      proximityScore: 0.9,
      reciprocalScore: 0.6,
      activityScore: 0.8,
      totalScore: 0.78,
    );

/// A second match candidate.
ScoredMatch secondTestMatch() => testMatch(
      id: 'match-user-2',
      name: 'Maria',
      distance: 1200,
    );

/// Swipe result when a mutual match is created.
final mutualMatchResult = SwipeResult(
  matched: true,
  swipeRecorded: true,
  matchId: 'test-match-1',
  user1Id: 'test-user-id',
  user2Id: 'match-user-1',
  status: 'PENDING',
  createdAt: DateTime(2026, 5, 8),
);

/// Swipe result when only a one-sided swipe is recorded.
const oneSidedSwipeResult = SwipeResult(
  matched: false,
  swipeRecorded: true,
);
