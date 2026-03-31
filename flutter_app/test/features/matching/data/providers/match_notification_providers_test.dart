import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/features/matching/data/providers/match_notification_providers.dart';

void main() {
  group('MatchNotificationNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is empty list', () {
      expect(container.read(matchNotificationProvider), isEmpty);
    });

    test('addMatch appends to the list', () {
      container.read(matchNotificationProvider.notifier).addMatch(
            const UnviewedMatch(matchId: 'm1', displayName: 'Carlos'),
          );

      final matches = container.read(matchNotificationProvider);
      expect(matches, hasLength(1));
      expect(matches.first.matchId, 'm1');
      expect(matches.first.displayName, 'Carlos');
    });

    test('addMatch with multiple entries preserves order', () {
      final notifier = container.read(matchNotificationProvider.notifier);
      notifier.addMatch(
        const UnviewedMatch(matchId: 'm1', displayName: 'Carlos'),
      );
      notifier.addMatch(
        const UnviewedMatch(matchId: 'm2', displayName: 'Diego'),
      );

      final matches = container.read(matchNotificationProvider);
      expect(matches, hasLength(2));
      expect(matches[0].matchId, 'm1');
      expect(matches[1].matchId, 'm2');
    });

    test('markViewed removes only the specified matchId', () {
      final notifier = container.read(matchNotificationProvider.notifier);
      notifier.addMatch(
        const UnviewedMatch(matchId: 'm1', displayName: 'Carlos'),
      );
      notifier.addMatch(
        const UnviewedMatch(matchId: 'm2', displayName: 'Diego'),
      );

      notifier.markViewed('m1');

      final matches = container.read(matchNotificationProvider);
      expect(matches, hasLength(1));
      expect(matches.first.matchId, 'm2');
    });

    test('markViewed with unknown matchId is a no-op', () {
      final notifier = container.read(matchNotificationProvider.notifier);
      notifier.addMatch(
        const UnviewedMatch(matchId: 'm1', displayName: 'Carlos'),
      );

      notifier.markViewed('unknown');

      expect(container.read(matchNotificationProvider), hasLength(1));
    });

    test('clear empties the list', () {
      final notifier = container.read(matchNotificationProvider.notifier);
      notifier.addMatch(
        const UnviewedMatch(matchId: 'm1', displayName: 'Carlos'),
      );
      notifier.addMatch(
        const UnviewedMatch(matchId: 'm2', displayName: 'Diego'),
      );

      notifier.clear();

      expect(container.read(matchNotificationProvider), isEmpty);
    });
  });

  group('unviewedMatchCountProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('returns 0 when empty', () {
      expect(container.read(unviewedMatchCountProvider), 0);
    });

    test('returns correct count after adds', () {
      final notifier = container.read(matchNotificationProvider.notifier);
      notifier.addMatch(
        const UnviewedMatch(matchId: 'm1', displayName: 'Carlos'),
      );
      notifier.addMatch(
        const UnviewedMatch(matchId: 'm2', displayName: 'Diego'),
      );

      expect(container.read(unviewedMatchCountProvider), 2);
    });

    test('decrements after markViewed', () {
      final notifier = container.read(matchNotificationProvider.notifier);
      notifier.addMatch(
        const UnviewedMatch(matchId: 'm1', displayName: 'Carlos'),
      );
      notifier.addMatch(
        const UnviewedMatch(matchId: 'm2', displayName: 'Diego'),
      );

      notifier.markViewed('m1');

      expect(container.read(unviewedMatchCountProvider), 1);
    });
  });

  group('mostRecentUnviewedMatchProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('returns null when empty', () {
      expect(container.read(mostRecentUnviewedMatchProvider), isNull);
    });

    test('returns last added match', () {
      final notifier = container.read(matchNotificationProvider.notifier);
      notifier.addMatch(
        const UnviewedMatch(matchId: 'm1', displayName: 'Carlos'),
      );
      notifier.addMatch(
        const UnviewedMatch(matchId: 'm2', displayName: 'Diego'),
      );

      final recent = container.read(mostRecentUnviewedMatchProvider);
      expect(recent?.matchId, 'm2');
      expect(recent?.displayName, 'Diego');
    });

    test('updates when most recent is marked viewed', () {
      final notifier = container.read(matchNotificationProvider.notifier);
      notifier.addMatch(
        const UnviewedMatch(matchId: 'm1', displayName: 'Carlos'),
      );
      notifier.addMatch(
        const UnviewedMatch(matchId: 'm2', displayName: 'Diego'),
      );

      notifier.markViewed('m2');

      final recent = container.read(mostRecentUnviewedMatchProvider);
      expect(recent?.matchId, 'm1');
    });
  });
}
