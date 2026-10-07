import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'app_theme.dart';

/// How the kitchen arranges itself in the space this device actually has.
///
/// Every size here is derived from the box the widget is given rather than
/// picked in advance, because "a tablet in landscape" was never the only
/// thing this runs on. A phone held upright has a third of the width and a
/// phone in landscape a third of the height, and in both cases the pantry
/// shelf has to stay on screen — a child who cannot reach an ingredient
/// cannot play at all.
@immutable
class SoupLayout {
  const SoupLayout({
    required this.soundColumns,
    required this.scale,
    required this.chefScale,
    required this.soundCardScale,
    required this.soundCardWidth,
    required this.compactControls,
    required this.gap,
  });

  /// Whiteboard sessions are shown across a room, so everything grows.
  factory SoupLayout.forSize(Size size, {bool whiteboard = false}) {
    final scale = SoupMetrics.scale(whiteboard);
    final columns = soundColumnsFor(size.width, height: size.height);
    final cardWidth =
        (size.width -
            horizontalPaddingFor(size.width) * 2 -
            soundCardSpacing * (columns - 1)) /
        columns;

    return SoupLayout(
      soundColumns: columns,
      scale: scale,
      // The chef and the speech bubble are the tallest fixed thing above the
      // pot, so they are what has to give on a short screen.
      chefScale:
          _clamp(math.min(size.width / 760, size.height / 620), 0.55, 1.0) *
          scale,
      soundCardScale: _clamp(cardWidth / naturalSoundCardWidth, 0.5, 1.0),
      soundCardWidth: math.max(cardWidth, SoupMetrics.minTapTarget),
      compactControls: size.width < compactControlsWidth,
      gap: size.height < 520 ? 8.0 : 14.0,
    );
  }

  /// Below this the top bar drops its labels and runs on icons alone. A
  /// labelled "Watch my mouth" button next to a back arrow, a sound card,
  /// a song button and a stop button does not fit on a phone.
  static const double compactControlsWidth = 700;

  /// What a sound card measures at full size, used to work out how far it
  /// has to shrink to fit the picker.
  static const double naturalSoundCardWidth = 196;

  static const double soundCardSpacing = 16;

  /// Columns in the sound picker. Two on a phone, so a child sees more than
  /// one sound without scrolling.
  ///
  /// On a short screen that flips round. A phone lying on its side has room
  /// for two rows at most, so five sounds in two columns put the last one
  /// below the fold with nothing on screen to say it was there — the same
  /// way the pantry used to hide. Another column is worth more than a bigger
  /// card when the alternative is a sound the child never sees.
  static int soundColumnsFor(double width, {double? height}) {
    final natural = width < 600
        ? 2
        : width < 900
        ? 3
        : 4;
    if (height == null || height >= shortScreenHeight) return natural;

    // As many as will fit while every card keeps its minimum tap target.
    final fits =
        ((width - horizontalPaddingFor(width) * 2 + soundCardSpacing) /
                (SoupMetrics.minTapTarget * 2 + soundCardSpacing))
            .floor();
    return math.max(natural, math.min(fits, 4));
  }

  /// Below this there is only room for two rows of sound cards.
  static const double shortScreenHeight = 420;

  static double horizontalPaddingFor(double width) {
    if (width < 500) return 16;
    if (width < 700) return 24;
    return 32;
  }

  /// How many sound cards fit across the picker.
  final int soundColumns;
  final double scale;
  final double chefScale;
  final double soundCardScale;
  final double soundCardWidth;
  final bool compactControls;
  final double gap;

  static double _clamp(double value, double low, double high) =>
      value.clamp(low, high).toDouble();
}

/// The pot and the shelf, sized for the box left over once the chef, the top
/// bar and the buttons have taken theirs.
@immutable
class PlayAreaLayout {
  const PlayAreaLayout({
    required this.sideBySide,
    required this.potSize,
    required this.ingredientSize,
  });

  /// [area] is the space the pot and shelf actually have, not the screen.
  factory PlayAreaLayout.forArea(
    Size area, {
    bool whiteboard = false,
    bool landscape = false,
  }) {
    // Side by side whenever the screen is wider than it is tall. Stacking
    // the shelf under the pot in landscape pushed it clean off the bottom of
    // a phone, which is how the shelf came to be unreachable.
    final sideBySide = landscape && area.width >= 480;

    final shelfWidth = sideBySide ? area.width * 0.58 : area.width;
    final potWidth = sideBySide ? area.width * 0.38 : area.width;
    final potHeight = sideBySide ? area.height : area.height * 0.45;

    return PlayAreaLayout(
      sideBySide: sideBySide,
      potSize: _clamp(
        math.min(potWidth, potHeight - stirButtonAllowance),
        minPotSize,
        whiteboard ? 340 : 300,
      ),
      ingredientSize: ingredientSizeFor(shelfWidth, whiteboard: whiteboard),
    );
  }

  /// Room under the pot for "Stir it!" and the tasting face.
  static const double stirButtonAllowance = 72;

  /// Small, but still a pot rather than a dot.
  static const double minPotSize = 96;

  /// Three ingredients across wherever the shelf is wide enough for three
  /// tap targets, and never a tile below the minimum tap size.
  static double ingredientSizeFor(
    double shelfWidth, {
    bool whiteboard = false,
  }) {
    if (whiteboard) return SoupMetrics.ingredientSizeWhiteboard;
    // The shelf's own padding and its 3px border both eat into the row.
    // Leaving the border out is what made three 95-point tiles need 309
    // points of a 305-point row, and wrap to two.
    const shelfPadding = (16.0 + 3.0) * 2;
    const spacing = 12.0;
    // Rounded down to a whole pixel. A tile a tenth of a pixel too wide
    // wraps to two per row instead of three, which costs a child a third of
    // the pantry for no visible reason.
    final perRow = ((shelfWidth - shelfPadding - spacing * 2) / 3)
        .floorToDouble();
    return _clamp(perRow, SoupMetrics.minTapTarget, SoupMetrics.ingredientSize);
  }

  final bool sideBySide;
  final double potSize;
  final double ingredientSize;

  static double _clamp(double value, double low, double high) =>
      value.clamp(low, high).toDouble();
}
