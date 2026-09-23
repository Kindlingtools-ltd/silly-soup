import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/app_theme.dart';

/// The grown-ups' area, behind the press-and-hold gate.
///
/// Everything here is stored on this device. Nothing is sent anywhere.
class AdultScreen extends StatelessWidget {
  const AdultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final settings = app.settings;

    return Scaffold(
      backgroundColor: SoupColours.background,
      appBar: AppBar(
        title: const Text('Grown-ups'),
        backgroundColor: SoupColours.background,
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: Breakpoints.getHorizontalPadding(context),
          vertical: 16,
        ),
        children: [
          _Section(
            title: 'Sounds',
            subtitle:
                'Turn sounds on and off, and put them in the order your '
                'scheme teaches them.',
            child: _SoundList(app: app),
          ),
          _Section(
            title: 'The game',
            child: Column(
              children: [
                _SliderRow(
                  label: 'Pantry size',
                  value: settings.pantrySize.toDouble(),
                  min: AppSettings.minPantrySize.toDouble(),
                  max: AppSettings.maxPantrySize.toDouble(),
                  divisions:
                      AppSettings.maxPantrySize - AppSettings.minPantrySize,
                  valueLabel: '${settings.pantrySize} items',
                  onChanged: (value) => app.updateSettings(
                    settings.copyWith(pantrySize: value.round()),
                  ),
                ),
                SwitchListTile(
                  value: settings.showLetters,
                  title: const Text('Show letters (Phase 2)'),
                  subtitle: const Text(
                    'Off for Phase One. Letters are introduced in Phase 2, so '
                    'the game is sounds and pictures only until you turn this '
                    'on.',
                  ),
                  onChanged: (value) =>
                      app.updateSettings(settings.copyWith(showLetters: value)),
                ),
                const ListTile(
                  title: Text('How children add items'),
                  subtitle: Text(
                    'Dragging is the activity; tapping always works too.',
                  ),
                ),
                SegmentedButton<InputMode>(
                  segments: const [
                    ButtonSegment(
                      value: InputMode.dragAndTap,
                      label: Text('Drag or tap'),
                    ),
                    ButtonSegment(
                      value: InputMode.tapOnly,
                      label: Text('Tap only'),
                    ),
                  ],
                  selected: {settings.inputMode},
                  onSelectionChanged: (selection) => app.updateSettings(
                    settings.copyWith(inputMode: selection.first),
                  ),
                ),
              ],
            ),
          ),
          _Section(
            title: 'Sound and motion',
            child: Column(
              children: [
                _SliderRow(
                  label: 'Volume',
                  value: settings.volume,
                  min: 0,
                  max: 1,
                  divisions: 10,
                  valueLabel: '${(settings.volume * 100).round()}%',
                  onChanged: (value) =>
                      app.updateSettings(settings.copyWith(volume: value)),
                ),
                SwitchListTile(
                  value: settings.reducedMotion,
                  title: const Text('Reduce motion'),
                  subtitle: const Text(
                    'Calmer animation. The app already follows the device '
                    'setting; this turns it down as well.',
                  ),
                  onChanged: (value) => app.updateSettings(
                    settings.copyWith(reducedMotion: value),
                  ),
                ),
                SwitchListTile(
                  value: settings.whiteboardMode,
                  title: const Text('Whiteboard mode'),
                  subtitle: const Text(
                    'Extra-large and adult-paced, for group sessions. The '
                    'chef waits for you instead of moving on by itself.',
                  ),
                  onChanged: (value) => app.updateSettings(
                    settings.copyWith(whiteboardMode: value),
                  ),
                ),
              ],
            ),
          ),
          _Section(
            title: 'Mirror',
            child: SwitchListTile(
              value: settings.mirrorModeEnabled,
              title: const Text('Mirror in "Watch my mouth"'),
              subtitle: const Text(
                'Shows the front camera as a live mirror so a child can watch '
                'their own mouth. Live view only: nothing is recorded, saved '
                'or sent anywhere, and the microphone is never opened.',
              ),
              onChanged: (value) => app.updateSettings(
                settings.copyWith(mirrorModeEnabled: value),
              ),
            ),
          ),
          _Section(
            title: 'Extensions',
            subtitle:
                'These are NOT part of the original Letters and Sounds '
                'activity. The core game has no right or wrong answers; these '
                'modes do. Arriving in Stage 3.',
            child: Column(
              children: [
                for (final mode in ExtensionMode.values)
                  SwitchListTile(
                    value: settings.isExtensionEnabled(mode),
                    title: Text(mode.label),
                    subtitle: const Text('Not built yet'),
                    onChanged: null,
                  ),
              ],
            ),
          ),
          const _Section(
            title: 'Your own sounds and words',
            subtitle:
                'Record your own sounds, add words with photos, and move a '
                'sound pack between devices. Arriving in Stage 2 — the data '
                'model and the import checks are already in place.',
            child: SizedBox.shrink(),
          ),
          const _Section(
            title: 'Look, listen and note',
            subtitle:
                'A short observation checklist for the adult, stored on this '
                'device only and using initials rather than full names. '
                'Arriving in Stage 2.',
            child: SizedBox.shrink(),
          ),
          _ContentCheck(app: app),
          _MissingRecordings(app: app),
          const _PrivacyNote(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SoundList extends StatelessWidget {
  const _SoundList({required this.app});
  final AppProvider app;

  @override
  Widget build(BuildContext context) {
    final settings = app.settings;
    final bank = app.bank;

    // Bank order first, then anything the adult has ordered explicitly.
    final ordered = <PhonemeSound>[];
    final byId = {for (final sound in bank.visibleSounds) sound.id: sound};
    for (final id in settings.soundOrder) {
      final sound = byId.remove(id);
      if (sound != null) ordered.add(sound);
    }
    ordered.addAll(byId.values);

    return Column(
      children: [
        for (var index = 0; index < ordered.length; index++)
          _SoundRow(
            app: app,
            sound: ordered[index],
            wordCount: bank.wordsFor(ordered[index].id).length,
            canMoveUp: index > 0,
            canMoveDown: index < ordered.length - 1,
            onMove: (delta) => _move(ordered, index, delta),
          ),
      ],
    );
  }

  void _move(List<PhonemeSound> ordered, int index, int delta) {
    final ids = ordered.map((sound) => sound.id).toList();
    final target = index + delta;
    if (target < 0 || target >= ids.length) return;
    final moved = ids.removeAt(index);
    ids.insert(target, moved);
    app.updateSettings(app.settings.copyWith(soundOrder: ids));
  }
}

class _SoundRow extends StatelessWidget {
  const _SoundRow({
    required this.app,
    required this.sound,
    required this.wordCount,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMove,
  });
  final AppProvider app;
  final PhonemeSound sound;
  final int wordCount;
  final bool canMoveUp;
  final bool canMoveDown;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) {
    final settings = app.settings;
    final enabled = settings.isSoundEnabled(sound.id);
    final thin = wordCount < SoundBank.minWordsPerSound;

    return ListTile(
      leading: SizedBox(
        width: 56,
        child: Text(
          sound.spokenPureSound,
          style: SoupTypography.heading(context).copyWith(fontSize: 20),
        ),
      ),
      title: Text('$wordCount ${wordCount == 1 ? 'word' : 'words'}'),
      subtitle: thin
          ? Text(
              'Too few words to fill the pantry.'
              '${sound.notes.isEmpty ? '' : ' ${sound.notes}'}',
              style: SoupTypography.label(context)
                  .copyWith(color: SoupColours.primary),
            )
          : (sound.notes.isEmpty ? null : Text(sound.notes)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward_rounded),
            onPressed: canMoveUp ? () => onMove(-1) : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward_rounded),
            onPressed: canMoveDown ? () => onMove(1) : null,
          ),
          Switch(
            value: enabled,
            onChanged: (value) {
              final ids = [...settings.enabledSoundIds];
              value ? ids.add(sound.id) : ids.remove(sound.id);
              app.updateSettings(settings.copyWith(enabledSoundIds: ids));
            },
          ),
        ],
      ),
    );
  }
}

