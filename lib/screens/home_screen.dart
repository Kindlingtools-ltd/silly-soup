import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/app_theme.dart';
import '../utils/soup_layout.dart';
import '../widgets/widgets.dart';
import 'adult_screen.dart';
import 'soup_screen.dart';

/// Pick a sound. One clear choice, nothing else on screen.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final sounds = app.availableSounds;

    return Scaffold(
      backgroundColor: SoupColours.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final layout = SoupLayout.forSize(
              size,
              whiteboard: app.settings.whiteboardMode,
            );
            final scale = layout.scale;
            // A phone in landscape has about a third of the height of the
            // tablet this was drawn for, and the title was taking most of it.
            final titleScale = size.height < 460 ? 0.65 : 1.0;

            return Stack(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: SoupLayout.horizontalPaddingFor(size.width),
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      SizedBox(height: 8 * scale * titleScale),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '🍲',
                            style: TextStyle(fontSize: 40 * scale * titleScale),
                          ),
                          SizedBox(width: 12 * scale),
                          Flexible(
                            child: Text(
                              'Silly Soup',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SoupTypography.heading(context)
                                  .copyWith(fontSize: 34 * scale * titleScale),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4 * scale),
                      Text(
                        'Pick a sound to cook with',
                        textAlign: TextAlign.center,
                        style: SoupTypography.subheading(context)
                            .copyWith(fontSize: 18 * scale * titleScale),
                      ),
                      SizedBox(height: 16 * scale * titleScale),
                      Expanded(
                        child: sounds.isEmpty
                            ? _NoSounds(scale: scale)
                            // Centred in the space that is left, and it
                            // scrolls when a long list of sounds needs more
                            // room than a phone has.
                            : Center(
                                child: SingleChildScrollView(
                                  child: Wrap(
                                    spacing: SoupLayout.soundCardSpacing,
                                    runSpacing: SoupLayout.soundCardSpacing,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      for (final sound in sounds)
                                        SoundCard(
                                          sound: sound,
                                          showLetter: app.settings.showLetters,
                                          scale: layout.soundCardScale * scale,
                                          width: layout.soundCardWidth,
                                          onTap: () =>
                                              _openSoup(context, sound),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                      SizedBox(height: 8 * scale),
                      Opacity(
                        opacity: 0.6,
                        child: SvgPicture.asset(
                          'assets/kindling_logo.svg',
                          width: 24 * scale,
                          height: 24 * scale,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: AdultGateButton(
                    onUnlocked: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AdultScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openSoup(BuildContext context, PhonemeSound sound) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => SoupScreen(sound: sound)));
  }
}

class _NoSounds extends StatelessWidget {
  const _NoSounds({required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No sounds are switched on yet.\n'
          'A grown-up can turn some on by holding the button in the corner.',
          textAlign: TextAlign.center,
          style: SoupTypography.subheading(context)
              .copyWith(fontSize: 18 * scale),
        ),
      ),
    );
  }
}
