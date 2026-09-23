import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// The chef and what they are saying.
///
/// The chef is an emoji placeholder, sized and positioned so real artwork can
/// drop straight in later.
class ChefPanel extends StatelessWidget {
  const ChefPanel({
    super.key,
    required this.line,
    this.scale = 1.0,
    this.isBusy = false,
  });
  final String line;
  final double scale;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AnimatedScale(
          scale: isBusy ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 400),
          child: Text('👩‍🍳', style: TextStyle(fontSize: 64 * scale)),
        ),
        SizedBox(width: 12 * scale),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Container(
              key: ValueKey(line),
              padding: EdgeInsets.symmetric(
                horizontal: 20 * scale,
                vertical: 14 * scale,
              ),
              decoration: BoxDecoration(
                color: SoupColours.surface,
                borderRadius: BorderRadius.circular(20 * scale),
                border: Border.all(color: SoupColours.border, width: 2),
              ),
              child: Text(
                line,
                style: SoupTypography.chefSpeech(
                  context,
                ).copyWith(fontSize: 18 * scale),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
