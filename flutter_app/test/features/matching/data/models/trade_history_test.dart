import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/matching/data/models/trade_history.dart';

void main() {
  group('TradeHistory', () {
    test('fromJson parses complete trade record', () {
      final json = <String, dynamic>{
        'trade_id': '11111111-1111-1111-1111-111111111111',
        'match_id': '22222222-2222-2222-2222-222222222222',
        'initiator_id': 'aaaa-aaaa',
        'responder_id': 'bbbb-bbbb',
        'initiator_sticker_ids': [1, 5, 10],
        'responder_sticker_ids': [2, 7],
        'status': 'COMPLETED',
        'created_at': '2026-04-15T10:30:00.000Z',
      };

      final trade = TradeHistory.fromJson(json);

      expect(trade.tradeId, '11111111-1111-1111-1111-111111111111');
      expect(trade.matchId, '22222222-2222-2222-2222-222222222222');
      expect(trade.initiatorId, 'aaaa-aaaa');
      expect(trade.responderId, 'bbbb-bbbb');
      expect(trade.initiatorStickerIds, [1, 5, 10]);
      expect(trade.responderStickerIds, [2, 7]);
      expect(trade.status, 'COMPLETED');
      expect(trade.createdAt, isA<DateTime>());
      expect(trade.createdAt.year, 2026);
      expect(trade.createdAt.month, 4);
      expect(trade.createdAt.day, 15);
    });

    test('getPartnerIdFor returns responder ID when user is initiator', () {
      final trade = TradeHistory(
        tradeId: 'trade-1',
        matchId: 'match-1',
        initiatorId: 'user-alice',
        responderId: 'user-bob',
        initiatorStickerIds: const [1, 2],
        responderStickerIds: const [3, 4],
        status: 'COMPLETED',
        createdAt: DateTime.now(),
      );

      expect(trade.getPartnerIdFor('user-alice'), 'user-bob');
    });

    test('getPartnerIdFor returns initiator ID when user is responder', () {
      final trade = TradeHistory(
        tradeId: 'trade-1',
        matchId: 'match-1',
        initiatorId: 'user-alice',
        responderId: 'user-bob',
        initiatorStickerIds: const [1, 2],
        responderStickerIds: const [3, 4],
        status: 'COMPLETED',
        createdAt: DateTime.now(),
      );

      expect(trade.getPartnerIdFor('user-bob'), 'user-alice');
    });

    test('getGivenStickersFor returns initiator stickers when user is initiator',
        () {
      final trade = TradeHistory(
        tradeId: 'trade-1',
        matchId: 'match-1',
        initiatorId: 'user-alice',
        responderId: 'user-bob',
        initiatorStickerIds: const [1, 2, 3],
        responderStickerIds: const [4, 5],
        status: 'COMPLETED',
        createdAt: DateTime.now(),
      );

      expect(trade.getGivenStickersFor('user-alice'), [1, 2, 3]);
    });

    test('getGivenStickersFor returns responder stickers when user is responder',
        () {
      final trade = TradeHistory(
        tradeId: 'trade-1',
        matchId: 'match-1',
        initiatorId: 'user-alice',
        responderId: 'user-bob',
        initiatorStickerIds: const [1, 2, 3],
        responderStickerIds: const [4, 5],
        status: 'COMPLETED',
        createdAt: DateTime.now(),
      );

      expect(trade.getGivenStickersFor('user-bob'), [4, 5]);
    });

    test(
        'getReceivedStickersFor returns responder stickers when user is initiator',
        () {
      final trade = TradeHistory(
        tradeId: 'trade-1',
        matchId: 'match-1',
        initiatorId: 'user-alice',
        responderId: 'user-bob',
        initiatorStickerIds: const [1, 2, 3],
        responderStickerIds: const [4, 5],
        status: 'COMPLETED',
        createdAt: DateTime.now(),
      );

      expect(trade.getReceivedStickersFor('user-alice'), [4, 5]);
    });

    test(
        'getReceivedStickersFor returns initiator stickers when user is responder',
        () {
      final trade = TradeHistory(
        tradeId: 'trade-1',
        matchId: 'match-1',
        initiatorId: 'user-alice',
        responderId: 'user-bob',
        initiatorStickerIds: const [1, 2, 3],
        responderStickerIds: const [4, 5],
        status: 'COMPLETED',
        createdAt: DateTime.now(),
      );

      expect(trade.getReceivedStickersFor('user-bob'), [1, 2, 3]);
    });
  });
}
