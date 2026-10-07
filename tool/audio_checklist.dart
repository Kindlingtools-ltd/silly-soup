// Lists every audio clip Silly Soup expects, and says which are still
// missing. Run it from the project root:
//
//   dart run tool/audio_checklist.dart
//   dart run tool/audio_checklist.dart --missing-only
//   dart run tool/audio_checklist.dart --csv > recording-list.csv
//
// Exits 1 when anything is missing, so it can gate a release.
//
// This is the list for a person: each line says what to say into the
// microphone, which is what an adult recording a class's own voice needs. The
// machine-readable version of the same inventory — with the pronunciation and
// the measurements each take has to pass — is tool/audio_specs.py, and
// `python3 tool/generate_audio.py --audit` checks the clips rather than just
// counting them. Keep the paths below in step with ChefVoice, which is what
// the app asks for at runtime; test/data/audio_assets_test.dart fails if they
// drift.

import 'dart:convert';
import 'dart:io';

const String bankPath = 'assets/data/sound_bank.json';
const String scriptPath = 'assets/data/chef_script.json';
const String audioRoot = 'assets/audio';
const String songClip = '$audioRoot/song/silly_soup_song.mp3';

class Clip {
  const Clip({
    required this.path,
    required this.kind,
    required this.subject,
    required this.script,
    this.notes = '',
  });
  final String path;
  final String kind;
  final String subject;

  /// What the person recording should actually say.
  final String script;

  final String notes;

  bool get exists => File(path).existsSync();
}

void main(List<String> args) {
  final missingOnly = args.contains('--missing-only');
  final asCsv = args.contains('--csv');

  final bankFile = File(bankPath);
  if (!bankFile.existsSync()) {
    stderr.writeln('Could not find $bankPath. Run this from the project root.');
    exit(2);
  }

  final bank = json.decode(bankFile.readAsStringSync()) as Map<String, dynamic>;
  final sounds = (bank['sounds'] as List).cast<Map<String, dynamic>>();
  final words = (bank['words'] as List).cast<Map<String, dynamic>>();
  final soundsById = {for (final sound in sounds) sound['id'] as String: sound};

  final scriptFile = File(scriptPath);
  final chefScript = scriptFile.existsSync()
      ? json.decode(scriptFile.readAsStringSync()) as Map<String, dynamic>
      : const <String, dynamic>{};
  final phrases = (chefScript['phrases'] as Map<String, dynamic>?) ?? const {};
  final praise = (chefScript['praise'] as List?)?.cast<String>() ?? const [];

  final clips = <Clip>[
    for (final sound in sounds)
      if ((sound['audio'] as String? ?? '').isNotEmpty)
        Clip(
          path: '$audioRoot/${sound['audio']}',
          kind: 'phoneme',
          subject: '/${sound['id']}/',
          script: 'The pure sound: "${pureSound(sound)}". No "uh" on the end.',
          notes: [
            if ((sound['pronunciation'] as String? ?? '').isNotEmpty)
              'IPA ${sound['pronunciation']}.',
            if ((sound['notes'] as String? ?? '').isNotEmpty)
              sound['notes'] as String,
          ].join(' '),
        ),
    for (final sound in sounds)
      if ((sound['action'] as String? ?? '').isNotEmpty)
        Clip(
          path: '$audioRoot/actions/${sound['id']}.mp3',
          kind: 'action',
          subject: '/${sound['id']}/ action',
          script: '"${sound['action']}"',
        ),
    for (final word in words)
      if ((word['audio'] as String? ?? '').isNotEmpty)
        Clip(
          path: '$audioRoot/${word['audio']}',
          kind: 'word',
          subject: word['word'] as String,
          script: 'The word on its own: "${word['word']}".',
          notes: wordNotes(word, soundsById),
        ),
    for (final word in words)
      Clip(
        path: '$audioRoot/emphasis/${word['word']}.mp3',
        kind: 'emphasis',
        subject: '${word['word']}, first sound emphasised',
        script:
            'The chef\'s recital form: '
            '"${emphasised(word, soundsById[word['phoneme']])}".',
        notes: wordNotes(word, soundsById),
      ),
    for (final entry in phrases.entries)
      Clip(
        path: '$audioRoot/phrases/${entry.key}.mp3',
        kind: 'phrase',
        subject: entry.key,
        script: '"${entry.value}"',
        notes: 'Part of a sentence built from several clips — keep it even.',
      ),
    for (var i = 0; i < praise.length; i++)
      Clip(
        path: '$audioRoot/praise/$i.mp3',
        kind: 'praise',
        subject: 'praise $i',
        script: '"${praise[i]}"',
        notes: 'Warm and delighted. Never a correction.',
      ),
    const Clip(
      path: songClip,
      kind: 'song',
      subject: 'The Silly Soup Song',
      script:
          'Sung to the tune of "Pop Goes the Weasel". '
          'Original words — see lib/models/soup_song.dart.',
    ),
  ];

  final missing = clips.where((clip) => !clip.exists).toList();
  final shown = missingOnly ? missing : clips;

  if (asCsv) {
    stdout.writeln('status,kind,subject,path,script,notes');
    for (final clip in shown) {
      stdout.writeln(
        [
          clip.exists ? 'recorded' : 'missing',
          clip.kind,
          clip.subject,
          clip.path,
          clip.script,
          clip.notes,
        ].map(csvField).join(','),
      );
    }
  } else {
    stdout.writeln('Silly Soup audio checklist');
    stdout.writeln('=' * 60);
    var lastKind = '';
    for (final clip in shown) {
      if (clip.kind != lastKind) {
        lastKind = clip.kind;
        stdout.writeln('\n${lastKind.toUpperCase()}S');
      }
      stdout.writeln('  [${clip.exists ? 'x' : ' '}] ${clip.path}');
      stdout.writeln('      ${clip.subject} — ${clip.script}');
      if (clip.notes.trim().isNotEmpty) {
        stdout.writeln('      note: ${clip.notes.trim()}');
      }
    }

    stdout.writeln('\n${'=' * 60}');
    stdout.writeln(
      '${clips.length - missing.length} of ${clips.length} recorded, '
      '${missing.length} still to do.',
    );
    if (missing.isNotEmpty) {
      stdout.writeln(
        '\nUntil a clip exists, the chef says that line with the device voice '
        'and logs it in the adult area.',
      );
    }
  }

  exit(missing.isEmpty ? 0 : 1);
}

