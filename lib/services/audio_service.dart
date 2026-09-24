import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio_sink.dart';
import 'chef_voice.dart';

/// Everything the child hears.
///
/// Recorded clips come first, always. Speech is only ever a fallback for a
/// clip that has not been recorded yet, and every fallback is logged so the
/// adult area and `dart run tool/audio_checklist.dart` can both show exactly
/// what is still missing.
///
/// What to say is decided by [ChefVoice], which hands over an [Utterance] —
/// the clips and the same line in words. This class only plays it.
class AudioService {
  AudioService({AudioSink? sink}) : _sink = sink ?? PlatformAudioSink();

  final AudioSink _sink;

  /// 0.0 to 1.0, set from the adult's volume control.
  double volume = 1.0;

  /// Utterances run one at a time. Some of the chef's lines are started
  /// without being awaited — the "now you make a silly soup" hand-over, the
  /// sound it says when a soup opens — and without a queue those land on top
  /// of whatever is already playing, so the child hears two voices at once.
  Future<void> _queue = Future<void>.value();

  /// Bumped by [interrupt]. Anything still waiting its turn from an earlier
  /// epoch is dropped rather than played late.
  int _epoch = 0;

  /// How long to wait for an utterance before giving up on it.
  ///
  /// Waiting for speech to finish is what stops the chef talking over itself,
  /// but it cannot be an unbounded wait: a device with no voice installed —
  /// or a browser that refuses to speak before the first tap — never fires a
  /// completion callback at all, and the whole game would sit there frozen
  /// on "Watch me make my silly soup!". Generous enough never to clip real
  /// speech, short enough that a silent device still plays.
  static Duration budgetFor(String text) {
    final millis = 2500 + text.length * 160;
    return Duration(milliseconds: millis.clamp(2500, 25000));
  }

  Future<void> _enqueue(Future<void> Function() utterance) {
    final epoch = _epoch;
    final next = _queue.then((_) async {
      if (epoch != _epoch) return;
      await utterance();
    });
    _queue = next.catchError((Object _) {});
    return next;
  }

  /// Spend the child's first tap on making sound possible.
  ///
  /// A mobile browser will not speak or play a clip until the page has been
  /// touched, and it refuses silently: the app looked as though it had no
  /// voice at all, gave up waiting for one, and ran the whole game in
  /// silence. This is called from the first pointer down, inside the gesture,
  /// which is the only moment the permission is granted.
  Future<void> unlock() async {
    if (_unlocked) return;
    _unlocked = true;
    await _sink.unlock();
    // Anything that timed out before the voice was allowed to speak should
    // not count against it.
    _unfinished = 0;
  }

  bool _unlocked = false;

  /// Whether [unlock] has run. The adult area reports it, because "no sound
  /// on this device" and "nobody has touched the screen yet" look identical
  /// and have very different answers.
  bool get isUnlocked => _unlocked;

  /// Stop what is playing and abandon anything queued behind it.
  ///
  /// This is what a child's tap does: they should not have to wait for the
  /// chef to finish a sentence before their choice is heard.
  Future<void> interrupt() async {
    _epoch++;
    _queue = Future<void>.value();
    await _sink.stop();
  }

  final Set<String> _missingClips = <String>{};

  /// Clip paths the app asked for and did not find, in the order first seen.
  List<String> get missingClips => List.unmodifiable(_missingClips);

  /// Say an [Utterance]: its recordings if they are all there, its words if
  /// they are not.
  ///
  /// The whole line is one entry in the queue, so a child's tap cuts it off
  /// wherever it has got to rather than letting the rest of the sentence
  /// arrive after their choice.
  Future<void> play(Utterance utterance) {
    if (utterance.isEmpty) return Future<void>.value();
    final epoch = _epoch;
    return _enqueue(() async {
      if (utterance.clips.isNotEmpty) {
        final played = await _playClips(utterance, epoch);
        if (played) return;
      }
      if (epoch != _epoch) return;
      await _bounded(
        () => _sink.speak(utterance.text, volume: volume),
        utterance.text,
      );
    });
  }

  /// Play a line's clips back to back. False when one of them turns out not
  /// to be there, which is the caller's cue to speak the line instead.
  Future<bool> _playClips(Utterance utterance, int epoch) async {
    for (final clip in utterance.clips) {
      if (epoch != _epoch) return true;
      var played = false;
      // Deliberately not [_bounded]: that shortens its wait once the device
      // has proved it has no voice, and a clip is a file — it plays whether
      // the device can speak or not. Borrowing that budget cut recordings
      // off a quarter of a second in.
      await _playOneClip(clip, () async {
        played = await _sink.playAsset(clip, volume: volume);
      });
      if (!played) {
        if (_missingClips.add(clip)) {
          debugPrint('Silly Soup: no recording for $clip, speaking instead');
        }
        return false;
      }
    }
    return true;
  }

  /// The longest a single recording is allowed to take. Every clip this app
  /// ships is under nine seconds; the song is the longest at eight.
  static const Duration _clipBudget = Duration(seconds: 20);

  Future<void> _playOneClip(String clip, Future<void> Function() action) async {
    try {
      await action().timeout(_clipBudget);
    } on TimeoutException {
      debugPrint('Silly Soup: $clip never reported finishing');
      await _sink.stop();
    }
  }

  /// The stirring song, with the adult's own recording in front of the
  /// bundled one if they made one in the adult area.
  Future<void> playSong(Utterance song, {String? customRecordingPath}) {
    if (customRecordingPath == null || customRecordingPath.isEmpty) {
      return play(song);
    }
    return play(Utterance([customRecordingPath, ...song.clips], song.text));
  }

  /// Say something in the chef's own words rather than from a recording.
  /// Nothing in the game needs this now that every line is recorded; it is
  /// the fallback path, and the adult area uses it to try the device voice.
  Future<void> speak(String text) =>
      _enqueue(() => _bounded(() => _sink.speak(text, volume: volume), text));

  /// Consecutive utterances that never reported finishing.
  int _unfinished = 0;

  /// After this many in a row, stop giving the voice the benefit of the
  /// doubt. Two is enough to tell a dead voice from one slow line.
  static const int _silenceThreshold = 2;

  /// True when the device has stopped reporting that speech finished — no
  /// voice installed, or a browser that will not speak. Waiting a full
  /// budget per line then makes the game crawl, which reads as broken.
  bool get voiceIsSilent => _unfinished >= _silenceThreshold;

  /// Run an utterance, but never wait on it forever.
  Future<void> _bounded(Future<void> Function() action, String text) async {
    // A silent device still gets a beat between lines, just not a long one.
    final budget = voiceIsSilent
        ? const Duration(milliseconds: 250)
        : budgetFor(text);
    try {
      await action().timeout(budget);
      _unfinished = 0;
    } on TimeoutException {
      _unfinished++;
      if (_unfinished == _silenceThreshold) {
        debugPrint(
          'Silly Soup: this device is not reporting that speech finished. '
          'Carrying on without waiting for it.',
        );
      }
      // Whatever it was is still notionally playing; stop it so the next
      // line does not land on top of it.
      await _sink.stop();
    }
  }

  /// Stop whatever is playing. Every clip is interruptible — a child who
  /// wants to carry on should never have to wait for the chef.
  Future<void> stop() => interrupt();

  Future<void> dispose() => _sink.dispose();
}
