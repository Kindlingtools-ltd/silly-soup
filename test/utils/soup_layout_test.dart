import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/utils/utils.dart';

/// Screens someone will genuinely hold this up on.
const phonePortrait = Size(375, 667);
const smallPhonePortrait = Size(320, 568);
const phoneLandscape = Size(667, 375);
const tabletLandscape = Size(1024, 768);

void main() {
  group('the kitchen', () {
    test('puts the pot beside the shelf whenever the screen is wide', () {
      // Height is the scarce thing in landscape. Stacking the shelf under
      // the pot is what pushed it off the bottom of a phone.
      final play = PlayAreaLayout.forArea(
        const Size(615, 180),
        landscape: true,
      );

      expect(play.sideBySide, isTrue);
    });

    test('stacks the pot above the shelf on a phone held upright', () {
      final play = PlayAreaLayout.forArea(const Size(343, 430));

      expect(play.sideBySide, isFalse);
    });

    test('the pot fits the space it is given, however short', () {
      for (final area in [
        const Size(615, 140),
        const Size(343, 300),
        const Size(960, 520),
      ]) {
        final play = PlayAreaLayout.forArea(
          area,
          landscape: area.width > area.height,
        );

        expect(play.potSize, lessThanOrEqualTo(area.width));
        expect(play.potSize, greaterThanOrEqualTo(PlayAreaLayout.minPotSize));
      }
    });

    test('an ingredient is never smaller than a tap target', () {
      for (final width in [240.0, 288.0, 357.0, 600.0]) {
        expect(
          PlayAreaLayout.ingredientSizeFor(width),
          greaterThanOrEqualTo(SoupMetrics.minTapTarget),
        );
      }
    });

    test('three ingredients fit across a phone-width shelf', () {
      // 343 is a 375-wide phone once the screen padding has come off, and
      // the shelf then spends 16 points of padding and 3 of border a side.
      for (final shelfWidth in [288.0, 343.0, 380.0]) {
        final size = PlayAreaLayout.ingredientSizeFor(shelfWidth);

        expect(
          size * 3 + 12 * 2 + (16 + 3) * 2,
          lessThanOrEqualTo(shelfWidth),
          reason: 'three tiles should fit a $shelfWidth-point shelf',
        );
      }
    });

    test('a whiteboard keeps its big tiles', () {
      expect(
        PlayAreaLayout.ingredientSizeFor(900, whiteboard: true),
        SoupMetrics.ingredientSizeWhiteboard,
      );
    });
  });

  group('the chrome', () {
    test('the top bar drops its labels on a phone but not a tablet', () {
      expect(SoupLayout.forSize(phoneLandscape).compactControls, isTrue);
      expect(SoupLayout.forSize(phonePortrait).compactControls, isTrue);
      expect(SoupLayout.forSize(tabletLandscape).compactControls, isFalse);
    });

    test('the chef shrinks on a short screen and not on a roomy one', () {
      final short = SoupLayout.forSize(phoneLandscape);
      final roomy = SoupLayout.forSize(tabletLandscape);

      expect(short.chefScale, lessThan(roomy.chefScale));
      expect(short.chefScale, greaterThanOrEqualTo(0.55));
    });

    test('two sound cards fit across a phone', () {
      for (final size in [phonePortrait, smallPhonePortrait]) {
        final layout = SoupLayout.forSize(size);
        final padding = SoupLayout.horizontalPaddingFor(size.width);

        expect(SoupLayout.soundColumnsFor(size.width), 2);
        expect(
          layout.soundCardWidth * 2 + SoupLayout.soundCardSpacing + padding * 2,
          lessThanOrEqualTo(size.width + 0.01),
        );
      }
    });

    test('a sound card never shrinks past half size', () {
      expect(
        SoupLayout.forSize(const Size(240, 400)).soundCardScale,
        greaterThanOrEqualTo(0.5),
      );
    });

    test('a whiteboard still scales everything up', () {
      final layout = SoupLayout.forSize(tabletLandscape, whiteboard: true);

      expect(layout.scale, greaterThan(1));
    });
  });
}
