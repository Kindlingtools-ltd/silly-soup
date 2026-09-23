import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'audio_sink.dart';
import 'recital_service.dart';

/// Everything the child hears.
///
/// Recorded clips come first, always. Speech is only ever a fallback for a
/// clip that has not been recorded yet, and every fallback is logged so the
/// adult area and `dart run tool/audio_checklist.dart` can both show exactly
/// what is still missing.
class AudioService {
  AudioService({AudioSink? sink}) : _sink = sink ?? PlatformAudioSink();

  final AudioSink _sink;

  /// 0.0 to 1.0, set from the adult's volume control.
  double volume = 1.0;

  final Set<String> _missingClips = <String>{};

  /// Clip paths the app asked for and did not find, in the order first seen.
  List<String> get missingClips => List.unmodifiable(_missingClips);

  /// The chef saying a sound on its own: "sss", "b-b-b".
  Future<void> playSound(PhonemeSound sound) =>
      _playClipOrSpeak(sound.audioAssetPath, RecitalService.pureSound(sound));

  /// A single word, said plainly.
  Future<void> playWord(SoupWord word) =>
      _playClipOrSpeak(word.audioAssetPath, word.word);

  /// A word with its first sound emphasised, for the chef's commentary.
  ///
  /// There is no clip for the emphasised form — the emphasis is the chef's
  /// job — so this always goes through the voice unless a setting has
  /// recorded one for this exact word.
  Future<void> playEmphasisedWord(SoupWord word, PhonemeSound sound) =>
      speak(RecitalService.emphasise(word, sound));

  /// The stirring song: the adult's own recording if they made one, then the
  /// bundled recording, then the words spoken.
  Future<void> playSong({String? customRecordingPath}) async {
    if (customRecordingPath != null && customRecordingPath.isNotEmpty) {
      if (await _sink.playAsset(customRecordingPath, volume: volume)) return;
    }
    await _playClipOrSpeak(SoupSong.audioAssetPath, SoupSong.spokenLyrics);
  }

  /// Say something in the chef's voice. Commentary and praise are generated
  /// from the child's own choices, so they are always spoken.
  Future<void> speak(String text) => _sink.speak(text, volume: volume);

  /// Stop whatever is playing. Every clip is interruptible — a child who
  /// wants to carry on should never have to wait for the chef.
  Future<void> stop() => _sink.stop();

  Future<void> dispose() => _sink.dispose();

  Future<void> _playClipOrSpeak(String? assetPath, String fallbackText) async {
    if (assetPath != null && assetPath.isNotEmpty) {
      if (await _sink.playAsset(assetPath, volume: volume)) return;
      if (_missingClips.add(assetPath)) {
        debugPrint('Silly Soup: no recording for $assetPath, speaking instead');
      }
    }
    await _sink.speak(fallbackText, volume: volume);
  }
}
