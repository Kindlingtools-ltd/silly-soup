import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/models/models.dart';
import 'package:silly_soup/utils/utils.dart';
import 'package:silly_soup/widgets/widgets.dart';

/// Colours that have to stay readable and stay distinct, and an ingredient
/// that has to stay in the pot.
///
/// All three came out of a design review of the running app. None of them
/// would have failed a layout test: nothing overflowed, nothing was off
/// screen, everything was the right size. They were simply the wrong colour,
/// or in the wrong place.
void main() {
  group('a control that is not ready still says what it is', () {
    testWidgets('the label on a disabled button is readable', (tester) async {
      // It used to be the button's white label on Material's cool grey —
      // 1.2:1, which is not a low-contrast label, it is no label. "All done!"
      // simply was not there until the pot was.
      for (final outlined in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Center(
                child: SoupButton(label: 'All done!', outlined: outlined),
              ),
            ),
          ),
        );

        final box =
            tester
                    .widget<Container>(
                      find
                          .descendant(
                            of: find.byType(SoupButton),
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        final label = tester.widget<Text>(find.text('All done!'));

        expect(
          _contrast(label.style!.color!, box.color!),
          greaterThanOrEqualTo(4.5),
          reason:
              'the label of a disabled outlined=$outlined button has to '
              'be readable, not merely present',
        );
      }
    });

    testWidgets('it does not look pressable', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Center(child: SoupButton(label: 'All done!')),
          ),
        ),
      );
      final box =
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byType(SoupButton),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(box.boxShadow, anyOf(isNull, isEmpty));
      expect(box.color, isNot(SoupColours.primary));
    });
  });

  group('a warning is not the same colour as a call to action', () {
    test('it is not the brand colour', () {
      // "Too few words to fill the pantry" was set in the same carrot as
      // every primary button, so "do this" and "something is wrong" were one
      // colour.
      expect(SoupColours.warning, isNot(SoupColours.primary));
    });

    test('it is readable on the card it appears on', () {
      // The old one was 2.6:1 on white — the warning was the harder of the
      // two to read as well as the wrong colour.
      expect(
        _contrast(SoupColours.warning, SoupColours.surface),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('everything a child puts in the pot stays in the pot', () {
    testWidgets('a full pot keeps every ingredient in the broth', (
      tester,
    ) async {
      // The cluster used to be a bare Wrap inside a fixed box. Once it needed
      // a second run, that run was drawn below the box — on the outside of
      // the pan, beneath the broth.
      //
      // In a browser three items are already too wide, because a colour emoji
      // is drawn wider than its font size. A widget test has no emoji font
      // and lays every glyph out at its nominal width, so three fit here and
      // five do not. Both are the same overflow, and the fix covers both;
      // this asserts the one this environment can actually see.
      const size = 400.0;
      const words = [
        SoupWord(word: 'sun', phoneme: 's', image: 'emoji:☀️'),
        SoupWord(word: 'sock', phoneme: 's', image: 'emoji:🧦'),
        SoupWord(word: 'seal', phoneme: 's', image: 'emoji:🦭'),
        SoupWord(word: 'sofa', phoneme: 's', image: 'emoji:🛋️'),
        SoupWord(word: 'star', phoneme: 's', image: 'emoji:⭐'),
        SoupWord(word: 'spoon', phoneme: 's', image: 'emoji:🥄'),
      ];

      for (var count = 1; count <= words.length; count++) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Center(
                child: SoupPot(
                  contents: words.take(count).toList(),
                  size: size,
                  reducedMotion: true,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        final pot = tester.getRect(find.byType(SoupPot));
        final broth = Rect.fromLTWH(
          pot.left + size * (1 - SoupPot.contentsWidth) / 2,
          pot.top + size * SoupPot.contentsTop,
          size * SoupPot.contentsWidth,
          size * SoupPot.contentsHeight,
        );

        for (final picture in find.byType(WordPicture).evaluate()) {
          final rect = tester.getRect(find.byWidget(picture.widget));
          expect(
            broth.inflate(0.5).contains(rect.topLeft) &&
                broth.inflate(0.5).contains(rect.bottomRight),
            isTrue,
            reason:
                'with $count in the pot, an ingredient at $rect is '
                'outside the broth $broth — it is drawn on the pan',
          );
        }
      }
    });
  });
}

/// WCAG 2.1 contrast ratio.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

double _luminance(Color colour) {
  double channel(double value) => value <= 0.04045
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();

  return 0.2126 * channel(colour.r) +
      0.7152 * channel(colour.g) +
      0.0722 * channel(colour.b);
}
