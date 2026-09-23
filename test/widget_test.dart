import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/models/models.dart';
import 'package:silly_soup/utils/app_theme.dart';
import 'package:silly_soup/widgets/widgets.dart';

import 'test_data.dart';

Widget wrap(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('pantry shelf', () {
    testWidgets('shows a tile for every item', (tester) async {
      await tester.pumpWidget(
        wrap(PantryShelf(items: sWords.take(6).toList(), onItemChosen: (_) {})),
      );

      expect(find.byType(IngredientCard), findsNWidgets(6));
    });

    testWidgets('tapping an item chooses it, with dragging switched off', (
      tester,
    ) async {
      SoupWord? chosen;
      await tester.pumpWidget(
        wrap(
          PantryShelf(
            items: [word('sun', 's')],
            draggable: false,
            onItemChosen: (item) => chosen = item,
          ),
        ),
      );

      await tester.tap(find.byType(IngredientCard));

      expect(chosen?.word, 'sun');
    });

    testWidgets('tapping works even when dragging is available', (
      tester,
    ) async {
      SoupWord? chosen;
      await tester.pumpWidget(
        wrap(
          PantryShelf(
            items: [word('sun', 's')],
            onItemChosen: (item) => chosen = item,
          ),
        ),
      );

      await tester.tap(find.byType(IngredientCard));

      expect(chosen?.word, 'sun');
    });

    testWidgets('no letters on the tiles in Phase One', (tester) async {
      await tester.pumpWidget(
        wrap(PantryShelf(items: [word('sun', 's')], onItemChosen: (_) {})),
      );

      expect(find.text('s'), findsNothing);
    });

    testWidgets('letters appear on the tiles in Phase Two mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          PantryShelf(
            items: [word('sun', 's')],
            showLetters: true,
            onItemChosen: (_) {},
          ),
        ),
      );

      expect(find.text('s'), findsOneWidget);
    });
  });

  group('sound card', () {
    testWidgets('shows the pure sound, not the letter, in Phase One', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(SoundCard(sound: soundB)));

      expect(find.text('b-b-b'), findsOneWidget);
      expect(find.text('b'), findsNothing);
    });

    testWidgets('shows the grapheme as well in Phase Two mode', (tester) async {
      await tester.pumpWidget(wrap(SoundCard(sound: soundB, showLetter: true)));

      expect(find.text('b-b-b'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
    });
  });

  group('tap targets', () {
    testWidgets('a button is never smaller than the minimum', (tester) async {
      await tester.pumpWidget(
        wrap(SoupButton(label: 'Stir it!', onPressed: () {})),
      );

      final size = tester.getSize(find.byType(SoupButton));

      expect(size.height, greaterThanOrEqualTo(SoupMetrics.minTapTarget));
      expect(size.width, greaterThanOrEqualTo(SoupMetrics.minTapTarget));
    });

    testWidgets('the adult gate is a full-size target too', (tester) async {
      await tester.pumpWidget(wrap(AdultGateButton(onUnlocked: () {})));

      final size = tester.getSize(find.byType(AdultGateButton));

      expect(size.height, greaterThanOrEqualTo(SoupMetrics.minTapTarget));
    });
  });

  group('adult gate', () {
    testWidgets('a short press does not open the adult area', (tester) async {
      var unlocked = false;
      await tester.pumpWidget(
        wrap(AdultGateButton(onUnlocked: () => unlocked = true)),
      );

      await tester.tap(find.byType(AdultGateButton));
      await tester.pump(const Duration(milliseconds: 500));

      expect(unlocked, isFalse);
    });

    testWidgets('holding for three seconds opens it', (tester) async {
      var unlocked = false;
      await tester.pumpWidget(
        wrap(AdultGateButton(onUnlocked: () => unlocked = true)),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(AdultGateButton)),
      );
      // The press has to be recognised before the hold starts counting.
      await tester.pump(const Duration(milliseconds: 150));
      for (var second = 0; second < 4; second++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(unlocked, isTrue);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('the pot', () {
    testWidgets('holds what the child put in', (tester) async {
      await tester.pumpWidget(
        wrap(
          SoupPot(contents: [word('sun', 's')], size: 200, reducedMotion: true),
        ),
      );

      expect(find.byType(WordPicture), findsOneWidget);
    });

    testWidgets('accepts a dragged item', (tester) async {
      SoupWord? dropped;
      await tester.pumpWidget(
        wrap(
          Column(
            children: [
              SoupPot(
                contents: const [],
                size: 160,
                reducedMotion: true,
                onItemDropped: (item) => dropped = item,
              ),
              PantryShelf(items: [word('sun', 's')], onItemChosen: (_) {}),
            ],
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(IngredientCard)),
      );
      await tester.pump(const Duration(milliseconds: 120));
      await gesture.moveTo(tester.getCenter(find.byType(SoupPot)));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(dropped?.word, 'sun');
    });
  });

  group('watch my mouth', () {
    test('a stop starts with the mouth closed and pops open', () {
      const closed = MouthPainter(
        shape: MouthShape.lipsTogether,
        isStop: true,
        progress: 0,
      );
      const open = MouthPainter(
        shape: MouthShape.lipsTogether,
        isStop: true,
        progress: 1,
      );

      expect(closed.openness, 0);
      expect(open.openness, 1);
    });

    test('a nasal hum keeps the lips together throughout', () {
      // /m/ is a continuant made with the mouth shut: if it opened, a child
      // copying the picture would be making /b/.
      const humming = MouthPainter(
        shape: MouthShape.lipsTogether,
        isStop: false,
        progress: 1,
      );

      expect(humming.openness, 0);
    });

    test('a continuant eases into its shape and holds it', () {
      const holding = MouthPainter(
        shape: MouthShape.teethNearlyTogether,
        isStop: false,
        progress: 1,
      );

      expect(holding.openness, 1);
    });
  });
}
