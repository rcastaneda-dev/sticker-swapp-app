import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/trade_history_item.dart';
import '../services/trade_history_service.dart';

/// Provider for the TradeHistoryService singleton.
final tradeHistoryServiceProvider = Provider<TradeHistoryService>((ref) {
  return TradeHistoryService();
});

/// Fetches all completed trades for the current authenticated user.
///
/// Returns enriched [TradeHistoryItem] objects ordered by date descending
/// (most recent first). Automatically refetches when auth state changes.
final tradeHistoryListProvider = FutureProvider<List<TradeHistoryItem>>((ref) {
  final service = ref.watch(tradeHistoryServiceProvider);
  return service.fetchTradeHistory();
});
