import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/app_theme.dart';
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
      create: (_) => SoupProvider(audio: app.audio, analytics: app.analytics),
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
    if (_started) return;
    _started = true;

    final app = context.read<AppProvider>();
    final soup = context.read<SoupProvider>()
      ..adultPaced = app.settings.whiteboardMode
      ..reducedMotion = app.prefersReducedMotion(context);
    _soup = soup;
    soup.start(sound: widget.sound, bank: app.bank, settings: app.settings);
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
    final scale = SoupMetrics.scale(settings.whiteboardMode);
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
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: Breakpoints.getHorizontalPadding(context),
            vertical: 12,
          ),
          child: Column(
            children: [
              _TopBar(sound: session.sound, scale: scale),
              SizedBox(height: 10 * scale),
              ChefPanel(
                line: soup.chefLine,
                scale: scale,
                isBusy: soup.isChefBusy,
              ),
              SizedBox(height: 12 * scale),
              Expanded(
                child: Breakpoints.shouldUseWideLayout(context)
                    ? _WideLayout(
                        session: session,
                        settings: settings,
                        soup: soup,
                        scale: scale,
                        reducedMotion: reducedMotion,
                      )
                    : _NarrowLayout(
                        session: session,
                        settings: settings,
                        soup: soup,
                        scale: scale,
                        reducedMotion: reducedMotion,
                      ),
              ),
              SizedBox(height: 10 * scale),
              _Actions(session: session, soup: soup, scale: scale),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.sound, required this.scale});
  final PhonemeSound sound;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final soup = context.read<SoupProvider>();

    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Back to the sounds',
          child: IconButton(
            iconSize: 34 * scale,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: SoupColours.textSecondary,
          ),
        ),
        const Spacer(),
        SoundCard(
          sound: sound,
          showLetter: app.settings.showLetters,
          scale: scale * 0.6,
          onTap: soup.repeatSound,
        ),
        const Spacer(),
        SoupButton(
          label: 'Watch my mouth',
          icon: Icons.face_retouching_natural_outlined,
          outlined: true,
          scale: scale * 0.8,
          onPressed: () => _openMouthView(context, app),
        ),
        SizedBox(width: 8 * scale),
        Semantics(
          button: true,
          label: 'Play the soup song',
          child: IconButton(
            iconSize: 34 * scale,
            color: SoupColours.primary,
            onPressed: () {
              app.analytics.logSongPlayed();
              app.audio.playSong();
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
            iconSize: 34 * scale,
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

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.session,
    required this.settings,
    required this.soup,
    required this.scale,
    required this.reducedMotion,
  });
  final SoupSession session;
  final AppSettings settings;
  final SoupProvider soup;
  final double scale;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Center(
            child: _Pot(
              session: session,
              settings: settings,
              soup: soup,
              size: 260 * scale,
              reducedMotion: reducedMotion,
            ),
          ),
        ),
        SizedBox(width: 16 * scale),
        Expanded(
          flex: 6,
          child: SingleChildScrollView(
            child: _Shelf(
              session: session,
              settings: settings,
              soup: soup,
              scale: scale,
            ),
          ),
        ),
      ],
    );
  }
}

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({
    required this.session,
    required this.settings,
    required this.soup,
    required this.scale,
    required this.reducedMotion,
  });
  final SoupSession session;
  final AppSettings settings;
  final SoupProvider soup;
  final double scale;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _Pot(
            session: session,
            settings: settings,
            soup: soup,
            size: 200 * scale,
            reducedMotion: reducedMotion,
          ),
          SizedBox(height: 16 * scale),
          _Shelf(
            session: session,
            settings: settings,
            soup: soup,
            scale: scale,
          ),
        ],
      ),
    );
  }
}

class _Pot extends StatelessWidget {
  const _Pot({
    required this.session,
    required this.settings,
    required this.soup,
    required this.size,
    required this.reducedMotion,
  });
  final SoupSession session;
  final AppSettings settings;
  final SoupProvider soup;
  final double size;
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (session.stage == SoupStage.tasting)
          _TastingFlourish(reducedMotion: reducedMotion, size: size),
        SoupPot(
          contents: contents,
          size: size,
          isStirring: soup.isStirring,
          reducedMotion: reducedMotion,
          letter: settings.showLetters ? session.sound.grapheme : null,
          onItemDropped: canDrop ? soup.addItem : null,
        ),
        if (session.stage == SoupStage.childsTurn)
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
    );
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.session,
    required this.settings,
    required this.soup,
    required this.scale,
  });
  final SoupSession session;
  final AppSettings settings;
  final SoupProvider soup;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final childsTurn = session.stage == SoupStage.childsTurn;

    return AnimatedOpacity(
      opacity: childsTurn ? 1 : 0.45,
      duration: const Duration(milliseconds: 250),
      child: IgnorePointer(
        ignoring: !childsTurn,
        child: PantryShelf(
          items: session.pantry,
          draggable: settings.inputMode == InputMode.dragAndTap,
          showLetters: settings.showLetters,
          itemSize: SoupMetrics.ingredient(settings.whiteboardMode),
          onItemChosen: soup.addItem,
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
  });
  final SoupSession session;
  final SoupProvider soup;
  final double scale;

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
      SoupStage.tasting => Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.center,
        children: [
          SoupButton(
            label: 'Make another soup?',
            icon: Icons.replay_rounded,
            scale: scale,
            onPressed: () => soup.start(
              sound: session.sound,
              bank: app.bank,
              settings: app.settings,
            ),
          ),
          SoupButton(
            label: 'Pick a new sound',
            icon: Icons.grid_view_rounded,
            outlined: true,
            scale: scale,
            onPressed: () => Navigator.of(context).pop(),
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
