import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/app_theme.dart';
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
    final scale = SoupMetrics.scale(app.settings.whiteboardMode);

    return Scaffold(
      backgroundColor: SoupColours.background,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: Breakpoints.getHorizontalPadding(context),
                vertical: 16,
              ),
              child: Column(
                children: [
                  SizedBox(height: 8 * scale),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('🍲', style: TextStyle(fontSize: 40 * scale)),
                      SizedBox(width: 12 * scale),
                      Text(
                        'Silly Soup',
                        style: SoupTypography.heading(context)
                            .copyWith(fontSize: 34 * scale),
                      ),
                    ],
                  ),
                  SizedBox(height: 4 * scale),
                  Text(
                    'Pick a sound to cook with',
                    style: SoupTypography.subheading(context)
                        .copyWith(fontSize: 18 * scale),
                  ),
                  SizedBox(height: 20 * scale),
                  Expanded(
                    child: sounds.isEmpty
                        ? _NoSounds(scale: scale)
                        : SingleChildScrollView(
                            child: Center(
                              child: Wrap(
                                spacing: 16 * scale,
                                runSpacing: 16 * scale,
                                alignment: WrapAlignment.center,
                                children: [
                                  for (final sound in sounds)
                                    SoundCard(
                                      sound: sound,
                                      showLetter: app.settings.showLetters,
                                      scale: scale,
                                      onTap: () => _openSoup(context, sound),
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
                      width: 28 * scale,
                      height: 28 * scale,
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
                  MaterialPageRoute<void>(builder: (_) => const AdultScreen()),
                ),
              ),
            ),
          ],
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
      child: Padding(
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
