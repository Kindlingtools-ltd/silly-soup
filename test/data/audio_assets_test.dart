import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/models/models.dart';

/// Guards the recordings that ship.
///
/// Audio is the most important part of this app, so a missing or truncated
/// clip should fail the build rather than quietly fall back to the device
/// voice in a classroom.
///
/// What the clips actually *sound* like is checked where it can be measured:
/// `uv run tool/build_audio.py --audit` reads every one back and fails on a
/// pure sound that has picked up a vowel. This file checks the things a
/// checkout can check — that every clip the app will ask for is present,
/// playable, and listed in the manifest the app reads at startup.
void main() {
  final bank = SoundBank.fromJson(
    json.decode(File('assets/data/sound_bank.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  /// Smaller than this is not a word — it is a glitch.
  const minimumClipBytes = 2000;

  bool looksLikeMp3(File file) {
    final head = file.readAsBytesSync().take(3).toList();
    if (head.length < 3) return false;
    if (head[0] == 0x49 && head[1] == 0x44 && head[2] == 0x33) return true;
    return head[0] == 0xFF && (head[1] & 0xE0) == 0xE0;
  }

  List<String> missingFrom(Iterable<String> paths) => [
    for (final path in paths)
      if (!File(path).existsSync() ||
          File(path).lengthSync() < minimumClipBytes)
        path,
  ];

  test('every sound in the bank has a recorded pure sound', () {
    // These are the whole point of the app. They used to be absent, because
    // asking the engine for "sss" got back the letter name "S S S"; they are
    // now cut from real words, so they exist and they are sounds.
    final paths = [
      for (final sound in bank.sounds)
        if (sound.audioAssetPath != null) sound.audioAssetPath!,
    ];

    expect(paths, hasLength(bank.sounds.length));
    expect(missingFrom(paths), isEmpty);
  });

  test('every word has a recording of the word on its own', () {
    expect(
      missingFrom([
        for (final word in bank.words)
          if (word.audioAssetPath != null) word.audioAssetPath!,
      ]),
      isEmpty,
    );
  });

  test('every word has the chef\'s commentary recorded', () {
    // "In goes a sssun!" — said after every single ingredient, and the line
    // a child hears more than any other.
    expect(
      missingFrom([
        for (final word in bank.words) ChefLine.commentary(word.word),
      ]),
      isEmpty,
    );
  });

  test('every word has a list-item recording, so any soup can be recited', () {
    expect(
      missingFrom([
        for (final word in bank.words) ChefLine.listItem(word.word),
      ]),
      isEmpty,
    );
  });

  test('every sound has its action recorded', () {
    expect(
      missingFrom([
        for (final sound in bank.sounds)
          if (sound.action.isNotEmpty) ChefLine.action(sound.id),
      ]),
      isEmpty,
    );
  });

  test('the chef\'s fixed lines are all recorded', () {
    const keys = [
      'watch_me',
      'now_you',
      'my_sound_today',
      'in_goes',
      'soup_has',
      'and',
      'in_it',
      'empty_pan',
      'praise_0',
      'praise_1',
      'praise_2',
      'praise_3',
      'praise_4',
      'praise_5',
    ];

    expect(missingFrom(keys.map(ChefLine.line)), isEmpty);
  });

  test('the soup song is recorded', () {
    expect(missingFrom([SoupSong.audioAssetPath]), isEmpty);
  });

  test('every recording is a playable mp3', () {
    final broken = Directory('assets/audio')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.mp3'))
        .where((file) => !looksLikeMp3(file))
        .map((file) => file.path)
        .toList();

    expect(broken, isEmpty);
  });

  test('the manifest and the files on disk agree', () {
    // The app trusts the manifest: it checks a whole line is recorded before
    // playing any of it, so a manifest that promises a clip that is not there
    // means the chef stops mid-sentence.
    final manifest = json.decode(
      File('assets/audio/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final listed = (manifest['clips'] as List)
        .cast<String>()
        .map((path) => 'assets/audio/$path')
        .toSet();
    final onDisk = Directory('assets/audio')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.mp3'))
        .map((file) => file.path)
        .toSet();

    expect(listed.difference(onDisk), isEmpty, reason: 'promised but absent');
    expect(onDisk.difference(listed), isEmpty, reason: 'present but unlisted');
  });

  test('the manifest records which voice the clips were built with', () {
    final manifest = json.decode(
      File('assets/audio/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    expect(manifest['language'], 'en-GB');
    expect(manifest['voice'], isNotEmpty);
  });
}
