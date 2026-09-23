import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/app_theme.dart';
import 'word_picture.dart';

/// One item on the pantry shelf.
///
/// Draggable and tappable at the same time when the adult has left dragging
/// on: dragging is the activity, tapping is the way in for a child who finds
/// dragging hard today.
class IngredientCard extends StatelessWidget {
  const IngredientCard({
    super.key,
    required this.word,
    required this.onChosen,
    this.size = SoupMetrics.ingredientSize,
    this.draggable = true,
    this.letter,
  });
  final SoupWord word;
  final double size;
  final bool draggable;
  final VoidCallback onChosen;

  /// Shown under the picture only in Phase Two mode.
  final String? letter;

  @override
  Widget build(BuildContext context) {
    final tile = _Tile(word: word, size: size, letter: letter);

    final tappable = Semantics(
      button: true,
      label: word.word,
      child: GestureDetector(
        onTap: onChosen,
        behavior: HitTestBehavior.opaque,
        child: tile,
      ),
    );

    if (!draggable) return tappable;

    return Draggable<SoupWord>(
      data: word,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Transform.translate(
        offset: Offset(-size * 0.6, -size * 0.6),
        child: Opacity(
          opacity: 0.9,
          child: _Tile(word: word, size: size * 1.2, letter: letter),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.25, child: tile),
      child: tappable,
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.word, required this.size, this.letter});
  final SoupWord word;
  final double size;
  final String? letter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: SoupColours.surface,
        borderRadius: BorderRadius.circular(SoupMetrics.cardRadius),
        border: Border.all(color: SoupColours.border, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          WordPicture(word: word, size: size * 0.52),
          if (letter != null) ...[
            SizedBox(height: size * 0.04),
            Text(
              letter!,
              style: SoupTypography.heading(context)
                  .copyWith(fontSize: size * 0.2),
            ),
          ],
        ],
      ),
    );
  }
}
