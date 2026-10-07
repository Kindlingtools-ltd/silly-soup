import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/models/models.dart';
import 'package:silly_soup/services/services.dart';

import '../test_data.dart';

/// What the chef says, and which recordings say it.
///
/// The rule every test here is checking: the clips and the words always mean
/// the same thing. An adult reads the caption out loud while the clip plays,
/// so a line that says one thing and sounds like another is a phonics error
/// rather than a cosmetic one.
void main() {
  final sun = word('sun', 's', audio: 'words/sun.mp3');
  final sock = word('sock', 's', audio: 'words/sock.mp3');
  final sausage = word('sausage', 's', audio: 'words/sausage.mp3');
  final banana = word('banana', 'b', audio: 'words/banana.mp3');
  final apple = word('apple', 'a', audio: 'words/apple.mp3');

  final voice = fullyRecordedVoice(
    sounds: [soundS, soundB, soundA],
    words: [sun, sock, sausage, banana, apple],
  );

  group('the pure sound', () {
    test('comes from its own recording', () {
      final said = voice.pureSound(soundS);

      expect(said.clips, ['assets/audio/phonemes/s.mp3']);
      expect(said.text, 'sss');
    });

    test('is spoken when the sound has no recording at all', () {
      // soundB in the test bank has no audio field.
      final said = voice.pureSound(soundB);

      expect(said.clips, isEmpty);
      expect(said.text, 'b-b-b');
    });
  });

  group('one item going in', () {
    test('is "In goes" followed by the word with its sound stretched', () {
      final said = voice.commentateOnItem(sun, soundS);

      expect(said.clips, [
        'assets/audio/phrases/inGoes.mp3',
        'assets/audio/emphasis/sun.mp3',
      ]);
      expect(said.text, 'In goes a sssun!');
    });

    test('bounces a stop instead of stretching it', () {
      final said = voice.commentateOnItem(banana, soundB);

      expect(said.clips.last, 'assets/audio/emphasis/banana.mp3');
      expect(said.text, 'In goes a b-b-banana!');
    });

    test('says "an" before a vowel sound', () {
      final said = voice.commentateOnItem(apple, soundA);

      expect(said.text, 'In goes an aaapple!');
    });
  });

  group('the growing list', () {
    test('is one carrier phrase and then every item, in order', () {
      final said = voice.reciteList([sun, sock, sausage], soundS);

      expect(said.clips, [
        'assets/audio/phrases/inGoes.mp3',
        'assets/audio/emphasis/sun.mp3',
        'assets/audio/emphasis/sock.mp3',
        'assets/audio/emphasis/sausage.mp3',
      ]);
      expect(said.text, 'In goes a sssun… a sssock… a sssausage…');
    });

    test('an empty pot is not something to say', () {
      expect(voice.reciteList(const [], soundS).isEmpty, isTrue);
    });
  });

  group('the read-back at tasting time', () {
    test('puts "and" in front of the last ingredient, as the caption does', () {
      final said = voice.reciteFinishedSoup([sun, sock, sausage], soundS);

      expect(said.clips, [
        'assets/audio/phrases/yourSoupHas.mp3',
        'assets/audio/emphasis/sun.mp3',
        'assets/audio/emphasis/sock.mp3',
        'assets/audio/phrases/and.mp3',
        'assets/audio/emphasis/sausage.mp3',
        'assets/audio/phrases/inIt.mp3',
      ]);
      expect(said.text, contains('and a sssausage in it!'));
    });

    test('a single ingredient needs no "and"', () {
      final said = voice.reciteFinishedSoup([sun], soundS);

      expect(said.clips, isNot(contains('assets/audio/phrases/and.mp3')));
      expect(said.text, 'Your silly soup has a sssun in it!');
    });

    test('an empty pan gets its own kind line', () {
      final said = voice.reciteFinishedSoup(const [], soundS);

      expect(said.clips, ['assets/audio/phrases/emptyPan.mp3']);
      expect(said.text.toLowerCase(), isNot(contains('wrong')));
    });
  });

  group('when a recording is missing', () {
    test('the whole line is spoken rather than part of it played', () {
      // Every phrase is recorded, but this word's emphasis clip is not.
      final patchy = ChefVoice(
        script: testScript,
        catalogue: ClipCatalogue({
          ChefVoice.phraseClip(ChefScript.inGoes),
          ChefVoice.emphasisClip(sun),
        }),
      );

      final said = patchy.reciteList([sun, sock], soundS);

      expect(said.clips, isEmpty);
      expect(said.text, 'In goes a sssun… a sssock…');
    });

    test('a chef with no catalogue at all still has every line', () {
      const none = ChefVoice(script: testScript);

      expect(none.commentateOnItem(sun, soundS).clips, isEmpty);
      expect(none.commentateOnItem(sun, soundS).text, isNotEmpty);
      expect(none.praise(0).text, isNotEmpty);
    });
  });

  test('praise cycles through the script and never marks a child wrong', () {
    final lines = [
      for (var i = 0; i < testScript.praise.length; i++) voice.praise(i),
    ];

    expect(lines.map((line) => line.clips.single).toSet(), hasLength(3));
    for (final line in lines) {
      expect(line.text.toLowerCase(), isNot(contains('wrong')));
    }
  });

  test('a chef with no script says nothing rather than something empty', () {
    const mute = ChefVoice();

    expect(mute.praise(0).isEmpty, isTrue);
    expect(mute.phrase(ChefScript.inGoes).isEmpty, isTrue);
  });
}
