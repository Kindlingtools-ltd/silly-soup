import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/models/models.dart';
import 'package:silly_soup/services/services.dart';

import '../test_data.dart';

void main() {
  group('pure sounds', () {
    test('a continuant is held on, never given an "uh"', () {
      expect(RecitalService.pureSound(soundS), 'sss');
      expect(RecitalService.pureSound(soundS), isNot(contains('u')));
    });

    test('a stop is bounced, never stretched', () {
      expect(RecitalService.pureSound(soundB), 'b-b-b');
    });

    test('no sound in the shipped starter set picks up an added vowel', () {
      for (final sound in testBank.sounds) {
        expect(
          RecitalService.pureSound(sound).replaceAll('-', ''),
          isNot(anyOf(endsWith('uh'), endsWith('er'))),
        );
      }
    });
  });

  group('emphasise', () {
    test('stretches the first sound of a continuant word', () {
      expect(RecitalService.emphasise(word('sun', 's'), soundS), 'sssun');
      expect(
        RecitalService.emphasise(word('sock', 's'), soundS),
        'ssssock'.replaceFirst('ssss', 'sss'),
      );
    });

    test('stretches across a cluster without losing the rest of the word', () {
      expect(RecitalService.emphasise(word('snake', 's'), soundS), 'sssnake');
      expect(RecitalService.emphasise(word('star', 's'), soundS), 'ssstar');
    });

    test('bounces the first sound of a stop word', () {
      expect(
        RecitalService.emphasise(word('banana', 'b'), soundB),
        'b-b-banana',
      );
      expect(RecitalService.emphasise(word('bug', 'b'), soundB), 'b-b-bug');
    });

    test('uses the spelling of the word, so /k/ works for cat and kite', () {
      const kay = PhonemeSound(
        id: 'k',
        label: 'k',
        grapheme: 'k',
        articulation: Articulation.stop,
        pureSound: 'k',
      );
      const cat = SoupWord(word: 'cat', phoneme: 'k', image: 'emoji:🐱');
      const kite = SoupWord(word: 'kite', phoneme: 'k', image: 'emoji:🪁');

      expect(RecitalService.emphasise(cat, kay), 'c-c-cat');
      expect(RecitalService.emphasise(kite, kay), 'k-k-kite');
    });

    test('handles a two-letter grapheme like sh', () {
      const sh = PhonemeSound(
        id: 'sh',
        label: 'sh',
        grapheme: 'sh',
        articulation: Articulation.continuant,
        pureSound: 'shhh',
      );
      const ship = SoupWord(
        word: 'ship',
        phoneme: 'sh',
        image: 'emoji:🚢',
        initialGrapheme: 'sh',
      );

      expect(RecitalService.emphasise(ship, sh), 'shshship');
    });

    test('an empty word does not crash the chef', () {
      expect(RecitalService.emphasise(word('', 's'), soundS), '');
    });
  });

  group('articles', () {
    test('a consonant sound takes "a"', () {
      expect(RecitalService.article(word('sun', 's'), soundS), 'a');
    });

    test('a vowel sound takes "an"', () {
      expect(RecitalService.article(word('apple', 'a'), soundA), 'an');
    });
  });

  group('reciting the pot', () {
    test('an empty pot has nothing to recite', () {
      expect(RecitalService.reciteList(const [], soundS), '');
    });

    test('recites the growing list in the order the child chose', () {
      final pot = [word('sun', 's'), word('sock', 's'), word('sofa', 's')];

      expect(
        RecitalService.reciteList(pot, soundS),
        'In goes a sssun… a sssock… a sssofa…',
      );
    });

    test('the finished soup reads back as a sentence', () {
      final pot = [word('banana', 'b'), word('bee', 'b'), word('bug', 'b')];

      expect(
        RecitalService.reciteFinishedSoup(pot, soundB),
        'Your silly soup has a b-b-banana, a b-b-bee and a b-b-bug in it!',
      );
    });

    test('one item on its own still reads properly', () {
      expect(
        RecitalService.reciteFinishedSoup([word('sun', 's')], soundS),
        'Your silly soup has a sssun in it!',
      );
    });

    test('even an empty pan gets a kind answer, never a correction', () {
      final line = RecitalService.reciteFinishedSoup(const [], soundS);

      expect(line, isNotEmpty);
      expect(line.toLowerCase(), isNot(contains('wrong')));
    });
  });

  group('praise', () {
    test('praise cycles rather than repeating the same line', () {
      final lines = List.generate(
        RecitalService.praiseLines.length,
        RecitalService.praise,
      );

      expect(lines.toSet().length, RecitalService.praiseLines.length);
    });

    test('no praise line ever marks a child wrong', () {
      for (final line in RecitalService.praiseLines) {
        expect(
          line.toLowerCase(),
          isNot(
            anyOf(
              contains('wrong'),
              contains('no,'),
              contains('try again'),
              contains('nearly'),
            ),
          ),
        );
      }
    });
  });
}