String pureSound(Map<String, dynamic> sound) {
  final pure = sound['pureSound'] as String? ?? sound['id'] as String;
  return sound['articulation'] == 'stop' ? '$pure-$pure-$pure' : pure;
}

/// What the chef says for one ingredient: "a sssun", "a b-b-banana".
/// Mirrors RecitalService.emphasise with the article in front, which is how
/// the clip is recorded so a list of them reads as English.
String emphasised(Map<String, dynamic> word, Map<String, dynamic>? sound) {
  final text = word['word'] as String;
  final grapheme =
      (word['initialGrapheme'] as String?)?.trim().isNotEmpty == true
      ? (word['initialGrapheme'] as String).trim()
      : (text.isEmpty ? '' : text[0]);
  final article = sound?['isVowel'] == true ? 'an' : 'a';
  if (grapheme.isEmpty) return '$article $text';
  if (sound?['articulation'] == 'stop') {
    return '$article $grapheme-$grapheme-$text';
  }
  final rest = text.length >= grapheme.length
      ? text.substring(grapheme.length)
      : '';
  return '$article ${grapheme * 3}$rest';
}

String wordNotes(Map<String, dynamic> word, Map<String, dynamic> soundsById) =>
    [
      if ((word['pronunciation'] as String? ?? '').isNotEmpty)
        'IPA ${word['pronunciation']}.',
      if (word['hasCluster'] == true) 'Starts with a consonant cluster.',
      if ((word['notes'] as String? ?? '').isNotEmpty) word['notes'] as String,
      if (soundsById[word['phoneme']] != null) 'Sound: /${word['phoneme']}/.',
    ].join(' ');

String csvField(String value) {
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}
