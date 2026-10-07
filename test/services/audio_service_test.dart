import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/models/models.dart';
import 'package:silly_soup/services/services.dart';

import '../test_data.dart';

void main() {
  group('clips come first', () {
    test('plays the recording when there is one', () async {
      final sink = RecordingAudioSink(
        availableAssets: {'assets/audio/phonemes/s.mp3'},
      );
      final audio = AudioService(sink: sink);

      await audio.playSound(soundS);

      expect(sink.playedAssets, ['assets/audio/phonemes/s.mp3']);
      expect(sink.spokenText, isEmpty);
      expect(audio.missingClips, isEmpty);
    });

    test(
      'falls back to the voice when the clip is missing, and logs it',
      () async {
        final sink = RecordingAudioSink();
        final audio = AudioService(sink: sink);

        await audio.playSound(soundS);

        expect(sink.playedAssets, isEmpty);
        expect(sink.spokenText, ['sss']);
        expect(audio.missingClips, ['assets/audio/phonemes/s.mp3']);
      },
    );

    test(
      'a missing clip is logged once, however often it is asked for',
      () async {
        final audio = AudioService(sink: RecordingAudioSink());

        await audio.playSound(soundS);
        await audio.playSound(soundS);
        await audio.playSound(soundS);

        expect(audio.missingClips, hasLength(1));
      },
    );

    test('a sound with no clip at all just speaks, and logs nothing', () async {
      final sink = RecordingAudioSink();
      final audio = AudioService(sink: sink);

      await audio.playSound(soundB); // no audio field

      expect(sink.spokenText, ['b-b-b']);
      expect(audio.missingClips, isEmpty);
    });

    test('a word plays its own recording when there is one', () async {
      final sink = RecordingAudioSink(
        availableAssets: {'assets/audio/words/sun.mp3'},
      );
      final audio = AudioService(sink: sink);

      await audio.playWord(word('sun', 's', audio: 'words/sun.mp3'));

      expect(sink.playedAssets, ['assets/audio/words/sun.mp3']);
    });
  });

  group('a chef line is played, not spoken', () {
    final commentary = ChefScript.commentateOnItem(word('sun', 's'), soundS);

    test('plays every clip in the line, in order', () async {
      final sink = RecordingAudioSink(
        availableAssets: {
          'assets/audio/lines/in_goes.mp3',
          'assets/audio/list/sun.mp3',
          'assets/audio/list/sock.mp3',
        },
      );
      final audio = AudioService(
        sink: sink,
        clips: ClipLibrary.withClips(const {
          'assets/audio/lines/in_goes.mp3',
          'assets/audio/list/sun.mp3',
          'assets/audio/list/sock.mp3',
        }),
      );

      await audio.say(
        ChefScript.reciteList([word('sun', 's'), word('sock', 's')], soundS),
      );

      expect(sink.playedAssets, [
        'assets/audio/lines/in_goes.mp3',
        'assets/audio/list/sun.mp3',
        'assets/audio/list/sock.mp3',
      ]);
      expect(sink.spokenText, isEmpty);
    });

    test('speaks the whole line when a recording is missing', () async {
      final sink = RecordingAudioSink();
      final audio = AudioService(sink: sink);

      await audio.say(commentary);

      expect(sink.playedAssets, isEmpty);
      expect(sink.spokenText, ['In goes a sssun!']);
      expect(audio.missingClips, ['assets/audio/commentary/sun.mp3']);
    });

    test(
      'a part-recorded line is spoken rather than played in pieces',
      () async {
        // Half a recital is worse than none: the child hears "In goes" and
        // then silence, and speaking it afterwards repeats what they heard.
        final sink = RecordingAudioSink(
          availableAssets: {'assets/audio/lines/in_goes.mp3'},
        );
        final audio = AudioService(
          sink: sink,
          clips: ClipLibrary.withClips(const {
            'assets/audio/lines/in_goes.mp3',
          }),
        );

        await audio.say(ChefScript.reciteList([word('sun', 's')], soundS));

        expect(sink.playedAssets, isEmpty);
        expect(sink.spokenText, ['In goes a sssun…']);
      },
    );

    test('an empty line asks the sink for nothing at all', () async {
      final sink = RecordingAudioSink();
      final audio = AudioService(sink: sink);

      await audio.say(ChefScript.reciteList(const [], soundS));

      expect(sink.playedAssets, isEmpty);
      expect(sink.spokenText, isEmpty);
    });
  });

  group('the song', () {
    test('an adult recording wins over the bundled one', () async {
      final sink = RecordingAudioSink(
        availableAssets: {'custom/our-song.m4a', SoupSong.audioAssetPath},
      );
      final audio = AudioService(sink: sink);

      await audio.playSong(customRecordingPath: 'custom/our-song.m4a');

      expect(sink.playedAssets, ['custom/our-song.m4a']);
    });

    test('with no recording anywhere the words are spoken', () async {
      final sink = RecordingAudioSink();
      final audio = AudioService(sink: sink);

      await audio.playSong();

      expect(sink.spokenText, [SoupSong.spokenLyrics]);
      expect(audio.missingClips, [SoupSong.audioAssetPath]);
    });
  });

  test('volume is passed straight through to whatever is playing', () async {
    final sink = RecordingAudioSink();
    final audio = AudioService(sink: sink)..volume = 0.3;

    await audio.speak('hello');

    expect(sink.spokenText, ['hello']);
  });

  group('a device with no voice', () {
    test('does not leave the chef waiting forever', () async {
      final sink = SilentSink();
      final audio = AudioService(sink: sink);

      // The bug this guards: awaiting speech completion froze the game on a
      // device that never reports completion, because it never speaks.
      await audio
          .speak('hello')
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => fail('speak() never returned'),
          );

      expect(sink.stopCount, greaterThan(0));
    });

    test('stops waiting once it is clear nothing is being spoken', () async {
      final audio = AudioService(sink: SilentSink());

      expect(audio.voiceIsSilent, isFalse);

      final started = DateTime.now();
      for (var i = 0; i < 5; i++) {
        await audio.speak('In goes a b-b-banana!');
      }
      final elapsed = DateTime.now().difference(started);

      expect(audio.voiceIsSilent, isTrue);
      // Five full budgets would be about half a minute. A child watching a
      // silent tablet should not wait that long for the chef to get going.
      expect(elapsed.inSeconds, lessThan(15));
    });

    test('the budget scales with how much there is to say', () {
      final short = AudioService.budgetFor('sss');
      final long = AudioService.budgetFor(
        'In goes a b-b-banana… a b-b-bee… a b-b-bug… a b-b-ball…',
      );

      expect(long, greaterThan(short));
      expect(short.inSeconds, greaterThanOrEqualTo(2));
      expect(long.inSeconds, lessThanOrEqualTo(25));
    });
  });

  test('a silent device still plays its recordings', () async {
    final sink = RecordingAudioSink(
      availableAssets: {'assets/audio/commentary/sun.mp3'},
    );
    final audio = AudioService(
      sink: sink,
      clips: ClipLibrary.withClips(const {'assets/audio/commentary/sun.mp3'}),
    );

    // A device whose voice does not work is exactly the device that needs the
    // recordings, and they do not go through the voice at all.
    await audio.say(ChefScript.commentateOnItem(word('sun', 's'), soundS));
    expect(sink.playedAssets, ['assets/audio/commentary/sun.mp3']);
    expect(sink.spokenText, isEmpty);

    final silent = AudioService(sink: SilentSink());
    await silent.speak('one');
    await silent.speak('two');
    expect(silent.voiceIsSilent, isTrue);

    final recovered = AudioService(sink: sink);
    for (var i = 0; i < 2; i++) {
      await recovered.speak('x');
    }
    expect(sink.spokenText, contains('x'));
  });

  test('stop reaches the sink so a child never has to wait', () async {
    final sink = RecordingAudioSink();

    await AudioService(sink: sink).stop();

    expect(sink.stopCount, 1);
  });

  group('unlocking the sound', () {
    test('the first touch is spent on making sound possible', () async {
      final sink = RecordingAudioSink();
      final audio = AudioService(sink: sink);

      expect(audio.isUnlocked, isFalse);
      await audio.unlock();

      expect(sink.unlockCount, 1);
      expect(audio.isUnlocked, isTrue);
    });

    test('later touches do not ask again', () async {
      final sink = RecordingAudioSink();
      final audio = AudioService(sink: sink);

      await audio.unlock();
      await audio.unlock();
      await audio.unlock();

      expect(sink.unlockCount, 1);
    });

    test(
      'a voice written off before the first touch gets another chance',
      () async {
        // A browser refuses to speak until the page is touched, and refuses
        // silently. Those refusals used to convince the app the device had no
        // voice at all, and it then played the whole game without one.
        final sink = SilentSink();
        final audio = AudioService(sink: sink);

        await audio.speak('sss');
        await audio.speak('mmm');
        expect(audio.voiceIsSilent, isTrue);

        await audio.unlock();

        expect(audio.voiceIsSilent, isFalse);
      },
    );
  });
}

/// A sink that accepts an utterance and never finishes it — a device with no
/// voice installed, or a browser refusing to speak before the first tap.
class SilentSink implements AudioSink {
  int stopCount = 0;
  int unlockCount = 0;

  @override
  Future<bool> playAsset(String assetPath, {required double volume}) async =>
      false;

  @override
  Future<void> speak(String text, {required double volume}) =>
      Completer<void>().future;

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<void> unlock() async => unlockCount++;

  @override
  Future<void> dispose() async {}
}
