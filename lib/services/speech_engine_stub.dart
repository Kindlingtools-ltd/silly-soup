import 'speech_engine.dart';

/// Reached only on a platform with neither `dart:io` nor `dart:js_interop`,
/// which in practice means nothing we ship. Silence beats a crash.
class SilentSpeechEngine implements SpeechEngine {
  @override
  Future<void> prepare() async {}

  @override
  Future<void> speak(String text, {required double volume}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> unlock() async {}

  @override
  Future<void> dispose() async {}
}

SpeechEngine createSpeechEngine() => SilentSpeechEngine();
