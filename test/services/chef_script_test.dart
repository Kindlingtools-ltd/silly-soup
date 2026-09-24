import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/services/services.dart';

import '../test_data.dart';

/// What the chef says, and which recordings say it.
///
/// Every line carries both, because the words are what goes on screen and
/// what a device with no recordings falls back to. A line whose text and
/// clips disagree would show one thing and say another.
void main() {
  final sun = word('sun', 's');
  final sock = word('sock', 's');
  final seal = word('seal', 's');

  group('a line is recorded and readable', () {
    test('the commentary is one clip per word', () {
      final line = ChefScript.commentateOnItem(sun, soundS);

      expect(line.text, 'In goes a sssun!');
      expect(line.clips, ['assets/audio/commentary/sun.mp3']);
    });

    test('the fixed lines name their own recording', () {
      expect(ChefScript.watchMe.clips, ['assets/audio/lines/watch_me.mp3']);
      expect(ChefScript.nowYou.clips, ['assets/audio/lines/now_you.mp3']);
    });

    test('praise picks the clip that matches the words', () {
      for (var seed = 0; seed < 12; seed++) {
        final line = ChefScript.praise(seed);
        final index = seed % RecitalService.praiseLines.length;

        expect(line.text, RecitalService.praiseLines[index]);
        expect(line.clips, ['assets/audio/lines/praise_$index.mp3']);
      }
    });

    test('the sound of the day plays the words, then the sound itself', () {
      final line = ChefScript.soundOfTheDay(soundS);

      expect(line.text, 'My sound today is sss.');
      expect(line.clips, [
        'assets/audio/lines/my_sound_today.mp3',
        'assets/audio/phonemes/s.mp3',
      ]);
    });

    test('a sound with no recording of its own has no clips to play', () {
      // soundB carries no `audio` field, so there is nothing to chain.
      expect(ChefScript.soundOfTheDay(soundB).clips, isEmpty);
    });

    test('an action is the words and the recording of them', () {
      final wiggly = soundS.copyWith(action: 'Wiggle like a snake.');

      expect(ChefScript.soundAction(wiggly).text, 'Wiggle like a snake.');
      expect(ChefScript.soundAction(wiggly).clips, [
        'assets/audio/actions/s.mp3',
      ]);
    });

    test('a sound with no action asks for no recording', () {
      expect(ChefScript.soundAction(soundS).clips, isEmpty);
    });
  });

  group('reciting a soup nobody recorded', () {
    test('"In goes", then one clip per ingredient, in order', () {
      final line = ChefScript.reciteList([sun, sock, seal], soundS);

      expect(line.text, 'In goes a sssun… a sssock… a ssseal…');
      expect(line.clips, [
        'assets/audio/lines/in_goes.mp3',
        'assets/audio/list/sun.mp3',
        'assets/audio/list/sock.mp3',
        'assets/audio/list/seal.mp3',
      ]);
    });

    test('an empty pot is not a line at all', () {
      final line = ChefScript.reciteList(const [], soundS);

      expect(line.text, isEmpty);
      expect(line.clips, isEmpty);
    });

    test('the finished soup puts "and" before the last ingredient', () {
      final line = ChefScript.reciteFinishedSoup([sun, sock, seal], soundS);

      expect(line.clips, [
        'assets/audio/lines/soup_has.mp3',
        'assets/audio/list/sun.mp3',
        'assets/audio/list/sock.mp3',
        'assets/audio/lines/and.mp3',
        'assets/audio/list/seal.mp3',
        'assets/audio/lines/in_it.mp3',
      ]);
    });

    test('one ingredient needs no "and"', () {
      final line = ChefScript.reciteFinishedSoup([sun], soundS);

      expect(line.clips, [
        'assets/audio/lines/soup_has.mp3',
        'assets/audio/list/sun.mp3',
        'assets/audio/lines/in_it.mp3',
      ]);
    });

    test('an empty pan has its own line', () {
      final line = ChefScript.reciteFinishedSoup(const [], soundS);

      expect(line.text, contains('empty pan'));
      expect(line.clips, ['assets/audio/lines/empty_pan.mp3']);
    });
  });

  group('the words on screen are the words said', () {
    test('every line spells out what its recordings say', () {
      final lines = [
        ChefScript.watchMe,
        ChefScript.nowYou,
        ChefScript.commentateOnItem(sun, soundS),
        ChefScript.reciteList([sun, sock], soundS),
        ChefScript.reciteFinishedSoup([sun, sock], soundS),
        ChefScript.praise(0),
        ChefScript.soundAction(soundS.copyWith(action: 'Hiss like a snake.')),
      ];

      for (final line in lines) {
        expect(line.text, isNotEmpty, reason: '$line');
        expect(line.clips, isNotEmpty, reason: '$line');
      }
    });

    test('a stop is bounced and a continuant held, in the words too', () {
      expect(
        ChefScript.commentateOnItem(word('banana', 'b'), soundB).text,
        'In goes a b-b-banana!',
      );
      expect(ChefScript.commentateOnItem(sun, soundS).text, contains('sssun'));
    });
  });
}
