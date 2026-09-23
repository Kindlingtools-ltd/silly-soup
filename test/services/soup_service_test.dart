import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/models/models.dart';
import 'package:silly_soup/services/services.dart';

import '../test_data.dart';

void main() {
  group('buildPantry', () {
    test(
      'the core mode never puts an item with a different sound on the shelf',
      () {
        // Run it a lot: the shelf is shuffled, so one pass proves very little.
        for (var seed = 0; seed < 200; seed++) {
          final pantry = SoupService.buildPantry(
            sound: soundS,
            candidates: testBank.words,
            size: 8,
            random: Random(seed),
          );

          expect(pantry, isNotEmpty);
          expect(
            pantry.every((item) => item.phoneme == soundS.id),
            isTrue,
            reason: 'seed $seed produced ${pantry.map((w) => w.word).toList()}',
          );
        }
      },
    );

    test('pantry items are never duplicated', () {
      for (var seed = 0; seed < 200; seed++) {
        final pantry = SoupService.buildPantry(
          sound: soundS,
          candidates: [...testBank.words, ...sWords], // deliberate duplicates
          size: 10,
          random: Random(seed),
        );

        final ids = pantry.map((item) => item.id).toList();
        expect(ids.toSet().length, ids.length, reason: 'seed $seed');
      }
    });

    test('asks for more items than exist and gets what there is', () {
      final pantry = SoupService.buildPantry(
        sound: soundB,
        candidates: testBank.words,
        size: 10,
        random: Random(1),
      );

      expect(pantry.length, bWords.length);
    });

    test('hidden words never reach the shelf', () {
      final pantry = SoupService.buildPantry(
        sound: soundS,
        candidates: [...sWords, word('sausage', 's', hidden: true)],
        size: 10,
        random: Random(3),
      );

      expect(pantry.any((item) => item.word == 'sausage'), isFalse);
    });

    test('cluster words can be filtered out for adults who want that', () {
      final pantry = SoupService.buildPantry(
        sound: soundS,
        candidates: sWords,
        size: 10,
        random: Random(4),
        allowClusters: false,
      );

      expect(pantry.any((item) => item.hasCluster), isFalse);
    });

    test('a distractor that shares the target sound is dropped, not shown', () {
      // Odd-one-out only works if the odd one really is odd.
      final pantry = SoupService.buildPantry(
        sound: soundS,
        candidates: sWords,
        size: 6,
        distractors: [word('sun', 's'), word('banana', 'b')],
        distractorCount: 2,
        random: Random(5),
      );

      final offSound = pantry.where((item) => item.phoneme != soundS.id);
      expect(offSound.length, 1);
      expect(offSound.single.word, 'banana');
    });

    test('the shelf is the size the adult asked for', () {
      final pantry = SoupService.buildPantry(
        sound: soundS,
        candidates: sWords,
        size: 6,
        random: Random(6),
      );

      expect(pantry.length, 6);
    });
  });

  group('buildChefSoup', () {
    test('models with three items, all on the target sound', () {
      for (var seed = 0; seed < 50; seed++) {
        final soup = SoupService.buildChefSoup(
          sound: soundB,
          candidates: testBank.words,
          random: Random(seed),
        );

        expect(soup.length, 3);
        expect(soup.every((item) => item.phoneme == 'b'), isTrue);
        expect(soup.map((item) => item.id).toSet().length, 3);
      }
    });

    test('avoids consonant clusters when it can', () {
      for (var seed = 0; seed < 50; seed++) {
        final soup = SoupService.buildChefSoup(
          sound: soundS,
          candidates: sWords,
          random: Random(seed),
        );

        expect(
          soup.any((item) => item.hasCluster),
          isFalse,
          reason: 'seed $seed',
        );
      }
    });
  });

  group('availableSounds', () {
    test('follows the adult order and drops sounds they switched off', () {
      const settings = AppSettings(
        soundOrder: ['b', 's', 'a'],
        enabledSoundIds: ['s', 'b'],
      );

      final sounds = SoupService.availableSounds(
        bank: testBank,
        settings: settings,
      );

      expect(sounds.map((sound) => sound.id).toList(), ['b', 's']);
    });

    test('a sound the adult never ordered still appears, at the end', () {
      const settings = AppSettings(
        soundOrder: ['s'],
        enabledSoundIds: ['s', 'a'],
      );

      final sounds = SoupService.availableSounds(
        bank: testBank,
        settings: settings,
      );

      expect(sounds.map((sound) => sound.id).toList(), ['s', 'a']);
    });

    test('hidden sounds never reach the picker', () {
      final bank = SoundBank(
        sounds: [soundS, soundB.copyWith(hidden: true)],
        words: testBank.words,
      );
      const settings = AppSettings(enabledSoundIds: ['s', 'b']);

      final sounds = SoupService.availableSounds(
        bank: bank,
        settings: settings,
      );

      expect(sounds.map((sound) => sound.id).toList(), ['s']);
    });
  });
}
