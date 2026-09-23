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
    this.onTap,
  });
  final PhonemeSound sound;
  final bool showLetter;
  final double scale;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      constraints: BoxConstraints(
        minWidth: SoupMetrics.minTapTarget * 2 * scale,
        minHeight: SoupMetrics.minTapTarget * 1.6 * scale,
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
          Text(
            sound.spokenPureSound,
            style: SoupTypography.soundDisplay(
              context,
            ).copyWith(fontSize: 48 * scale, color: SoupColours.primary),
          ),
          if (showLetter) ...[
            SizedBox(height: 8 * scale),
            Text(
              sound.grapheme,
              style: SoupTypography.heading(
                context,
              ).copyWith(fontSize: 32 * scale),
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
