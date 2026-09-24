import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/app_theme.dart';
import '../utils/soup_layout.dart';
import '../widgets/widgets.dart';
import 'mouth_screen.dart';

/// The core game.
///
/// The chef makes a soup first, then the child makes their own. Nothing here
/// keeps score, times anything, or tells a child they are wrong, because in
/// the DfE activity there is nothing to get wrong.
class SoupScreen extends StatelessWidget {
  const SoupScreen({super.key, required this.sound});
  final PhonemeSound sound;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppProvider>();
    return ChangeNotifierProvider<SoupProvider>(
      create: (_) => SoupProvider(
        audio: app.audio,
        voice: app.chefVoice,
        analytics: app.analytics,
      ),
      child: _SoupView(sound: sound),
    );
  }
}

class _SoupView extends StatefulWidget {
  const _SoupView({required this.sound});
  final PhonemeSound sound;

  @override
  State<_SoupView> createState() => _SoupViewState();
}

class _SoupViewState extends State<_SoupView> {
  bool _started = false;

  /// Held onto rather than read in `dispose`. By the time this screen is
  /// being torn down the provider is no longer reachable from the context,
  /// and `context.read` there throws — which is why the chef used to carry
  /// on talking over the sound picker after a child backed out.
  SoupProvider? _soup;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Held on to so dispose() does not have to look the provider up through
    // a context that is on its way out.
    _soup = context.read<SoupProvider>();
    if (_started) return;
    _started = true;

    final app = context.read<AppProvider>();
    final soup = _soup!
      ..adultPaced = app.settings.whiteboardMode
      ..reducedMotion = app.prefersReducedMotion(context);

