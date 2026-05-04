import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/matching/data/models/trade_history.dart';
import 'package:flutter_app/features/matching/data/models/trade_history_item.dart';
import 'package:flutter_app/features/stickers/data/models/sticker.dart';

void main() {
  group('TradeHistoryItem', () {
    late TradeHistory trade;
    late List<Sticker> givenStickers;
    late List<Sticker> receivedStickers;

    setUp(() {
      trade = TradeHistory(
        tradeId: 'trade-123',
        matchId: 'match-456',
        initiatorId: 'user-alice',
        responderId: 'user-bob',
        initiatorStickerIds: const [1, 2],
        responderStickerIds: const [3],
        status: 'COMPLETED',
        createdAt: DateTime(2026, 4, 15, 10, 30),
      );

      givenStickers = [
        const Sticker(
          id: 1,
          stickerNumber: 1,
          title: 'Lionel Messi',
          team: 'Argentina',
          page: 1,
          type: 'player',
          imageUrl: null,
        ),
        const Sticker(
          id: 2,
          stickerNumber: 2,
          title: 'Cristiano Ronaldo',
          team: 'Portugal',
          page: 1,
          type: 'player',
          imageUrl: null,
        ),
      ];

      receivedStickers = [
        const Sticker(
          id: 3,
          stickerNumber: 3,
          title: 'Neymar Jr',
          team: 'Brazil',
          page: 1,
          type: 'player',
          imageUrl: null,
        ),
      ];
    });

    test('constructs with all required fields', () {
      final item = TradeHistoryItem(
        trade: trade,
        partnerDisplayName: 'Bob Smith',
        givenStickers: givenStickers,
        receivedStickers: receivedStickers,
      );

      expect(item.trade, trade);
      expect(item.partnerDisplayName, 'Bob Smith');
      expect(item.givenStickers, givenStickers);
      expect(item.receivedStickers, receivedStickers);
    });

    test('tradeId getter returns trade.tradeId', () {
      final item = TradeHistoryItem(
        trade: trade,
        partnerDisplayName: 'Bob Smith',
        givenStickers: givenStickers,
        receivedStickers: receivedStickers,
      );

      expect(item.tradeId, 'trade-123');
    });

    test('createdAt getter returns trade.createdAt', () {
      final item = TradeHistoryItem(
        trade: trade,
        partnerDisplayName: 'Bob Smith',
        givenStickers: givenStickers,
        receivedStickers: receivedStickers,
      );

      expect(item.createdAt, DateTime(2026, 4, 15, 10, 30));
    });

    test('status getter returns trade.status', () {
      final item = TradeHistoryItem(
        trade: trade,
        partnerDisplayName: 'Bob Smith',
        givenStickers: givenStickers,
        receivedStickers: receivedStickers,
      );

      expect(item.status, 'COMPLETED');
    });
  });
}
