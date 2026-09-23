import 'dart:math';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../utils/app_theme.dart';

/// A close-up of a mouth making the sound.
///
/// Every shape in [MouthShape] is something a child can see and copy: lips
/// together for /m/, /b/ and /p/; teeth on the lip for /f/; tongue behind the
/// teeth for /t/, /d/ and /n/.
///
/// Stop sounds start with the mouth closed and pop open. Continuants hold
/// their shape, because that is exactly what "hold the sound on" looks like.
class MouthView extends StatefulWidget {
  const MouthView({
    super.key,
    required this.sound,
    required this.size,
    this.reducedMotion = false,
    this.playToken = 0,
  });
  final PhonemeSound sound;
  final double size;
  final bool reducedMotion;

  /// Bump to replay the animation from the start.
  final int playToken;

  @override
  State<MouthView> createState() => _MouthViewState();
}

class _MouthViewState extends State<MouthView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _play();
  }

  @override
  void didUpdateWidget(MouthView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playToken != widget.playToken ||
        oldWidget.sound.id != widget.sound.id) {
      _play();
    }
  }

  void _play() {
    if (widget.reducedMotion) {
      _controller.value = 1.0;
      return;
    }
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: MouthPainter(
            shape: widget.sound.mouthShape,
            isStop: !widget.sound.isContinuant,
            progress: _controller.value,
          ),
        );
      },
    );
  }
}

/// Paints the face and the mouth shape. Split out so it can be exercised in
/// a test without a ticker.
@visibleForTesting
class MouthPainter extends CustomPainter {
  const MouthPainter({
    required this.shape,
    required this.isStop,
    required this.progress,
  });
  final MouthShape shape;
  final bool isStop;

  /// 0 = about to make the sound, 1 = making it.
  final double progress;

  /// How open the mouth is, 0 to 1, at this point in the animation.
  double get openness {
    if (shape.startsClosed) {
      // Stops and nasals start closed. A stop pops open part-way through; a
      // nasal hum (/m/) stays closed, which is what the child should copy.
      if (!isStop) return 0;
      return progress < 0.45 ? 0 : ((progress - 0.45) / 0.3).clamp(0.0, 1.0);
    }
    // Continuants ease into their shape and hold it.
    return (progress / 0.4).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height * 0.56);
    final faceRadius = size.width * 0.42;

    canvas.drawCircle(
      centre.translate(0, -size.height * 0.04),
      faceRadius,
      Paint()..color = SoupColours.skin,
    );

    // Nose hint, so the mouth reads as a mouth.
    canvas.drawLine(
      Offset(centre.dx, centre.dy - faceRadius * 0.62),
      Offset(centre.dx, centre.dy - faceRadius * 0.34),
      Paint()
        ..color = SoupColours.lips.withValues(alpha: 0.45)
        ..strokeWidth = size.width * 0.012
        ..strokeCap = StrokeCap.round,
    );

    _paintMouth(canvas, size, centre);
  }

  void _paintMouth(Canvas canvas, Size size, Offset centre) {
    final open = openness;
    final mouthCentre = centre.translate(0, size.height * 0.1);

    final width = switch (shape) {
      MouthShape.openWide => size.width * 0.44,
      MouthShape.openSmall => size.width * 0.42,
      MouthShape.roundedLips => size.width * 0.24,
      MouthShape.teethNearlyTogether => size.width * 0.40,
      MouthShape.teethOnLip => size.width * 0.36,
      MouthShape.tongueBehindTeeth => size.width * 0.38,
      MouthShape.lipsTogether => size.width * 0.34,
    };

    final maxHeight = switch (shape) {
      MouthShape.openWide => size.height * 0.30,
      MouthShape.openSmall => size.height * 0.13,
      MouthShape.roundedLips => size.height * 0.20,
      MouthShape.teethNearlyTogether => size.height * 0.08,
      MouthShape.teethOnLip => size.height * 0.10,
      MouthShape.tongueBehindTeeth => size.height * 0.16,
      MouthShape.lipsTogether => size.height * 0.18,
    };

    final height = max(size.height * 0.012, maxHeight * open);
    final rect = Rect.fromCenter(
      center: mouthCentre,
      width: width,
      height: height,
    );

    // Inside of the mouth
    canvas.drawOval(rect, Paint()..color = SoupColours.mouthInside);

    if (shape == MouthShape.teethNearlyTogether ||
        shape == MouthShape.tongueBehindTeeth) {
      _paintTopTeeth(canvas, rect);
    }
    if (shape == MouthShape.tongueBehindTeeth) {
      _paintTongueTip(canvas, rect);
    }
    if (shape == MouthShape.teethOnLip) {
      _paintTopTeeth(canvas, rect, overhang: true);
    }

    // Lips
    canvas.drawOval(
      rect,
      Paint()
        ..color = SoupColours.lips
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.035,
    );

    // A closed mouth needs a line, or it reads as no mouth at all.
    if (open < 0.05) {
      canvas.drawLine(
        Offset(mouthCentre.dx - width / 2, mouthCentre.dy),
        Offset(mouthCentre.dx + width / 2, mouthCentre.dy),
        Paint()
          ..color = SoupColours.lips
          ..strokeWidth = size.width * 0.035
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _paintTopTeeth(Canvas canvas, Rect rect, {bool overhang = false}) {
    final teethHeight = rect.height * (overhang ? 0.7 : 0.45);
    if (teethHeight <= 0) return;
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height)),
    );
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width, teethHeight),
      Paint()..color = SoupColours.teeth,
    );
    canvas.restore();
  }

  void _paintTongueTip(Canvas canvas, Rect rect) {
    if (rect.height <= 0) return;
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height)),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(rect.center.dx, rect.top + rect.height * 0.55),
        width: rect.width * 0.5,
        height: rect.height * 0.7,
      ),
      Paint()..color = SoupColours.tongue,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(MouthPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.shape != shape ||
      oldDelegate.isStop != isStop;
}