    // Starting the soup notifies listeners, and doing that while the tree is
    // still building trips a framework assert and leaves the first frame
    // half-painted. One frame later everything is mounted and the chef can
    // begin.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      soup.start(sound: widget.sound, bank: app.bank, settings: app.settings);
    });
  }

  @override
  void dispose() {
    // Stop the chef talking over whatever comes next.
    _soup?.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final soup = context.watch<SoupProvider>();
    final session = soup.session;
    final settings = app.settings;
    final reducedMotion = app.prefersReducedMotion(context);

    if (session == null) {
      return const Scaffold(
        backgroundColor: SoupColours.background,
        body: SizedBox.shrink(),
      );
    }

    return Scaffold(
      backgroundColor: SoupColours.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final layout = SoupLayout.forSize(
              size,
              whiteboard: settings.whiteboardMode,
            );
            final landscape = size.width > size.height;

            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: SoupLayout.horizontalPaddingFor(size.width),
                vertical: layout.gap * 0.75,
              ),
              child: Column(
                children: [
                  _TopBar(sound: session.sound, layout: layout),
                  SizedBox(height: layout.gap * 0.6),
                  ChefPanel(
                    line: soup.chefLine,
                    scale: layout.chefScale,
                    isBusy: soup.isChefBusy,
                    maxHeight: size.height * 0.28,
                  ),
                  SizedBox(height: layout.gap),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, playConstraints) {
                        final area = Size(
                          playConstraints.maxWidth,
                          playConstraints.maxHeight,
                        );
                        final play = PlayAreaLayout.forArea(
                          area,
                          whiteboard: settings.whiteboardMode,
                          landscape: landscape,
                        );
                        final pot = _Pot(
                          session: session,
                          settings: settings,
                          soup: soup,
                          play: play,
                          reducedMotion: reducedMotion,
                        );
                        final shelf = _Shelf(
                          session: session,
                          settings: settings,
                          soup: soup,
                          play: play,
                        );

                        if (play.sideBySide) {
                          return Row(
                            children: [
                              Expanded(flex: 4, child: pot),
                              SizedBox(width: layout.gap),
                              Expanded(flex: 6, child: shelf),
                            ],
                          );
                        }
                        // Flex rather than fixed heights: whatever the pot
                        // does not use, the shelf gets, and neither can push
                        // the other off the screen.
                        return Column(
                          children: [
                            Flexible(flex: 40, child: pot),
                            SizedBox(height: layout.gap),
                            Flexible(flex: 60, child: shelf),
                          ],
                        );
                      },
                    ),
                  ),
                  SizedBox(height: layout.gap * 0.6),
                  _Actions(
                    session: session,
                    soup: soup,
                    scale: layout.scale,
                    compact: layout.compactControls,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.sound, required this.layout});
  final PhonemeSound sound;
  final SoupLayout layout;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final soup = context.read<SoupProvider>();
    final compact = layout.compactControls;
    final iconSize = (compact ? 26.0 : 34.0) * layout.scale;

    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Back to the sounds',
          child: IconButton(
            iconSize: iconSize,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: SoupColours.textSecondary,
          ),
        ),
        Expanded(
          child: Center(
            child: SoundCard(
              sound: sound,
              showLetter: app.settings.showLetters,
              scale: layout.scale * (compact ? 0.42 : 0.6),
              onTap: soup.repeatSound,
            ),
          ),
        ),
        // On a phone there is no room for a labelled button next to
        // everything else, so "Watch my mouth" becomes the face icon it
        // already carries.
        if (compact)
          Semantics(
            button: true,
            label: 'Watch my mouth',
            child: IconButton(
              iconSize: iconSize,
              color: SoupColours.primary,
              onPressed: () => _openMouthView(context, app),
              icon: const Icon(Icons.face_retouching_natural_outlined),
            ),
          )
        else ...[
          SoupButton(
            label: 'Watch my mouth',
            icon: Icons.face_retouching_natural_outlined,
            outlined: true,
            scale: layout.scale * 0.8,
            onPressed: () => _openMouthView(context, app),
          ),
          SizedBox(width: 8 * layout.scale),
        ],
        Semantics(
          button: true,
          label: 'Play the soup song',
          child: IconButton(
            iconSize: iconSize,
            color: SoupColours.primary,
            onPressed: () {
              app.analytics.logSongPlayed();
              app.audio.playSong(app.chefVoice.song());
            },
            icon: const Icon(Icons.music_note_rounded),
          ),
        ),
        // Every clip is interruptible. A child who wants to carry on should
        // never have to sit through the chef finishing a sentence.
        Semantics(
          button: true,
          label: 'Stop the sound',
          child: IconButton(
            iconSize: iconSize,
            color: SoupColours.textSecondary,
            onPressed: () {
              app.analytics.logAudioStopped();
              app.audio.stop();
            },
            icon: const Icon(Icons.volume_off_rounded),
          ),
        ),
      ],
    );
  }

  void _openMouthView(BuildContext context, AppProvider app) {
    app.analytics.logMouthViewOpened(
      sound,
      mirrorShown: app.settings.mirrorModeEnabled,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // Named so the route observer can report the screen view.
        settings: const RouteSettings(name: 'watch_my_mouth'),
        builder: (_) => MouthScreen(sound: sound),
      ),
    );
  }
}

