import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/core/providers/deep_link_providers.dart';

void main() {
  group('DeepLinkNotifier', () {
    test('initial state is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(deepLinkProvider), isNull);
    });

    test('setPendingDestination stores the destination', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(deepLinkProvider.notifier).setPendingDestination('/matches/abc123');

      expect(container.read(deepLinkProvider), '/matches/abc123');
    });

    test('consume returns and clears the destination', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(deepLinkProvider.notifier);
      notifier.setPendingDestination('/matches/xyz789');

      final consumed = notifier.consume();

      expect(consumed, '/matches/xyz789');
      expect(container.read(deepLinkProvider), isNull);
    });

    test('consume returns null when no pending destination', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final consumed = container.read(deepLinkProvider.notifier).consume();

      expect(consumed, isNull);
    });

    test('clear removes the destination without returning it', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(deepLinkProvider.notifier);
      notifier.setPendingDestination('/matches/test');
      notifier.clear();

      expect(container.read(deepLinkProvider), isNull);
    });

    test('multiple setPendingDestination calls overwrite previous value', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(deepLinkProvider.notifier);
      notifier.setPendingDestination('/matches/first');
      notifier.setPendingDestination('/matches/second');

      expect(container.read(deepLinkProvider), '/matches/second');
    });
  });
}
