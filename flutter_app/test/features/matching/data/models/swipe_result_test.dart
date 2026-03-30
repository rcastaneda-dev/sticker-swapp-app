import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/matching/data/models/swipe_result.dart';

void main() {
  group('SwipeResult', () {
    test('fromJson parses mutual match response (201)', () {
      final json = <String, dynamic>{
        'matched': true,
        'match_id': '11111111-1111-1111-1111-111111111111',
        'user1_id': 'aaaa-aaaa',
        'user2_id': 'bbbb-bbbb',
        'status': 'PENDING',
        'created_at': '2026-03-30T12:34:56.123456Z',
      };

      final result = SwipeResult.fromJson(json);

      expect(result.matched, isTrue);
      expect(result.swipeRecorded, isFalse);
      expect(result.matchId, '11111111-1111-1111-1111-111111111111');
      expect(result.user1Id, 'aaaa-aaaa');
      expect(result.user2Id, 'bbbb-bbbb');
      expect(result.status, 'PENDING');
      expect(result.createdAt, isA<DateTime>());
      expect(result.createdAt!.year, 2026);
    });

    test('fromJson parses swipe-only response (200)', () {
      final json = <String, dynamic>{
        'matched': false,
        'swipe_recorded': true,
      };

      final result = SwipeResult.fromJson(json);

      expect(result.matched, isFalse);
      expect(result.swipeRecorded, isTrue);
      expect(result.matchId, isNull);
      expect(result.user1Id, isNull);
      expect(result.user2Id, isNull);
      expect(result.status, isNull);
      expect(result.createdAt, isNull);
    });

    test('fromJson defaults swipeRecorded to false when absent', () {
      final json = <String, dynamic>{'matched': false};

      final result = SwipeResult.fromJson(json);

      expect(result.swipeRecorded, isFalse);
    });
  });
}
