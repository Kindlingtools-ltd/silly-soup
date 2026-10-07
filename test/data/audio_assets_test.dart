import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/models/models.dart';
import 'package:silly_soup/services/services.dart';

/// Guards the recordings that ship.
///
/// Audio is the most important part of this app, so a missing or truncated
/// clip should fail the build rather than quietly fall back to the device
/// voice in a classroom. The clips are made by `tool/generate_audio.py`,
/// which measures every take before keeping it; what is checked here is that
/// what it produced is still all present, still playable, and still matches
/// the content it was made from.
void main() {
  final bank = SoundBank.fromJson(
    json.decode(File('assets/data/sound_bank.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final script = ChefScript.fromJson(
    json.decode(File('assets/data/chef_script.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final manifest = json.decode(
    File(ClipCatalogue.manifestAssetPath).readAsStringSync(),
  ) as Map<String, dynamic>;
  final catalogue = ClipCatalogue.fromJson(manifest);

  /// Smaller than this is not a word — it is a glitch.
  const minimumClipBytes = 2000;

  /// An MP3 frame header: sync bits, MPEG version, layer, bit rate, sample
  /// rate. Checking the first two bytes is not enough on the web, where a
  /// missing asset comes back as the host's index.html with a 200.
  ({int sampleRate, int channels})? mp3Header(File file) {
    final bytes = file.readAsBytesSync();
    var offset = 0;
    if (bytes.length > 10 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      var size = 0;
      for (final byte in bytes.sublist(6, 10)) {
        size = (size << 7) | (byte & 0x7F);
      }
      offset = 10 + size;
    }
    if (offset + 4 > bytes.length) return null;
    final header =
        (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    if (header >> 21 != 0x7FF) return null;
    if (4 - ((header >> 17) & 0x3) != 3) return null; // Layer III
    const rates = {
      0x3: [44100, 48000, 32000], // MPEG 1
      0x2: [22050, 24000, 16000], // MPEG 2
      0x0: [11025, 12000, 8000], // MPEG 2.5
    };
    final version = rates[(header >> 19) & 0x3];
    final rateIndex = (header >> 10) & 0x3;
    if (version == null || rateIndex > 2) return null;
    return (
      sampleRate: version[rateIndex],
      channels: ((header >> 6) & 0x3) == 0x3 ? 1 : 2,
    );
  }

  void expectPlayableClip(String path, {String? because}) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: because ?? path);
    expect(file.lengthSync(), greaterThan(minimumClipBytes), reason: path);
    final header = mp3Header(file);
    expect(header, isNotNull, reason: '$path is not a playable mp3');
    // Everything ships as mono at one rate, so a stray file from somewhere
    // else stands out.
    expect(header!.channels, 1, reason: path);
    expect(header.sampleRate, 24000, reason: path);
  }

  group('the sounds themselves', () {
    test('every sound in the bank has a recording of its pure sound', () {
      for (final sound in bank.sounds) {
        expect(sound.audioAssetPath, isNotNull, reason: sound.id);
        expectPlayableClip(
          sound.audioAssetPath!,
          because:
              'the pure sound is what this app teaches; /${sound.id}/ has no '
              'recording, so a child would hear the device voice say its '
              'letter name instead',
        );
      }
    });

    test('every sound has a British transcription to be recorded from', () {
      // The voice API has no British English to ask for: it takes `en` and
      // not `en-GB`. Without this, a clip is however the model reads the
      // letters — which is where the American vowels came from.
      for (final sound in bank.sounds) {
        expect(sound.pronunciation, startsWith('/'), reason: sound.id);
        expect(sound.pronunciation, endsWith('/'), reason: sound.id);
      }
    });

    test('every sound says how it is made and what it is cut out of', () {
      // The engine cannot say a phoneme: asked for `sss` it reads the letter
      // name, and asked for `b b b` it says "Buh buh buh". So each pure sound
      // is cut out of an ordinary word, and how to cut it depends on how the
      // sound is made. Without both of these a sound cannot be recorded at
      // all — including a custom one an adult adds.
      const manners = {'fricative', 'nasal', 'vowel', 'stop'};
      final words = bank.words.map((word) => word.word).toSet();

      for (final sound in bank.sounds) {
        expect(manners, contains(sound.manner), reason: sound.id);
        expect(words, contains(sound.carrierWord), reason: sound.id);
        final carrier = bank.words.firstWhere(
          (word) => word.word == sound.carrierWord,
        );
        expect(
          carrier.phoneme,
          sound.id,
          reason: '${sound.carrierWord} does not start with /${sound.id}/',
        );
      }
    });

    test('a stop is never held on, because holding one makes "buh"', () {
      for (final sound in bank.sounds) {
        if (sound.manner == 'stop') {
          expect(sound.isContinuant, isFalse, reason: sound.id);
        }
        if (sound.isContinuant) {
          expect(sound.manner, isNot('stop'), reason: sound.id);
        }
      }
    });

    test('every sound has a recording of its action', () {
      for (final sound in bank.sounds.where((s) => s.action.isNotEmpty)) {
        expectPlayableClip(ChefVoice.actionClip(sound));
      }
    });
  });

  group('the words', () {
    test('every word has a plain recording and an emphasised one', () {
      for (final word in bank.words) {
        expectPlayableClip(word.audioAssetPath!, because: word.word);
        expectPlayableClip(
          ChefVoice.emphasisClip(word),
          because:
              '"${word.word}" has no recording of its first sound being '
              'stretched or bounced, so the chef would have to spell '
              '"sssun" out to the device voice',
        );
      }
    });

    test('every word has a British transcription of its own', () {
      for (final word in bank.words) {
        expect(word.pronunciation, startsWith('/'), reason: word.word);
        expect(word.pronunciation, endsWith('/'), reason: word.word);
      }
    });

    test('a word transcription starts with the sound it is filed under', () {
      // This is what lets the chef stretch or bounce the first sound: the
      // emphasised recording is built by lengthening the opening symbol.
      const stressMarks = ['ˈ', 'ˌ'];
      for (final word in bank.words) {
        final sound = bank.soundById(word.phoneme)!;
        var ipa = word.pronunciation.replaceAll('/', '');
        while (ipa.isNotEmpty && stressMarks.contains(ipa[0])) {
          ipa = ipa.substring(1);
        }
        expect(
          ipa,
          startsWith(sound.pronunciation.replaceAll('/', '')),
          reason: '${word.word} is filed under /${sound.id}/',
        );
      }
    });
  });

  group('the chef\'s fixed lines', () {
    test('every phrase in the script is recorded', () {
      expect(script.phrases, isNotEmpty);
      for (final key in script.phrases.keys) {
        expectPlayableClip(ChefVoice.phraseClip(key));
      }
    });

    test('every praise line is recorded', () {
      expect(script.praise, isNotEmpty);
      for (var i = 0; i < script.praise.length; i++) {
        expectPlayableClip(ChefVoice.praiseClip(i));
      }
    });

    test('the app only ever asks for a phrase the script has', () {
      for (final key in [
        ChefScript.mySoundToday,
        ChefScript.watchMeMake,
        ChefScript.nowYouMake,
        ChefScript.inGoes,
        ChefScript.and,
        ChefScript.yourSoupHas,
        ChefScript.inIt,
        ChefScript.emptyPan,
      ]) {
        expect(script.phrase(key), isNotEmpty, reason: key);
      }
    });
  });

  test('the soup song is recorded', () {
    expectPlayableClip(SoupSong.audioAssetPath);
  });

  group('the manifest', () {
    test('lists every clip that is on disk, and nothing that is not', () {
      for (final path in catalogue.paths) {
        expect(File(path).existsSync(), isTrue, reason: '$path is listed');
      }
      final onDisk = Directory('assets/audio')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.mp3'))
          .map((file) => file.path)
          .toSet();
      expect(catalogue.paths, onDisk);
    });

    test('lets the chef say every line of every soup from recordings', () {
      // The end of the chain: with the real bank, the real script and the
      // real manifest, nothing a child can do should fall through to the
      // device voice. One missing emphasis clip is enough to send a whole
      // recital there, and this is what notices.
      final voice = ChefVoice(script: script, catalogue: catalogue);

      for (final sound in bank.sounds) {
        final pot = bank.wordsFor(sound.id);
        expect(pot, isNotEmpty, reason: sound.id);

        void expectRecorded(Utterance said, String what) {
          expect(
            said.clips,
            isNotEmpty,
            reason: '/${sound.id}/: $what would be read by the device voice',
          );
          expect(said.text, isNotEmpty, reason: '/${sound.id}/: $what');
        }

        expectRecorded(voice.pureSound(sound), 'the pure sound');
        expectRecorded(voice.action(sound), 'the action');
        expectRecorded(voice.phrase(ChefScript.watchMeMake), 'the opening');
        expectRecorded(
          voice.reciteList(pot, sound),
          'the whole pantry recited',
        );
        expectRecorded(
          voice.reciteFinishedSoup(pot, sound),
          'the finished soup',
        );
        expectRecorded(
          voice.reciteFinishedSoup(const [], sound),
          'an empty pan',
        );
        for (final word in pot) {
          expectRecorded(
            voice.commentateOnItem(word, sound),
            'in goes ${word.word}',
          );
          expectRecorded(voice.word(word), 'the plain word ${word.word}');
        }
      }

      for (var i = 0; i < script.praise.length; i++) {
        expect(voice.praise(i).clips, hasLength(1));
      }
      expect(voice.song().clips, [SoupSong.audioAssetPath]);
    });

    test('records the voice the clips were made with', () {
      expect(manifest['voice'], isNotEmpty);
      // `en` and not `en-GB`: see the note on PhonemeSound.pronunciation.
      expect(manifest['language'], 'en');
    });
  });
}