class _ContentCheck extends StatelessWidget {
  const _ContentCheck({required this.app});
  final AppProvider app;

  @override
  Widget build(BuildContext context) {
    final issues = app.bankValidation.issues;
    if (issues.isEmpty) return const SizedBox.shrink();

    return _Section(
      title: 'Content check',
      subtitle: 'What the app noticed about the words and sounds it loaded.',
      child: Column(
        children: [
          for (final issue in issues)
            ListTile(
              dense: true,
              leading: Icon(
                issue.isError
                    ? Icons.error_outline_rounded
                    : Icons.info_outline_rounded,
                color: issue.isError
                    ? SoupColours.primary
                    : SoupColours.textSecondary,
              ),
              title: Text(issue.message),
            ),
        ],
      ),
    );
  }
}

class _MissingRecordings extends StatelessWidget {
  const _MissingRecordings({required this.app});
  final AppProvider app;

  @override
  Widget build(BuildContext context) {
    final missing = app.missingClips;

    return _Section(
      title: 'Recordings',
      subtitle: missing.isEmpty
          ? 'Every clip asked for so far has played from a recording.'
          : 'These clips are not in the app yet, so the device voice read '
                'them instead. Run `dart run tool/audio_checklist.dart` for the '
                'full list.',
      child: Column(
        children: [
          for (final clip in missing.take(20))
            ListTile(dense: true, title: Text(clip)),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Privacy',
      child: Text(
        'Silly Soup has no accounts, no analytics and no tracking, and makes '
        'no network calls while it runs. Everything stays on this device. The '
        'camera and microphone are only ever used while a grown-up has turned '
        'them on, and nothing is recorded except audio a grown-up chooses to '
        'save as their own content.',
        style: SoupTypography.body(context),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.child});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: SoupTypography.heading(context)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: SoupTypography.body(context)),
            ],
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: SoupTypography.body(context)),
            Text(valueLabel, style: SoupTypography.label(context)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
