import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

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

  Future<void> dispose();
}

/// The real sink: recorded clips through audioplayers, speech through
/// flutter_tts. Both are local to the device; neither calls out to a service.
class PlatformAudioSink implements AudioSink {
  PlatformAudioSink({AudioPlayer? player, FlutterTts? tts})
    : _player = player ?? AudioPlayer(),
      _tts = tts ?? FlutterTts();

  final AudioPlayer _player;
  final FlutterTts _tts;
  bool _ttsReady = false;

  /// Clips already known to be absent, so a missing file costs one bundle
  /// lookup rather than one per tap.
  final Set<String> _knownMissing = {};

  @override
  Future<bool> playAsset(String assetPath, {required double volume}) async {
    if (_knownMissing.contains(assetPath)) return false;
    try {
      await rootBundle.load(assetPath);
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
      return true;
    } catch (error) {
      debugPrint('Silly Soup: could not play $assetPath ($error)');
      return false;
    }
  }

  @override
  Future<void> speak(String text, {required double volume}) async {
    if (text.trim().isEmpty) return;
    try {
      if (!_ttsReady) {
        await _tts.setLanguage('en-GB');
        // Slower than the default: these are three- to five-year-olds, and
        // the whole point is that they can hear the sound clearly.
        await _tts.setSpeechRate(0.4);
        await _tts.setPitch(1.1);
        _ttsReady = true;
      }
      await _tts.setVolume(volume);
      await _tts.stop();
      await _tts.speak(text);
    } catch (error) {
      debugPrint('Silly Soup: could not speak "$text" ($error)');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
      await _tts.stop();
    } catch (_) {
      // Stopping something that is not playing is not worth reporting.
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
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
  Future<void> dispose() async {}
}
