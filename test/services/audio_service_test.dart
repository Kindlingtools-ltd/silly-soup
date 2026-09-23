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

  test('stop reaches the sink so a child never has to wait', () async {
    final sink = RecordingAudioSink();

    await AudioService(sink: sink).stop();

    expect(sink.stopCount, 1);
  });
}
