// Lists every audio clip Silly Soup expects, and says which are still
// missing. Run it from the project root:
//
//   dart run tool/audio_checklist.dart
//   dart run tool/audio_checklist.dart --missing-only
//   dart run tool/audio_checklist.dart --csv > recording-list.csv
//
// Exits 1 when anything is missing, so it can gate a release once the
// recordings are meant to be complete.

import 'dart:convert';
import 'dart:io';

const String bankPath = 'assets/data/sound_bank.json';
const String audioRoot = 'assets/audio';
const String songClip = 'assets/audio/song/silly_soup_song.mp3';

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

  final clips = <Clip>[
    for (final sound in sounds)
      if ((sound['audio'] as String? ?? '').isNotEmpty)
        Clip(
          path: '$audioRoot/${sound['audio']}',
          kind: 'phoneme',
          subject: '/${sound['id']}/',
          script:
              'The pure sound: "${pureSound(sound)}". '
              'No "uh" on the end.',
          notes: sound['notes'] as String? ?? '',
        ),
    for (final word in words)
      if ((word['audio'] as String? ?? '').isNotEmpty)
        Clip(
          path: '$audioRoot/${word['audio']}',
          kind: 'word',
          subject: word['word'] as String,
          script: 'The word on its own: "${word['word']}".',
          notes: [
            if (word['hasCluster'] == true) 'Starts with a consonant cluster.',
            if ((word['notes'] as String? ?? '').isNotEmpty)
              word['notes'] as String,
            if (soundsById[word['phoneme']] != null)
              'Sound: /${word['phoneme']}/.',
          ].join(' '),
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
        '\nUntil a clip exists, the app reads that word or sound with the '
        'device voice and logs it in the adult area.',
      );
    }
  }

  exit(missing.isEmpty ? 0 : 1);
}

String pureSound(Map<String, dynamic> sound) {
  final pure = sound['pureSound'] as String? ?? sound['id'] as String;
  return sound['articulation'] == 'stop' ? '$pure-$pure-$pure' : pure;
}

String csvField(String value) {
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}
