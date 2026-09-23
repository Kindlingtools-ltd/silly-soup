import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'speech_engine.dart';

/// The platform voice on iOS, Android, macOS, Windows and Linux.
class NativeSpeechEngine implements SpeechEngine {
  NativeSpeechEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _ready = false;

  @override
  Future<void> prepare() async {
    if (_ready) return;
    try {
      // Without this, speak() returns the moment speech *starts*. Every
      // caller then moves on, and the next line's stop() cuts this one off
      // mid-word — which is what made the chef unlistenable.
      await _tts.awaitSpeakCompletion(true);
      await _tts.setLanguage('en-GB');
      // Slower than the default: these are three- to five-year-olds, and
      // the whole point is that they can hear the sound clearly.
      await _tts.setSpeechRate(0.4);
      await _tts.setPitch(1.1);
      _ready = true;
    } catch (error) {
      debugPrint('Silly Soup: could not set the voice up ($error)');
    }
  }

  @override
  Future<void> speak(String text, {required double volume}) async {
    if (text.trim().isEmpty) return;
    await prepare();
    try {
      await _tts.setVolume(volume);
      // Deliberately no stop() first: utterances are already played one at a
      // time, and stopping immediately before speaking leaves the plugin
      // believing it is still mid-sentence and dropping the next line.
      await _tts.speak(text);
    } catch (error) {
      debugPrint('Silly Soup: could not speak "$text" ($error)');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // Stopping something that is not playing is not worth reporting.
    }
  }

  /// Native platforms have no gesture requirement, so there is nothing to
  /// unlock — but warming the voice up here keeps the first line prompt.
  @override
  Future<void> unlock() => prepare();

  @override
  Future<void> dispose() => stop();
}

SpeechEngine createSpeechEngine() => NativeSpeechEngine();
