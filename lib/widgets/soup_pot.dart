import 'dart:math';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/app_theme.dart';
import 'word_picture.dart';

/// The pan. Items land here and bob about in the broth.
///
/// The pot is also the drop target, and it grows a highlight while something
/// is being dragged over it so a child can see where the banana is going.
class SoupPot extends StatefulWidget {
  const SoupPot({
    super.key,
    required this.contents,
    required this.size,
    this.isStirring = false,
    this.reducedMotion = false,
    this.onItemDropped,
    this.letter,
  });
  final List<SoupWord> contents;
  final bool isStirring;
  final bool reducedMotion;
  final double size;

  /// Null when the pot is not accepting items (during the chef's turn).
  final ValueChanged<SoupWord>? onItemDropped;

  /// Grapheme shown on the front of the pot in Phase Two mode.
  final String? letter;

  /// The band on the broth the ingredients sit in, as fractions of the pot's
  /// width. Shared with [_PotContents] so the cluster is measured against the
  /// same box it is drawn in.
  ///
  /// These are the broth itself, not a guess. `_PotPainter` draws it as an
  /// oval from `0.12` to `0.34` of a canvas that is `0.9` of this width tall
  /// — so `0.108` to `0.306` here — spanning `0.14` to `0.86` across. The box
  /// below sits inside that. It used to run to `0.39`, which is the dark side
  /// of the pan, and an ingredient that reached the bottom of it was drawn on
  /// the outside of the pot.
  static const double contentsTop = 0.11;
  static const double contentsWidth = 0.62;
  static const double contentsHeight = 0.20;

  @override
  State<SoupPot> createState() => _SoupPotState();
}

class _SoupPotState extends State<SoupPot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.reducedMotion) _controller.repeat();
  }

  @override
  void didUpdateWidget(SoupPot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reducedMotion && _controller.isAnimating) {
      _controller.stop();
    } else if (!widget.reducedMotion && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<SoupWord>(
      onWillAcceptWithDetails: (_) => widget.onItemDropped != null,
      onAcceptWithDetails: (details) =>
          widget.onItemDropped?.call(details.data),
      builder: (context, candidate, rejected) {
        final isHovered = candidate.isNotEmpty;
        return AnimatedScale(
          scale: isHovered ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: SizedBox(
            width: widget.size,
            height: widget.size * 0.9,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size(widget.size, widget.size * 0.9),
                  painter: _PotPainter(highlighted: isHovered),
                ),
                // Sat over the broth rather than below it: the point of the
                // activity is that the child can see their silly soup filling
                // up, so the ingredients have to be visible, not tucked
                // behind the rim.
                Positioned(
                  top: widget.size * SoupPot.contentsTop,
                  child: SizedBox(
                    width: widget.size * SoupPot.contentsWidth,
                    height: widget.size * SoupPot.contentsHeight,
                    child: _PotContents(
                      contents: widget.contents,
                      controller: _controller,
                      reducedMotion: widget.reducedMotion,
                      potSize: widget.size,
                    ),
                  ),
                ),
                if (widget.letter != null)
                  Positioned(
                    bottom: widget.size * 0.14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: SoupColours.soundCard,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        widget.letter!,
                        style: SoupTypography.heading(context)
                            .copyWith(fontSize: widget.size * 0.12),
                      ),
                    ),
                  ),
                if (widget.isStirring)
                  _Spoon(
                    controller: _controller,
                    size: widget.size,
                    reducedMotion: widget.reducedMotion,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PotContents extends StatelessWidget {
  const _PotContents({
    required this.contents,
    required this.controller,
    required this.reducedMotion,
    required this.potSize,
  });
  final List<SoupWord> contents;
  final AnimationController controller;
  final bool reducedMotion;
  final double potSize;

  /// Big while there are few, smaller as the pot fills. A child who has put
  /// two things in should see two large things, not two specks.
  double get itemSize {
    if (contents.length <= 3) return potSize * 0.20;
    if (contents.length <= 6) return potSize * 0.15;
    return potSize * 0.115;
  }

  @override
  Widget build(BuildContext context) {
    if (contents.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // One row, scaled to the broth it floats on.
        //
        // This was a Wrap inside a fixed box. An emoji is drawn wider than
        // its font size, so three items measured about 0.70 of the pot
        // against the 0.62 they were given, and the third wrapped onto a
        // second run that landed on the pan below the broth — an ingredient
        // stuck to the outside of the pot, in the one picture the whole
        // activity is about. Three is what the chef models every time.
        //
        // A row cannot wrap, so nothing leaves the soup by that route, and
        // scaling it means a full pantry shrinks rather than escapes.
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < contents.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Transform.translate(
                  offset: reducedMotion
                      ? Offset.zero
                      : Offset(
                          0,
                          sin((controller.value * 2 * pi) + i) *
                              itemSize *
                              0.12,
                        ),
                  child: WordPicture(word: contents[i], size: itemSize),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Spoon extends StatelessWidget {
  const _Spoon({
    required this.controller,
    required this.size,
    required this.reducedMotion,
  });
  final AnimationController controller;
  final double size;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    if (reducedMotion) {
      return Positioned(
        top: size * 0.02,
        right: size * 0.16,
        child: Text('🥄', style: TextStyle(fontSize: size * 0.2)),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final angle = controller.value * 2 * pi;
        return Positioned(
          top: size * 0.1 + sin(angle) * size * 0.05,
          left: size * 0.4 + cos(angle) * size * 0.18,
          child: Transform.rotate(angle: sin(angle) * 0.5, child: child),
        );
      },
      child: Text('🥄', style: TextStyle(fontSize: size * 0.2)),
    );
  }
}

class _PotPainter extends CustomPainter {
  const _PotPainter({required this.highlighted});
  final bool highlighted;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Paint()..color = SoupColours.pot;
    final rim = Paint()..color = SoupColours.potRim;
    final broth = Paint()..color = SoupColours.broth;
    final brothTop = Paint()..color = SoupColours.brothLight;

    final bodyRect = RRect.fromLTRBAndCorners(
      size.width * 0.12,
      size.height * 0.2,
      size.width * 0.88,
      size.height * 0.92,
      bottomLeft: Radius.circular(size.width * 0.18),
      bottomRight: Radius.circular(size.width * 0.18),
    );
    canvas.drawRRect(bodyRect, body);

    // Handles
    final handle = Paint()
      ..color = SoupColours.potDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.05
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.12, size.height * 0.34),
      Offset(size.width * 0.02, size.height * 0.44),
      handle,
    );
    canvas.drawLine(
      Offset(size.width * 0.88, size.height * 0.34),
      Offset(size.width * 0.98, size.height * 0.44),
      handle,
    );

    // Broth surface
    final brothRect = Rect.fromLTRB(
      size.width * 0.14,
      size.height * 0.12,
      size.width * 0.86,
      size.height * 0.34,
    );
    canvas.drawOval(brothRect, broth);
    canvas.drawOval(brothRect.deflate(size.width * 0.03), brothTop);

    // Rim
    canvas.drawOval(
      brothRect.inflate(size.width * 0.02),
      rim
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.045,
    );

    if (highlighted) {
      canvas.drawOval(
        brothRect.inflate(size.width * 0.05),
        Paint()
          ..color = SoupColours.gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.02,
      );
    }
  }

  @override
  bool shouldRepaint(_PotPainter oldDelegate) =>
      oldDelegate.highlighted != highlighted;
}
