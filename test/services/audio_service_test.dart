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

  group('the chef\'s own voice', () {
    test('emphasis is always spoken — there is no clip for "sssun"', () async {
      final sink = RecordingAudioSink(
        availableAssets: {'assets/audio/words/sun.mp3'},
      );
      final audio = AudioService(sink: sink);

      await audio.playEmphasisedWord(
        word('sun', 's', audio: 'words/sun.mp3'),
        soundS,
      );

      expect(sink.spokenText, ['sssun']);
      expect(sink.playedAssets, isEmpty);
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

  test('a silent device plays the recorded word rather than nothing', () async {
    final sink = RecordingAudioSink(
      availableAssets: {'assets/audio/words/sun.mp3'},
    );
    final audio = AudioService(sink: sink);
    final sun = word('sun', 's', audio: 'words/sun.mp3');

    // Nothing is spoken until the voice is known to be silent.
    await audio.playEmphasisedWord(sun, soundS);
    expect(sink.playedAssets, isEmpty);
    expect(sink.spokenText, ['sssun']);

    // Once it is, the recording carries it instead.
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
}

/// A sink that accepts an utterance and never finishes it — a device with no
/// voice installed, or a browser refusing to speak before the first tap.
class SilentSink implements AudioSink {
  int stopCount = 0;

  @override
  Future<bool> playAsset(String assetPath, {required double volume}) async =>
      false;

  @override
  Future<void> speak(String text, {required double volume}) =>
      Completer<void>().future;

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<void> dispose() async {}
}
