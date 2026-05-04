import 'package:flutter_app/features/stickers/data/models/sticker.dart';
import 'trade_history.dart';

/// Enriched trade history item with partner name and sticker details.
///
/// This combines raw TradeHistory data with resolved partner display names
/// and Sticker objects for UI rendering.
class TradeHistoryItem {
  final TradeHistory trade;
  final String partnerDisplayName;
  final List<Sticker> givenStickers;
  final List<Sticker> receivedStickers;

  const TradeHistoryItem({
    required this.trade,
    required this.partnerDisplayName,
    required this.givenStickers,
    required this.receivedStickers,
  });

  String get tradeId => trade.tradeId;
  DateTime get createdAt => trade.createdAt;
  String get status => trade.status;
}
