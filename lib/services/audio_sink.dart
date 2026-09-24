import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'speech_engine.dart';

/// Anything that can make a noise.
///
/// Pulled out behind an interface so the game logic and the missing-clip
/// bookkeeping can be tested without a plugin or a speaker.
abstract class AudioSink {
  /// Play a bundled clip. Returns false when the clip is not in the bundle,
  /// which is the caller's cue to fall back to speech.
  Future<bool> playAsset(String assetPath, {required double volume});

  /// Speak text with the platform voice (the Web Speech API on web).
  Future<void> speak(String text, {required double volume});

  Future<void> stop();

  /// Called from inside a real tap. Mobile browsers will not play a sound
  /// until the page has been touched, and they refuse silently, so the first
  /// tap is spent making everything after it audible.
  Future<void> unlock();

  Future<void> dispose();
}

/// The real sink: recorded clips through audioplayers, speech through the
/// platform's voice. Both are local to the device; neither calls out to a
/// service.
class PlatformAudioSink implements AudioSink {
  PlatformAudioSink({AudioPlayer? player, SpeechEngine? speech})
    : _player = player ?? AudioPlayer(),
      _speech = speech ?? createSpeechEngine();

  /// A tenth of a second of silence, used to spend a tap on satisfying a
  /// mobile browser's "no sound before the first touch" rule.
  static const String _silentClip =
      'data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEAgD4AAAB9AAAC'
      'ABAAZGF0YQAAAAA=';

  final AudioPlayer _player;
  final SpeechEngine _speech;
  bool _unlocked = false;

  /// Clips already known to be absent, so a missing file costs one bundle
  /// lookup rather than one per tap.
  final Set<String> _knownMissing = {};

  @override
  Future<bool> playAsset(String assetPath, {required double volume}) async {
    if (_knownMissing.contains(assetPath)) return false;
    try {
      final data = await rootBundle.load(assetPath);
      // "Does this asset exist?" cannot be answered by the load succeeding.
      // On the web a missing asset is an HTTP request, and a single-page-app
      // host answers those with 200 and index.html — so every missing clip
      // looked present, the player was handed HTML, and the child heard
      // nothing at all instead of the spoken fallback.
      if (!_looksLikeAudio(data)) {
        _knownMissing.add(assetPath);
        return false;
      }
    } catch (_) {
      _knownMissing.add(assetPath);
      return false;
    }

    try {
      await _player.stop();
      await _player.setVolume(volume);
      // audioplayers resolves AssetSource relative to the asset root, so the
      // leading "assets/" has to come off.
      final source = assetPath.startsWith('assets/')
          ? assetPath.substring('assets/'.length)
          : assetPath;
      await _player.play(AssetSource(source), volume: volume);
      // play() returns when playback *starts*. The chef has to wait until the
      // clip has actually finished, or the next line talks over this one.
      await _player.onPlayerComplete.first.timeout(
        const Duration(seconds: 20),
        onTimeout: () {},
      );
      return true;
    } catch (error) {
      debugPrint('Silly Soup: could not play $assetPath ($error)');
      return false;
    }
  }

  @override
  Future<void> speak(String text, {required double volume}) =>
      _speech.speak(text, volume: volume);

  @override
  Future<void> unlock() async {
    if (_unlocked) return;
    _unlocked = true;
    await _speech.unlock();
    try {
      // The clip player needs the same permission, and asking for it with a
      // real (silent) clip is the only thing browsers accept.
      await _player.setVolume(0);
      await _player.play(UrlSource(_silentClip), volume: 0);
      await _player.stop();
    } catch (error) {
      debugPrint('Silly Soup: could not warm the player up ($error)');
    }
  }

  /// True when the bytes start like a sound file rather than, say, a web
  /// page. Covers the container formats a clip could plausibly arrive in.
  static bool _looksLikeAudio(ByteData data) {
    if (data.lengthInBytes < 4) return false;
    final bytes = data.buffer.asUint8List(data.offsetInBytes, 4);
    // "ID3" tag, or an MPEG frame sync.
    if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) return true;
    if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) return true;
    // RIFF (wav), OggS (ogg/opus), fLaC.
    const signatures = [
      [0x52, 0x49, 0x46, 0x46],
      [0x4F, 0x67, 0x67, 0x53],
      [0x66, 0x4C, 0x61, 0x43],
    ];
    for (final signature in signatures) {
      var match = true;
      for (var i = 0; i < 4; i++) {
        if (bytes[i] != signature[i]) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
    return false;
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {
      // Stopping something that is not playing is not worth reporting.
    }
    await _speech.stop();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _speech.dispose();
    await _player.dispose();
  }
}

/// A sink that records what it was asked to do and makes no noise.
@visibleForTesting
class RecordingAudioSink implements AudioSink {
  RecordingAudioSink({Set<String> availableAssets = const {}})
    : _available = availableAssets;

  final Set<String> _available;
  final List<String> playedAssets = [];
  final List<String> spokenText = [];
  int stopCount = 0;
  int unlockCount = 0;

  @override
  Future<bool> playAsset(String assetPath, {required double volume}) async {
    if (!_available.contains(assetPath)) return false;
    playedAssets.add(assetPath);
    return true;
  }

  @override
  Future<void> speak(String text, {required double volume}) async {
    spokenText.add(text);
  }

  @override
  Future<void> stop() async => stopCount++;

  @override
  Future<void> unlock() async => unlockCount++;

  @override
  Future<void> dispose() async {}
}
