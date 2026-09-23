import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'speech_engine.dart';

/// The chef's voice in a browser, driven straight off the Web Speech API.
///
/// This does not go through `flutter_tts` on the web, for two reasons found
/// while chasing "the audio is broken on mobile":
///
///  * the plugin reuses one utterance object and treats a speech *error* by
///    dropping the future it handed the caller instead of completing it, so
///    a device that cannot speak leaves the chef frozen mid-sentence;
///  * it has no way to spend a tap on unlocking speech, which every mobile
///    browser requires before it will make a sound.
class WebSpeechEngine implements SpeechEngine {
  WebSpeechEngine();

  /// British, to match the phonics scheme this is built for. A voice that
  /// says "ay" for /a/ teaches the wrong thing.
  static const String language = 'en-GB';

  web.SpeechSynthesis? get _synth => web.window.speechSynthesis;

  web.SpeechSynthesisVoice? _voice;
  bool _prepared = false;
  bool _unlocked = false;

  /// The utterance currently being waited on, so a later [stop] can settle
  /// it rather than leaving a caller hanging.
  Completer<void>? _pending;

  @override
  Future<void> prepare() async {
    if (_prepared) return;
    _prepared = true;
    _pickVoice();
    // The voice list arrives asynchronously in most browsers, so take
    // another look when it does.
    _synth?.addEventListener('voiceschanged', _onVoicesChanged.toJS);
  }

  void _onVoicesChanged(web.Event _) => _pickVoice();

  void _pickVoice() {
    final synth = _synth;
    if (synth == null) return;
    final voices = synth.getVoices().toDart;
    if (voices.isEmpty) return;
    // Prefer a British voice, then any English one, then whatever there is.
    _voice =
        _firstWhere(voices, (v) => v.lang.replaceAll('_', '-') == language) ??
        _firstWhere(voices, (v) => v.lang.toLowerCase().startsWith('en')) ??
        voices.first;
  }

  static web.SpeechSynthesisVoice? _firstWhere(
    List<web.SpeechSynthesisVoice> voices,
    bool Function(web.SpeechSynthesisVoice) test,
  ) {
    for (final voice in voices) {
      if (test(voice)) return voice;
    }
    return null;
  }

  @override
  Future<void> unlock() async {
    if (_unlocked) return;
    final synth = _synth;
    if (synth == null) return;
    _unlocked = true;
    await prepare();
    try {
      // A silent utterance spent inside the child's first tap. Mobile
      // browsers only grant speech from a gesture, and the grant sticks.
      final warmUp = web.SpeechSynthesisUtterance(' ')
        ..volume = 0
        ..lang = language;
      synth.speak(warmUp);
      // Chrome can leave the queue paused after a background tab or a
      // cancel; resuming here costs nothing when it is not.
      synth.resume();
    } catch (error) {
      debugPrint('Silly Soup: could not warm the voice up ($error)');
    }
  }

  @override
  Future<void> speak(String text, {required double volume}) async {
    if (text.trim().isEmpty) return;
    final synth = _synth;
    if (synth == null) return;
    await prepare();

    // A queued utterance from an interrupted line would otherwise be spoken
    // over the top of this one.
    synth.cancel();
    _settle();

    final done = Completer<void>();
    _pending = done;

    final utterance = web.SpeechSynthesisUtterance(text)
      ..lang = language
      ..volume = volume.clamp(0.0, 1.0)
      // Slower than the default: these are three- to five-year-olds, and
      // the whole point is that they can hear the sound clearly.
      ..rate = 0.8
      ..pitch = 1.1;
    final voice = _voice;
    if (voice != null) utterance.voice = voice;

    void finish(web.Event event) {
      if (event.type == 'error') {
        debugPrint('Silly Soup: the browser would not say "$text"');
      }
      if (identical(_pending, done)) _pending = null;
      if (!done.isCompleted) done.complete();
    }

    utterance.addEventListener('end', finish.toJS);
    // Both of these have to settle the future. The whole bug this replaces
    // was an error path that quietly dropped it.
    utterance.addEventListener('error', finish.toJS);

    try {
      synth.speak(utterance);
      synth.resume();
    } catch (error) {
      debugPrint('Silly Soup: could not speak "$text" ($error)');
      finish(web.Event('error'));
    }

    return done.future;
  }

  @override
  Future<void> stop() async {
    try {
      _synth?.cancel();
    } catch (_) {
      // Cancelling when nothing is speaking is not worth reporting.
    }
    // `cancel()` does not reliably fire `end` on every browser, so whoever
    // is waiting is released here rather than left to time out.
    _settle();
  }

  void _settle() {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  @override
  Future<void> dispose() => stop();
}

SpeechEngine createSpeechEngine() => WebSpeechEngine();
