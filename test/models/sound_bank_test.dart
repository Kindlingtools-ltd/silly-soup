import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/models/models.dart';

import '../test_data.dart';

Map<String, dynamic> packJson({
  int schemaVersion = SoundBank.currentSchemaVersion,
  List<Map<String, dynamic>>? sounds,
  List<Map<String, dynamic>>? words,
}) {
  return {
    'schemaVersion': schemaVersion,
    'name': 'pack',
    'sounds':
        sounds ??
        [
          {
            'id': 's',
            'label': 's',
            'grapheme': 's',
            'articulation': 'continuant',
            'pureSound': 'sss',
          },
        ],
    'words':
        words ??
        [
          for (var i = 0; i < SoundBank.minWordsPerSound; i++)
            {'word': 'word$i', 'phoneme': 's', 'image': 'emoji:🍲'},
        ],
  };
}

void main() {
  group('validate', () {
    test('accepts a well-formed pack', () {
      final result = SoundBank.validate(packJson());

      expect(result.isValid, isTrue);
      expect(result.warnings, isEmpty);
    });

    test('rejects something that is not a pack at all', () {
      expect(SoundBank.validate('nope').isValid, isFalse);
      expect(SoundBank.validate(null).isValid, isFalse);
      expect(SoundBank.validate(<String>['a']).isValid, isFalse);
    });

    test('rejects a pack with no schemaVersion', () {
      final json = packJson()..remove('schemaVersion');

      expect(SoundBank.validate(json).isValid, isFalse);
    });

    test('rejects a pack from a newer version of the app', () {
      final result = SoundBank.validate(
        packJson(schemaVersion: SoundBank.currentSchemaVersion + 1),
      );

      expect(result.isValid, isFalse);
      expect(result.errors.first.message, contains('newer version'));
    });

    test('rejects a word with no picture', () {
      final result = SoundBank.validate(
        packJson(
          words: [
            {'word': 'sun', 'phoneme': 's', 'image': ''},
          ],
        ),
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.map((issue) => issue.message).join(),
        contains('needs one'),
      );
    });

    test('rejects a word pointing at a sound the pack does not have', () {
      final result = SoundBank.validate(
        packJson(
          words: [
            {'word': 'banana', 'phoneme': 'b', 'image': 'emoji:🍌'},
          ],
        ),
      );

      expect(result.isValid, isFalse);
    });

    test('rejects the same word twice under one sound', () {
      final result = SoundBank.validate(
        packJson(
          words: [
            for (var i = 0; i < SoundBank.minWordsPerSound; i++)
              {'word': 'word$i', 'phoneme': 's', 'image': 'emoji:🍲'},
            {'word': 'word0', 'phoneme': 's', 'image': 'emoji:🍲'},
          ],
        ),
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.map((issue) => issue.message).join(),
        contains('more than once'),
      );
    });

    test('rejects two sounds with the same id', () {
      final result = SoundBank.validate(
        packJson(
          sounds: [
            {'id': 's', 'pureSound': 'sss'},
            {'id': 's', 'pureSound': 'sss'},
          ],
        ),
      );

      expect(result.isValid, isFalse);
    });

    test('warns, but still imports, when a sound has too few words', () {
      final result = SoundBank.validate(
        packJson(
          words: [
            {'word': 'sun', 'phoneme': 's', 'image': 'emoji:☀️'},
          ],
        ),
      );

      expect(
        result.isValid,
        isTrue,
        reason: 'a thin pantry is the adult\'s call',
      );
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single.message, contains('too few'));
    });

    test('hidden words do not count towards the pantry minimum', () {
      final result = SoundBank.validate(
        packJson(
          words: [
            for (var i = 0; i < SoundBank.minWordsPerSound; i++)
              {'word': 'word$i', 'phoneme': 's', 'image': 'emoji:🍲'},
            {
              'word': 'hidden',
              'phoneme': 's',
              'image': 'emoji:🍲',
              'hidden': true,
            },
          ],
        ),
      );

      expect(result.warnings, isEmpty);
    });
  });

  group('queries', () {
    test('wordsFor returns only that sound, and skips hidden words', () {
      final bank = SoundBank(
        sounds: testBank.sounds,
        words: [...sWords, ...bWords, word('sausage', 's', hidden: true)],
      );

      final words = bank.wordsFor('s');

      expect(words.every((item) => item.phoneme == 's'), isTrue);
      expect(words.any((item) => item.word == 'sausage'), isFalse);
    });

    test('wordsNotFor is the distractor pool for odd-one-out', () {
      expect(
        testBank.wordsNotFor('s').every((item) => item.phoneme != 's'),
        isTrue,
      );
    });

    test('underfilledSounds names the sounds an adult needs to top up', () {
      final bank = SoundBank(
        sounds: [soundS, soundB],
        words: [...sWords, word('banana', 'b')],
      );

      expect(bank.underfilledSounds.map((sound) => sound.id), ['b']);
    });
  });

  group('mergedWith', () {
    test('an adult edit replaces the built-in word, in place', () {
      final overlay = SoundBank(
        words: [
          word('sun', 's').copyWith(notes: 'our own photo', isCustom: true),
        ],
      );

      final merged = testBank.mergedWith(overlay);
      final sun = merged.words.firstWhere((item) => item.word == 'sun');

      expect(sun.notes, 'our own photo');
      expect(merged.words.length, testBank.words.length);
    });

    test('hiding a built-in word keeps it in the bank', () {
      final overlay = SoundBank(
        words: [word('sun', 's').copyWith(hidden: true)],
      );

      final merged = testBank.mergedWith(overlay);

      expect(merged.words.any((item) => item.word == 'sun'), isTrue);
      expect(merged.wordsFor('s').any((item) => item.word == 'sun'), isFalse);
    });

    test('a new sound and its words are appended', () {
      final overlay = SoundBank(
        sounds: [
          const PhonemeSound(
            id: 'sh',
            label: 'sh',
            grapheme: 'sh',
            articulation: Articulation.continuant,
            pureSound: 'shhh',
            isCustom: true,
          ),
        ],
        words: [word('ship', 'sh')],
      );

      final merged = testBank.mergedWith(overlay);

      expect(merged.soundById('sh'), isNotNull);
      expect(merged.wordsFor('sh'), hasLength(1));
      expect(merged.soundById('s'), isNotNull);
    });
  });

  group('json round trip', () {
    test('a bank survives being written and read again', () {
      final restored = SoundBank.fromJson(testBank.toJson());

      expect(
        restored.sounds.map((sound) => sound.id),
        testBank.sounds.map((sound) => sound.id),
      );
      expect(
        restored.words.map((item) => item.id),
        testBank.words.map((item) => item.id),
      );
    });
  });
}
