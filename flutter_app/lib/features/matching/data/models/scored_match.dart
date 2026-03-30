/// A scored match candidate returned by the Go matchmaking engine.
///
/// Maps the JSON response from `GET /api/v1/matches`.
class ScoredMatch {
  final String userId;
  final String displayName;
  final double distanceM;
  final int duplicateCount;
  final int neededCount;
  final int theyHaveINeed;
  final int iHaveTheyNeed;
  final double proximityScore;
  final double reciprocalScore;
  final double activityScore;
  final double totalScore;

  const ScoredMatch({
    required this.userId,
    required this.displayName,
    required this.distanceM,
    required this.duplicateCount,
    required this.neededCount,
    required this.theyHaveINeed,
    required this.iHaveTheyNeed,
    required this.proximityScore,
    required this.reciprocalScore,
    required this.activityScore,
    required this.totalScore,
  });

  factory ScoredMatch.fromJson(Map<String, dynamic> json) {
    return ScoredMatch(
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String,
      distanceM: (json['distance_m'] as num).toDouble(),
      duplicateCount: (json['duplicate_count'] as num).toInt(),
      neededCount: (json['needed_count'] as num).toInt(),
      theyHaveINeed: (json['they_have_i_need'] as num).toInt(),
      iHaveTheyNeed: (json['i_have_they_need'] as num).toInt(),
      proximityScore: (json['proximity_score'] as num).toDouble(),
      reciprocalScore: (json['reciprocal_score'] as num).toDouble(),
      activityScore: (json['activity_score'] as num).toDouble(),
      totalScore: (json['total_score'] as num).toDouble(),
    );
  }

  /// Human-readable distance: "1.2 km" for ≥1000 m, "500 m" otherwise.
  String get formattedDistance {
    if (distanceM >= 1000) {
      return '${(distanceM / 1000).toStringAsFixed(1)} km';
    }
    return '${distanceM.round()} m';
  }
}
