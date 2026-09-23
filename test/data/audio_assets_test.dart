import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/models/models.dart';

/// Guards the recordings that ship.
///
/// Audio is the most important part of this app, so a missing or truncated
/// clip should fail the build rather than quietly fall back to the device
/// voice in a classroom.
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

  test('every word in the bank has a real recording', () {
    final missing = <String>[];
    for (final word in bank.words) {
      final path = word.audioAssetPath;
      if (path == null) continue;
      final file = File(path);
      if (!file.existsSync() || file.lengthSync() < minimumClipBytes) {
        missing.add(word.word);
      }
    }

    expect(missing, isEmpty, reason: 'no usable clip for: $missing');
  });

  test('every word recording is a playable mp3', () {
    for (final word in bank.words) {
      final path = word.audioAssetPath;
      if (path == null) continue;
      expect(looksLikeMp3(File(path)), isTrue, reason: word.word);
    }
  });

  test('the soup song is recorded', () {
    final song = File(SoupSong.audioAssetPath);

    expect(song.existsSync(), isTrue);
    expect(song.lengthSync(), greaterThan(minimumClipBytes));
  });

  test('no synthesised pure-sound clips have been committed', () {
    // The voice reads a bare consonant as its letter name — "tee" for /t/ —
    // which is the one mistake this app cannot make. These nine need a human
    // voice, and until then the adult area reports them as missing.
    final strays = Directory('assets/audio/phonemes')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.mp3'))
        .map((file) => file.path)
        .toList();

    expect(strays, isEmpty, reason: 'letter names would be taught as sounds');
  });
}