class _Pot extends StatelessWidget {
  const _Pot({
    required this.session,
    required this.settings,
    required this.soup,
    required this.play,
    required this.reducedMotion,
  });
  final SoupSession session;
  final AppSettings settings;
  final SoupProvider soup;
  final PlayAreaLayout play;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final isChefsPot = session.stage == SoupStage.chefModelling;
    final contents = isChefsPot
        ? session.chefSoup.take(soup.chefItemsShown).toList()
        : session.pot;
    final canDrop =
        session.stage == SoupStage.childsTurn &&
        settings.inputMode == InputMode.dragAndTap;
    final childsTurn = session.stage == SoupStage.childsTurn;
    final tasting = session.stage == SoupStage.tasting;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Whatever the flex handed us, the pot fits inside it: this is the
        // last place a fixed size could overflow, and on a phone in
        // landscape it is a very small box.
        final extras =
            (childsTurn ? PlayAreaLayout.stirButtonAllowance : 0.0) +
            (tasting ? play.potSize * 0.36 : 0.0);
        final size = math
            .min(
              math.min(constraints.maxWidth, play.potSize),
              math.max(constraints.maxHeight - extras, 48.0),
            )
            .toDouble();

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tasting)
                _TastingFlourish(reducedMotion: reducedMotion, size: size),
              Flexible(
                child: SoupPot(
                  contents: contents,
                  size: size,
                  isStirring: soup.isStirring,
                  reducedMotion: reducedMotion,
                  letter: settings.showLetters ? session.sound.grapheme : null,
                  onItemDropped: canDrop ? soup.addItem : null,
                ),
              ),
              if (childsTurn)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SoupButton(
                    label: 'Stir it!',
                    icon: Icons.refresh_rounded,
                    outlined: true,
                    scale: 0.8,
                    onPressed: session.pot.isEmpty ? null : soup.stirOnDemand,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.session,
    required this.settings,
    required this.soup,
    required this.play,
  });
  final SoupSession session;
  final AppSettings settings;
  final SoupProvider soup;
  final PlayAreaLayout play;

  @override
  Widget build(BuildContext context) {
    final childsTurn = session.stage == SoupStage.childsTurn;

    return AnimatedOpacity(
      opacity: childsTurn ? 1 : 0.45,
      duration: const Duration(milliseconds: 250),
      child: IgnorePointer(
        ignoring: !childsTurn,
        // The shelf keeps its own scrollbar-less scroll: on a small screen
        // the last row of ingredients is reachable by a swipe rather than
        // being off the bottom of the world.
        child: SingleChildScrollView(
          child: PantryShelf(
            items: session.pantry,
            draggable: settings.inputMode == InputMode.dragAndTap,
            showLetters: settings.showLetters,
            itemSize: play.ingredientSize,
            onItemChosen: soup.addItem,
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.session,
    required this.soup,
    required this.scale,
    required this.compact,
  });
  final SoupSession session;
  final SoupProvider soup;
  final double scale;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppProvider>();

    return switch (session.stage) {
      SoupStage.meetTheSound => SoupButton(
        label: 'Show me your soup!',
        icon: Icons.play_arrow_rounded,
        scale: scale,
        onPressed: soup.runChefModelling,
      ),
      SoupStage.chefModelling => SoupButton(
        label: 'My turn!',
        icon: Icons.pan_tool_alt_outlined,
        scale: scale,
        outlined: true,
        onPressed: soup.beginChildsTurn,
      ),
      SoupStage.childsTurn => SoupButton(
        label: 'All done!',
        icon: Icons.check_rounded,
        scale: scale,
        onPressed: session.pot.isEmpty ? null : soup.finish,
      ),
      // Two buttons side by side, because stacking them costs a whole row of
      // height a phone in landscape has not got.
      SoupStage.tasting => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: SoupButton(
              label: compact ? 'Another soup' : 'Make another soup?',
              icon: Icons.replay_rounded,
              scale: scale,
              onPressed: () => soup.start(
                sound: session.sound,
                bank: app.bank,
                settings: app.settings,
              ),
            ),
          ),
          SizedBox(width: 12 * scale),
          Flexible(
            child: SoupButton(
              label: compact ? 'New sound' : 'Pick a new sound',
              icon: Icons.grid_view_rounded,
              outlined: true,
              scale: scale,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    };
  }
}

/// The silly tasting: the chef has a spoonful and pulls a face.
class _TastingFlourish extends StatelessWidget {
  const _TastingFlourish({required this.reducedMotion, required this.size});
  final bool reducedMotion;
  final double size;

  @override
  Widget build(BuildContext context) {
    final face = Text('😋', style: TextStyle(fontSize: size * 0.28));
    if (reducedMotion) return face;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1.0),
      duration: const Duration(milliseconds: 700),
      curve: Curves.elasticOut,
      builder: (context, value, child) =>
          Transform.scale(scale: value, child: child),
      child: face,
    );
  }
}
