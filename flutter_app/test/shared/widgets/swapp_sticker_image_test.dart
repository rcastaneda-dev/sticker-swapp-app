import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/shared/widgets/swapp_sticker_image.dart';

void main() {
  Widget buildTestWidget({
    int stickerNumber = 1,
    String? imageUrl,
    String? team,
    String? type,
    StickerImageSize size = StickerImageSize.card,
    VoidCallback? onTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SwappStickerImage(
            stickerNumber: stickerNumber,
            imageUrl: imageUrl,
            team: team,
            type: type,
            size: size,
            onTap: onTap,
          ),
        ),
      ),
    );
  }

  group('SwappStickerImage placeholder', () {
    testWidgets('renders sticker number when imageUrl is null', (tester) async {
      await tester.pumpWidget(buildTestWidget(stickerNumber: 42));

      expect(find.text('#42'), findsOneWidget);
    });

    testWidgets('shows team name badge when team is provided', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        stickerNumber: 1,
        team: 'Argentina',
      ));

      expect(find.text('Argentina'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
    });

    testWidgets('hides team badge when team is null', (tester) async {
      await tester.pumpWidget(buildTestWidget(stickerNumber: 5));

      expect(find.text('#5'), findsOneWidget);
      // No team text should be present
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('shows player icon for player type', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        stickerNumber: 10,
        team: 'Brazil',
        type: 'player',
      ));

      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    });

    testWidgets('shows stadium icon for stadium type', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        stickerNumber: 3,
        type: 'stadium',
        size: StickerImageSize.card,
      ));

      expect(find.byIcon(Icons.stadium_outlined), findsOneWidget);
    });

    testWidgets('shows star icon for legend type', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        stickerNumber: 20,
        team: 'Germany',
        type: 'legend',
      ));

      expect(find.byIcon(Icons.star_outline), findsOneWidget);
    });
  });

  group('StickerImageSize', () {
    testWidgets('thumbnail renders at 64px', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        stickerNumber: 1,
        size: StickerImageSize.thumbnail,
      ));

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.width, 64.0);
      expect(sizedBox.height, 64.0);
    });

    testWidgets('card renders at 256px', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        stickerNumber: 1,
        size: StickerImageSize.card,
      ));

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.width, 256.0);
      expect(sizedBox.height, 256.0);
    });

    testWidgets('detail renders at 512px', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        stickerNumber: 1,
        size: StickerImageSize.detail,
      ));

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
      expect(sizedBox.width, 512.0);
      expect(sizedBox.height, 512.0);
    });

    testWidgets('thumbnail hides team badge and type icon', (tester) async {
      await tester.pumpWidget(buildTestWidget(
        stickerNumber: 7,
        team: 'France',
        type: 'player',
        size: StickerImageSize.thumbnail,
      ));

      // Only sticker number should appear on thumbnail
      expect(find.text('#7'), findsOneWidget);
      expect(find.text('France'), findsNothing);
      expect(find.byIcon(Icons.person_outline), findsNothing);
    });
  });

  group('interaction', () {
    testWidgets('calls onTap callback when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(buildTestWidget(
        stickerNumber: 1,
        onTap: () => tapped = true,
      ));

      await tester.tap(find.text('#1'));
      expect(tapped, isTrue);
    });

    testWidgets('does not wrap in InkWell when onTap is null', (tester) async {
      await tester.pumpWidget(buildTestWidget(stickerNumber: 1));

      // The Material widget should be present but InkWell should not wrap the content
      expect(find.byType(InkWell), findsNothing);
    });
  });
}
