import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/models.dart';
import '../utils/app_theme.dart';

/// Draws a pantry item's picture.
///
/// Emoji are placeholders, easy to swap for real artwork: change the word
/// bank entry from `emoji:🍌` to `asset:items/banana.svg` and nothing else
/// has to change.
class WordPicture extends StatelessWidget {
  const WordPicture({super.key, required this.word, required this.size});
  final SoupWord word;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = word.parsedImage;

    return ExcludeSemantics(
      child: switch (image.kind) {
        WordImageKind.emoji => Text(
          image.value,
          style: TextStyle(fontSize: size, height: 1.15),
          textAlign: TextAlign.center,
        ),
        WordImageKind.asset =>
          image.value.endsWith('.svg')
              ? SvgPicture.asset(image.assetPath, width: size, height: size)
              : Image.asset(image.assetPath, width: size, height: size),
        // Adult-supplied pictures live in local storage and arrive in Stage 2.
        WordImageKind.custom => Icon(
          Icons.image_outlined,
          size: size,
          color: SoupColours.textSecondary,
        ),
      },
    );
  }
}
