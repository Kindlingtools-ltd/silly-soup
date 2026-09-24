import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/app_theme.dart';

/// The card the chef holds up, showing today's sound.
///
/// In Phase One this is the pure sound only — "sss", "b-b-b". The letter
/// appears only when an adult has turned on Phase Two mode, because letters
/// are not introduced until Phase Two.
class SoundCard extends StatelessWidget {
  const SoundCard({
    super.key,
    required this.sound,
    this.showLetter = false,
    this.scale = 1.0,
    this.width,
    this.onTap,
  });
  final PhonemeSound sound;
  final bool showLetter;
  final double scale;

  /// Fixed width, so a row of cards lines up. Null lets the card be as wide
  /// as its sound needs.
  final double? width;
  final VoidCallback? onTap;

  /// How tall a card is at [scale], so a caller can work out whether a set
  /// of them fits the space it has before it draws them.
  ///
  /// Never below the minimum tap target, however far the card has had to
  /// shrink to fit the screen it is on — which also means shrinking stops
  /// helping below [shrinkFloor].
  static double heightFor(double scale) => math.max(
    SoupMetrics.minTapTarget,
    SoupMetrics.minTapTarget * 1.6 * scale,
  );

  /// The scale at which [heightFor] hits the tap-target floor.
  static const double shrinkFloor = 1 / 1.6;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: width,
      constraints: BoxConstraints(
        minWidth: math.max(
          SoupMetrics.minTapTarget,
          SoupMetrics.minTapTarget * 2 * scale,
        ),
        minHeight: heightFor(scale),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: 24 * scale,
        vertical: 16 * scale,
      ),
      decoration: BoxDecoration(
        color: SoupColours.soundCard,
        borderRadius: BorderRadius.circular(SoupMetrics.cardRadius * scale),
        border: Border.all(color: SoupColours.primary, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A long sound like "b-b-b" on a narrow card shrinks to fit rather
          // than wrapping and clipping its own second line.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              sound.spokenPureSound,
              maxLines: 1,
              style: SoupTypography.soundDisplay(context)
                  .copyWith(fontSize: 48 * scale, color: SoupColours.primary),
            ),
          ),
          if (showLetter) ...[
            SizedBox(height: 8 * scale),
            Text(
              sound.grapheme,
              style: SoupTypography.heading(context)
                  .copyWith(fontSize: 32 * scale),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return card;
    return Semantics(
      button: true,
      label: 'Say the sound again',
      child: GestureDetector(onTap: onTap, child: card),
    );
  }
}
