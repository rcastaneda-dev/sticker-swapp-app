import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_app/features/stickers/data/models/sticker.dart';
import '../models/trade_history.dart';
import '../models/trade_history_item.dart';

/// Service for fetching trade history from Supabase.
///
/// Queries the trade_audit_log table and enriches results with partner names
/// and sticker details for UI rendering.
class TradeHistoryService {
  final SupabaseClient _client;

  TradeHistoryService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  /// Fetch all completed trades for the current authenticated user.
  ///
  /// Returns enriched [TradeHistoryItem] objects with partner display names
  /// and full sticker details. Trades are ordered by created_at descending
  /// (most recent first).
  ///
  /// Throws if the user is not authenticated.
  Future<List<TradeHistoryItem>> fetchTradeHistory() async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }

    // 1. Fetch all trades where current user is a participant
    final tradesResponse = await _client
        .from('trade_audit_log')
        .select()
        .or('initiator_id.eq.$currentUserId,responder_id.eq.$currentUserId')
        .order('created_at', ascending: false);

    final trades = (tradesResponse as List)
        .map((row) => TradeHistory.fromJson(row))
        .toList();

    if (trades.isEmpty) {
      return [];
    }

    // 2. Collect unique user IDs (partners)
    final partnerIds = trades
        .map((t) => t.getPartnerIdFor(currentUserId))
        .toSet()
        .toList();

    // 3. Fetch user profiles for all partners
    final profilesResponse = await _client
        .from('user_profiles')
        .select('user_id, display_name')
        .inFilter('user_id', partnerIds);

    final profilesMap = <String, String>{};
    for (final row in profilesResponse as List) {
      profilesMap[row['user_id'] as String] =
          row['display_name'] as String? ?? 'Unknown User';
    }

    // 4. Collect unique sticker IDs from all trades
    final stickerIds = <int>{};
    for (final trade in trades) {
      stickerIds.addAll(trade.initiatorStickerIds);
      stickerIds.addAll(trade.responderStickerIds);
    }

    // 5. Fetch all stickers in a single query
    final stickersResponse = await _client
        .from('stickers')
        .select()
        .inFilter('id', stickerIds.toList());

    final stickersMap = <int, Sticker>{};
    for (final row in stickersResponse as List) {
      final sticker = Sticker.fromJson(row);
      stickersMap[sticker.id] = sticker;
    }

    // 6. Build enriched TradeHistoryItem objects
    return trades.map((trade) {
      final partnerId = trade.getPartnerIdFor(currentUserId);
      final partnerName = profilesMap[partnerId] ?? 'Unknown User';

      final givenStickerIds = trade.getGivenStickersFor(currentUserId);
      final receivedStickerIds = trade.getReceivedStickersFor(currentUserId);

      final givenStickers = givenStickerIds
          .map((id) => stickersMap[id])
          .whereType<Sticker>()
          .toList();

      final receivedStickers = receivedStickerIds
          .map((id) => stickersMap[id])
          .whereType<Sticker>()
          .toList();

      return TradeHistoryItem(
        trade: trade,
        partnerDisplayName: partnerName,
        givenStickers: givenStickers,
        receivedStickers: receivedStickers,
      );
    }).toList();
  }
}
