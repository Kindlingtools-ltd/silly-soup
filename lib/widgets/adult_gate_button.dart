import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// The way into the adult area.
///
/// Press and hold for three seconds. A child who finds the button by accident
/// lets go long before it opens, and there is no number puzzle for an adult
/// to remember.
class AdultGateButton extends StatefulWidget {
  const AdultGateButton({
    super.key,
    required this.onUnlocked,
    this.holdDuration = const Duration(seconds: 3),
  });
  final VoidCallback onUnlocked;
  final Duration holdDuration;

  @override
  State<AdultGateButton> createState() => _AdultGateButtonState();
}

class _AdultGateButtonState extends State<AdultGateButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.holdDuration)
        ..addStatusListener((status) {
          if (status != AnimationStatus.completed) return;
          // Reset after the notification has been delivered rather than during
          // it — changing an animation from inside its own status callback is
          // how you get a re-entrancy assert.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _controller.value = 0;
          });
          widget.onUnlocked();
        });

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Grown-ups: press and hold for three seconds',
      child: GestureDetector(
        onTapDown: (_) => _controller.forward(),
        onTapUp: (_) => _controller.reverse(),
        onTapCancel: () => _controller.reverse(),
        child: SizedBox(
          width: SoupMetrics.minTapTarget,
          height: SoupMetrics.minTapTarget,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  if (_controller.value > 0)
                    SizedBox(
                      width: SoupMetrics.minTapTarget - 8,
                      height: SoupMetrics.minTapTarget - 8,
                      child: CircularProgressIndicator(
                        value: _controller.value,
                        strokeWidth: 4,
                        color: SoupColours.primary,
                        backgroundColor: SoupColours.border,
                      ),
                    ),
                  child!,
                ],
              );
            },
            child: const Icon(
              Icons.settings_outlined,
              size: 30,
              color: SoupColours.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
