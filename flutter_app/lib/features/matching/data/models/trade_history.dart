/// Data model for a completed trade from the trade_audit_log table.
class TradeHistory {
  final String tradeId;
  final String matchId;
  final String initiatorId;
  final String responderId;
  final List<int> initiatorStickerIds;
  final List<int> responderStickerIds;
  final String status;
  final DateTime createdAt;

  const TradeHistory({
    required this.tradeId,
    required this.matchId,
    required this.initiatorId,
    required this.responderId,
    required this.initiatorStickerIds,
    required this.responderStickerIds,
    required this.status,
    required this.createdAt,
  });

  factory TradeHistory.fromJson(Map<String, dynamic> json) {
    return TradeHistory(
      tradeId: json['trade_id'] as String,
      matchId: json['match_id'] as String,
      initiatorId: json['initiator_id'] as String,
      responderId: json['responder_id'] as String,
      initiatorStickerIds: (json['initiator_sticker_ids'] as List<dynamic>)
          .map((e) => e as int)
          .toList(),
      responderStickerIds: (json['responder_sticker_ids'] as List<dynamic>)
          .map((e) => e as int)
          .toList(),
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Returns the other participant's ID (not the current user).
  String getPartnerIdFor(String currentUserId) {
    return currentUserId == initiatorId ? responderId : initiatorId;
  }

  /// Returns the stickers given by the current user.
  List<int> getGivenStickersFor(String currentUserId) {
    return currentUserId == initiatorId
        ? initiatorStickerIds
        : responderStickerIds;
  }

  /// Returns the stickers received by the current user.
  List<int> getReceivedStickersFor(String currentUserId) {
    return currentUserId == initiatorId
        ? responderStickerIds
        : initiatorStickerIds;
  }
}
