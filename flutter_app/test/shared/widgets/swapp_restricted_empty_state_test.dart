import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/shared/shared.dart';

void main() {
  Widget buildSubject({
    IconData icon = Icons.swap_horiz,
    String title = 'Test Title',
    String subtitle = 'Test subtitle text',
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return MaterialApp(
      theme: SwappTheme.light,
      home: Scaffold(
        body: SwappRestrictedEmptyState(
          icon: icon,
          title: title,
          subtitle: subtitle,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      ),
    );
  }

  group('SwappRestrictedEmptyState', () {
    testWidgets('renders icon, title, and subtitle', (tester) async {
      await tester.pumpWidget(buildSubject());

      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
      expect(find.text('Test Title'), findsOneWidget);
      expect(find.text('Test subtitle text'), findsOneWidget);
    });

    testWidgets('renders action button when actionLabel and onAction provided',
        (tester) async {
      await tester.pumpWidget(buildSubject(
        actionLabel: 'Browse Stickers',
        onAction: () {},
      ));

      expect(find.text('Browse Stickers'), findsOneWidget);
    });

    testWidgets('does not render action button when actionLabel is null',
        (tester) async {
      await tester.pumpWidget(buildSubject());

      // No OutlinedButton should exist
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('calls onAction when action button is tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(buildSubject(
        actionLabel: 'Browse Stickers',
        onAction: () => tapped = true,
      ));

      await tester.tap(find.text('Browse Stickers'));
      expect(tapped, isTrue);
    });
  });
}
