import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'audio_sink.dart';
import 'clip_library.dart';
import 'recital_service.dart';

/// Everything the child hears.
///
/// Recorded clips come first, always. Speech is only ever a fallback for a
/// clip that has not been recorded yet, and every fallback is logged so the
/// adult area and `uv run tool/build_audio.py --audit` can both show exactly
/// what is still missing.
///
/// Almost everything the chef says arrives as a [ChefLine] — words plus the
/// recordings that say them. That matters because the device's own voice is
/// whatever the browser happens to ship, and it used to be what a child heard
/// for the commentary, the recitals and the praise: all of it, all the time.
class AudioService {
  AudioService({AudioSink? sink, ClipLibrary? clips})
    : _sink = sink ?? PlatformAudioSink(),
      _clips = clips ?? const ClipLibrary.empty();

  final AudioSink _sink;

  /// Which recordings were built. Consulted before a line made of several
  /// clips is started, because a line cannot be abandoned half-way through
  /// without the child hearing the first half twice.
  final ClipLibrary _clips;

  /// How many recordings this build has. The adult area reports it.
  int get recordedClipCount => _clips.length;

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

  /// The chef saying a sound on its own: "sss", "b-b-b".
  Future<void> playSound(PhonemeSound sound) =>
      _playClipOrSpeak(sound.audioAssetPath, RecitalService.pureSound(sound));

  /// A single word, said plainly.
  Future<void> playWord(SoupWord word) =>
      _playClipOrSpeak(word.audioAssetPath, word.word);

  /// The stirring song: the adult's own recording if they made one, then the
  /// bundled recording, then the words spoken.
  Future<void> playSong({String? customRecordingPath}) async {
    if (customRecordingPath != null && customRecordingPath.isNotEmpty) {
      var played = false;
      await _enqueue(() async {
        await _bounded(() async {
          played = await _sink.playAsset(customRecordingPath, volume: volume);
        }, SoupSong.spokenLyrics);
      });
      if (played) return;
    }
    await _playClipOrSpeak(SoupSong.audioAssetPath, SoupSong.spokenLyrics);
  }

  /// Say something in the chef's voice. Commentary and praise are generated
  /// from the child's own choices, so they are always spoken.
  Future<void> speak(String text) =>
      _enqueue(() => _bounded(() => _sink.speak(text, volume: volume), text));

  /// Say one of the chef's lines, played rather than spoken wherever the
  /// recordings exist.
  ///
  /// The whole line is checked before any of it starts. A recital is several
  /// clips in a row, and discovering the fourth one is missing after playing
  /// three would leave the chef stopping mid-sentence; falling back to the
  /// voice at that point would repeat what the child just heard. So it is all
  /// the recordings or none of them.
  Future<void> say(ChefLine line) {
    if (line.text.isEmpty && line.clips.isEmpty) return Future<void>.value();
    if (line.clips.isEmpty || !_clips.hasAll(line.clips)) {
      for (final clip in line.clips) {
        if (!_clips.has(clip) && _missingClips.add(clip)) {
          debugPrint('Silly Soup: no recording for $clip, speaking instead');
        }
      }
      return speak(line.text);
    }

    final epoch = _epoch;
    return _enqueue(() async {
      for (final clip in line.clips) {
        // A child's tap ends the sentence. They should not have to wait out
        // a five-ingredient recital before their next choice is heard.
        if (epoch != _epoch) return;
        var played = false;
        await _bounded(() async {
          played = await _sink.playAsset(clip, volume: volume);
        }, line.text);
        if (played) continue;
        // The manifest said this was here. Stop rather than speak the line
        // again over the part already played.
        if (_missingClips.add(clip)) {
          debugPrint('Silly Soup: $clip is in the manifest but would not play');
        }
        return;
      }
    });
  }

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

  Future<void> _playClipOrSpeak(String? assetPath, String fallbackText) {
    return _enqueue(() async {
      if (assetPath != null && assetPath.isNotEmpty) {
        var played = false;
        await _bounded(() async {
          played = await _sink.playAsset(assetPath, volume: volume);
        }, fallbackText);
        if (played) return;
        if (_missingClips.add(assetPath)) {
          debugPrint(
            'Silly Soup: no recording for $assetPath, speaking instead',
          );
        }
      }
      await _bounded(
        () => _sink.speak(fallbackText, volume: volume),
        fallbackText,
      );
    });
  }
}
