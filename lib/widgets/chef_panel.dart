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
    this.maxHeight,
  });
  final String line;
  final double scale;
  final bool isBusy;

  /// Ceiling on the speech bubble, so a long recital of a very full soup
  /// cannot squeeze the pot and the shelf off a short screen. The bubble
  /// scrolls inside it rather than growing.
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    // The chef shrinks freely; the words do not. Below about 15 points this
    // stops being something an adult can read across a table.
    final fontSize = 14 + 4 * scale;

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
              constraints: BoxConstraints(
                maxHeight: maxHeight ?? double.infinity,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: 16 * scale,
                vertical: 12 * scale,
              ),
              decoration: BoxDecoration(
                color: SoupColours.surface,
                borderRadius: BorderRadius.circular(20 * scale),
                border: Border.all(color: SoupColours.border, width: 2),
              ),
              child: SingleChildScrollView(
                child: Text(
                  line,
                  style: SoupTypography.chefSpeech(context)
                      .copyWith(fontSize: fontSize),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
