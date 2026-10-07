import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/models/models.dart';
import 'package:silly_soup/providers/providers.dart';
import 'package:silly_soup/services/services.dart';

/// Plays a whole soup against the recordings that actually ship.
///
/// The unit tests use a hand-built bank and a made-up clip library, which
/// proves the wiring but not that the wiring reaches anything. This drives
/// the real sound bank through the real `assets/audio/manifest.json`, so a
/// clip the app asks for and the build does not produce shows up here as the
/// chef falling back to the device voice — which, before this, is what a
/// child heard for nearly everything.
void main() {
  final bank = SoundBank.fromJson(
    json.decode(File('assets/data/sound_bank.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final manifest = json.decode(
    File('assets/audio/manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final library = ClipLibrary.withClips(
    (manifest['clips'] as List).cast<String>().map(
      (path) => 'assets/audio/$path',
    ),
  );

  /// Everything the shipped clips can play, so the sink never reports a
  /// missing file for something the manifest promises.
  final everything = (manifest['clips'] as List)
      .cast<String>()
      .map((path) => 'assets/audio/$path')
      .toSet();

  ({SoupProvider provider, RecordingAudioSink sink}) kitchen() {
    final sink = RecordingAudioSink(availableAssets: everything);
    return (
      provider: SoupProvider(
        audio: AudioService(sink: sink, clips: library),
        random: Random(7),
      )..reducedMotion = true,
      sink: sink,
    );
  }

  test(
    'the chef never falls back to the device voice, for any sound',
    timeout: const Timeout(Duration(minutes: 3)),
    () async {
      for (final sound in bank.sounds) {
        final room = kitchen();
        room.provider.start(
          sound: sound,
          bank: bank,
          settings: const AppSettings(),
        );
        await room.provider.runChefModelling();

        final session = room.provider.session!;
        for (final word in session.pantry) {
          await room.provider.addItem(word);
        }
        await room.provider.finish();

        expect(
          room.sink.spokenText,
          isEmpty,
          reason:
              'the chef spoke instead of playing, for /${sound.id}/: '
              '${room.sink.spokenText}',
        );
        expect(room.sink.playedAssets, isNotEmpty);
      }
    },
  );

  test('a soup is recited from the pure sound up', () async {
    final room = kitchen();
    final sound = bank.sounds.firstWhere((s) => s.id == 's');

    room.provider.start(
      sound: sound,
      bank: bank,
      settings: const AppSettings(),
    );
    await room.provider.runChefModelling();

    // The pure sound first — the clip that did not exist at all before, and
    // the one the whole activity is built on.
    expect(room.sink.playedAssets.first, 'assets/audio/phonemes/s.mp3');

    // Then the chef's own soup: its commentary per ingredient, then the list.
    expect(
      room.sink.playedAssets,
      containsAllInOrder([
        'assets/audio/phonemes/s.mp3',
        'assets/audio/lines/watch_me.mp3',
        'assets/audio/lines/in_goes.mp3',
      ]),
    );
    expect(
      room.sink.playedAssets.where(
        (p) => p.startsWith('assets/audio/commentary/'),
      ),
      isNotEmpty,
    );
  });

  test('the growing list is played as one clip per ingredient', () async {
    final room = kitchen();
    final sound = bank.sounds.firstWhere((s) => s.id == 'b');

    room.provider.start(
      sound: sound,
      bank: bank,
      settings: const AppSettings(),
    );
    room.provider.beginChildsTurn();
    final pantry = room.provider.session!.pantry;

    await room.provider.addItem(pantry[0]);
    await room.provider.addItem(pantry[1]);

    // After the second ingredient the recital names both, in the order the
    // child chose them. No recording of that pair exists; it is assembled.
    final played = room.sink.playedAssets;
    expect(
      played,
      containsAllInOrder([
        'assets/audio/commentary/${pantry[1].word}.mp3',
        'assets/audio/lines/in_goes.mp3',
        'assets/audio/list/${pantry[0].word}.mp3',
        'assets/audio/list/${pantry[1].word}.mp3',
      ]),
    );
    expect(room.sink.spokenText, isEmpty);
  });

  test('praise and the tasting read-back are recorded too', () async {
    final room = kitchen();
    final sound = bank.sounds.firstWhere((s) => s.id == 'm');

    room.provider.start(
      sound: sound,
      bank: bank,
      settings: const AppSettings(),
    );
    room.provider.beginChildsTurn();
    final pantry = room.provider.session!.pantry;
    for (var i = 0; i < 3; i++) {
      await room.provider.addItem(pantry[i]);
    }
    await room.provider.finish();

    expect(
      room.sink.playedAssets.any(
        (p) => p.startsWith('assets/audio/lines/praise_'),
      ),
      isTrue,
    );
    expect(
      room.sink.playedAssets,
      containsAllInOrder([
        'assets/audio/lines/soup_has.mp3',
        'assets/audio/lines/and.mp3',
        'assets/audio/lines/in_it.mp3',
      ]),
    );
    expect(room.sink.spokenText, isEmpty);
  });
}
