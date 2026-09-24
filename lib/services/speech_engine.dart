import 'speech_engine_stub.dart'
    if (dart.library.js_interop) 'speech_engine_web.dart'
    if (dart.library.io) 'speech_engine_native.dart'
    as impl;

/// The chef's voice, when there is no recording to play.
///
/// Split by platform because the two have genuinely different failure modes:
/// a phone has a voice installed and simply speaks, while a browser will not
/// speak at all until the child has touched the screen, and reports failure
/// through an event that has to be listened for.
abstract class SpeechEngine {
  /// Set the voice up. Safe to call more than once.
  Future<void> prepare();

  /// Say [text], completing when the words have finished — or when the
  /// device has said it cannot say them.
  ///
  /// It must always complete. A future that never resolves is what left the
  /// chef frozen mid-sentence on a device with no voice.
  Future<void> speak(String text, {required double volume});

  Future<void> stop();

  /// Called from inside a real tap, before anything needs to be heard.
  ///
  /// Mobile browsers refuse to speak until the page has been touched, and a
  /// refusal is silent. Spending the child's first tap on a silent warm-up
  /// is what makes every later line audible.
  Future<void> unlock();

  Future<void> dispose();
}

SpeechEngine createSpeechEngine() => impl.createSpeechEngine();
