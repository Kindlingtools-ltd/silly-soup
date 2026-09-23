import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/models/models.dart';

/// Guards the content that actually ships.
///
/// The phonics rules in the brief are rules about this file, so they are
/// checked here rather than trusted to review.
void main() {
  final raw = File('assets/data/sound_bank.json').readAsStringSync();
  final decoded = json.decode(raw) as Map<String, dynamic>;
  final bank = SoundBank.fromJson(decoded);

  test('the shipped bank passes the same validation as an imported pack', () {
    final result = SoundBank.validate(decoded);

    expect(
      result.errors,
      isEmpty,
      reason: result.errors.map((issue) => issue.message).join('\n'),
    );
  });

  test('the starter set is there, in teaching order', () {
    expect(bank.sounds.map((sound) => sound.id).toList(), [
      's',
      'a',
      't',
      'p',
      'i',
      'n',
      'm',
      'd',
      'b',
    ]);
  });

  test('the Stage 1 sounds are the ones switched on by default', () {
    final on = bank.sounds
        .where((sound) => sound.enabledByDefault)
        .map((sound) => sound.id)
        .toList();

    expect(on, ['s', 'a', 't', 'p', 'b']);
  });

  test('every word sits under a sound the bank actually has', () {
    final ids = bank.sounds.map((sound) => sound.id).toSet();

    for (final word in bank.words) {
      expect(ids, contains(word.phoneme), reason: word.word);
    }
  });

  test('every word has a picture', () {
    for (final word in bank.words) {
      expect(word.image, isNotEmpty, reason: word.word);
    }
  });

  test('every word is spelled in lower case with no stray spaces', () {
    for (final word in bank.words) {
      expect(word.word, word.word.toLowerCase().trim(), reason: word.word);
    }
  });

  test('every word actually starts with the letter of its sound', () {
    // Not a phonics proof — cat/kite under /k/ would be fine — but it does
    // catch a word filed under the wrong sound by mistake.
    for (final word in bank.words) {
      final sound = bank.soundById(word.phoneme)!;
      expect(
        word.word.startsWith(word.emphasisGrapheme),
        isTrue,
        reason: '${word.word} under /${sound.id}/',
      );
    }
  });

  test('no pure sound has picked up an added "uh"', () {
    for (final sound in bank.sounds) {
      expect(sound.pureSound.endsWith('uh'), isFalse, reason: sound.id);
      expect(sound.pureSound.endsWith('er'), isFalse, reason: sound.id);
    }
  });

  test('every sound tells a child what to do with their mouth', () {
    for (final sound in bank.sounds) {
      expect(sound.mouthTip, isNotEmpty, reason: sound.id);
      expect(sound.action, isNotEmpty, reason: sound.id);
    }
  });

  test('every sound that is on by default can fill the biggest pantry', () {
    for (final sound in bank.sounds.where((s) => s.enabledByDefault)) {
      expect(
        bank.wordsFor(sound.id).length,
        greaterThanOrEqualTo(AppSettings.maxPantrySize),
        reason: 'sound ${sound.id} cannot fill a 10-item shelf',
      );
    }
  });

  test('a sound with too few words is off by default and says why', () {
    for (final sound in bank.underfilledSounds) {
      expect(sound.enabledByDefault, isFalse, reason: sound.id);
      expect(sound.notes, isNotEmpty, reason: sound.id);
    }
  });

  test('cluster words are flagged, not hidden', () {
    final clusters = bank.words
        .where((word) => word.hasCluster)
        .map((w) => w.word);

    expect(clusters, isNotEmpty);
    for (final word in bank.words.where((word) => word.hasCluster)) {
      expect(word.notes, isNotEmpty, reason: '${word.word} needs a note');
    }
  });

  test('a word that starts with two consonants is flagged as a cluster', () {
    const vowels = {'a', 'e', 'i', 'o', 'u'};

    for (final word in bank.words) {
      if (word.word.length < 2) continue;
      final startsWithTwoConsonants =
          !vowels.contains(word.word[0]) &&
          !vowels.contains(word.word[1]) &&
          // "th", "sh", "ch" and doubled letters are single sounds, and
          // "y" after a consonant is a vowel here.
          !{'th', 'sh', 'ch', 'ph', 'wh'}.contains(word.word.substring(0, 2)) &&
          word.word[0] != word.word[1] &&
          word.word[1] != 'y';

      if (startsWithTwoConsonants) {
        expect(word.hasCluster, isTrue, reason: word.word);
      }
    }
  });

  test('the chef can model b with banana, bee and bug', () {
    final bWords = bank.wordsFor('b').map((word) => word.word);

    expect(bWords, containsAll(['banana', 'bee', 'bug']));
  });

  test('sounds that are easy to confuse carry a note for the adult', () {
    for (final id in ['m', 'n', 'b', 'p', 'd', 't']) {
      final sound = bank.soundById(id);
      if (sound == null) continue;
      expect(sound.notes, isNotEmpty, reason: '/$id/ needs a pairing note');
    }
  });

  test('every word points at a clip path, so the checklist can find it', () {
    for (final word in bank.words) {
      expect(word.audio, isNotNull, reason: word.word);
      expect(
        word.audioAssetPath,
        startsWith('assets/audio/words/'),
        reason: word.word,
      );
    }
  });
}
