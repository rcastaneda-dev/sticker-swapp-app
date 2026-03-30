/// Result of a right-swipe action from `POST /api/v1/matches`.
///
/// When [matched] is `true`, a mutual match was created and [matchId],
/// [user1Id], [user2Id], [status], and [createdAt] are populated.
/// When `false`, only [swipeRecorded] is meaningful.
class SwipeResult {
  final bool matched;
  final bool swipeRecorded;
  final String? matchId;
  final String? user1Id;
  final String? user2Id;
  final String? status;
  final DateTime? createdAt;

  const SwipeResult({
    required this.matched,
    this.swipeRecorded = false,
    this.matchId,
    this.user1Id,
    this.user2Id,
    this.status,
    this.createdAt,
  });

  factory SwipeResult.fromJson(Map<String, dynamic> json) {
    return SwipeResult(
      matched: json['matched'] as bool,
      swipeRecorded: json['swipe_recorded'] as bool? ?? false,
      matchId: json['match_id'] as String?,
      user1Id: json['user1_id'] as String?,
      user2Id: json['user2_id'] as String?,
      status: json['status'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}
