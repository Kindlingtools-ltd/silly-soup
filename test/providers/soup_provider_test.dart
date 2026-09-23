import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/models/models.dart';
import 'package:silly_soup/providers/providers.dart';
import 'package:silly_soup/services/services.dart';

import '../test_data.dart';

/// A sink whose speech takes real time, so the tests can tell whether the
/// chef waits for a line to finish before starting the next one.
class SlowSink implements AudioSink {
  SlowSink({this.speakDuration = const Duration(milliseconds: 120)});

  final Duration speakDuration;
  final List<String> spoken = [];
  final List<String> events = [];
  int speaking = 0;
  int maxConcurrent = 0;

  Completer<void>? _current;

  Future<void> _utter(String label) async {
    spoken.add(label);
    events.add('start:$label');
    speaking++;
    maxConcurrent = max(maxConcurrent, speaking);
    final cancelled = _current = Completer<void>();
    await Future.any([Future<void>.delayed(speakDuration), cancelled.future]);
    if (identical(_current, cancelled)) _current = null;
    speaking--;
    events.add('end:$label');
  }

  @override
  Future<bool> playAsset(String assetPath, {required double volume}) async =>
      false;

  @override
  Future<void> speak(String text, {required double volume}) => _utter(text);

  // The real sink stops the platform voice mid-word. A fake that ignores
  // stop() would let the test pass a contract the app does not actually have.
  @override
  Future<void> stop() async {
    final current = _current;
    _current = null;
    if (current != null && !current.isCompleted) current.complete();
  }

  @override
  Future<void> dispose() async {}
}

SoupProvider buildProvider(SlowSink sink, {bool adultPaced = false}) {
  return SoupProvider(
      audio: AudioService(sink: sink),
      random: Random(7),
    )
    ..reducedMotion = true
    ..adultPaced = adultPaced;
}

void main() {
  group('the chef waits for itself', () {
    test('never starts a line before the last one has finished', () async {
      final sink = SlowSink();
      final provider = buildProvider(sink);

      provider.start(
        sound: soundB,
        bank: testBank,
        settings: const AppSettings(pantrySize: 6),
      );
      await provider.runChefModelling();

      // The bug this guards: speak() used to return as soon as speech began,
      // so the next line's stop() cut the previous one off mid-word.
      expect(sink.maxConcurrent, 1, reason: 'lines overlapped: ${sink.events}');
      expect(sink.spoken.length, greaterThan(3));
    });

    test('each item is named while the child is putting it in', () async {
      final sink = SlowSink();
      final provider = buildProvider(sink);
      provider.start(
        sound: soundB,
        bank: testBank,
        settings: const AppSettings(pantrySize: 6),
      );
      provider.beginChildsTurn();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      sink.spoken.clear();

      final item = provider.session!.pantry.first;
      await provider.addItem(item);

      expect(sink.maxConcurrent, 1, reason: sink.events.toString());
      expect(sink.spoken.first, contains(item.word));
    });
  });

  group('the chef fills the pot as it talks', () {
    test('items appear one at a time, not all three at once', () async {
      final sink = SlowSink();
      final provider = buildProvider(sink);
      provider.start(
        sound: soundB,
        bank: testBank,
        settings: const AppSettings(pantrySize: 6),
      );

      expect(provider.chefItemsShown, 0);

      final seen = <int>[];
      provider.addListener(() => seen.add(provider.chefItemsShown));
      await provider.runChefModelling();

      expect(seen, containsAllInOrder([1, 2, 3]));
      expect(provider.chefItemsShown, 3);
    });

    test('a new soup starts with an empty pot again', () async {
      final sink = SlowSink();
      final provider = buildProvider(sink);
      provider.start(
        sound: soundB,
        bank: testBank,
        settings: const AppSettings(pantrySize: 6),
      );
      await provider.runChefModelling();
      expect(provider.chefItemsShown, 3);

      provider.start(
        sound: soundB,
        bank: testBank,
        settings: const AppSettings(pantrySize: 6),
      );

      expect(provider.chefItemsShown, 0);
    });
  });

  group('whiteboard mode is adult-paced', () {
    test(
      'the chef stops and waits instead of handing over by itself',
      () async {
        final sink = SlowSink();
        final provider = buildProvider(sink, adultPaced: true);
        provider.start(
          sound: soundB,
          bank: testBank,
          settings: const AppSettings(pantrySize: 6, whiteboardMode: true),
        );

        await provider.runChefModelling();

        expect(provider.session!.stage, SoupStage.chefModelling);
        expect(provider.isChefBusy, isFalse, reason: 'the adult can act');

        provider.beginChildsTurn();
        expect(provider.session!.stage, SoupStage.childsTurn);
      },
    );

    test('a normal session hands over by itself', () async {
      final sink = SlowSink();
      final provider = buildProvider(sink);
      provider.start(
        sound: soundB,
        bank: testBank,
        settings: const AppSettings(pantrySize: 6),
      );

      await provider.runChefModelling();

      expect(provider.session!.stage, SoupStage.childsTurn);
    });

    test('adult pacing does not make the demonstration faster', () async {
      // It used to drop every pause, so whiteboard mode raced.
      final paced = buildProvider(SlowSink(), adultPaced: true);
      final normal = buildProvider(SlowSink());
      for (final provider in [paced, normal]) {
        provider.start(
          sound: soundB,
          bank: testBank,
          settings: const AppSettings(pantrySize: 6),
        );
      }

      final pacedStart = DateTime.now();
      await paced.runChefModelling();
      final pacedTime = DateTime.now().difference(pacedStart);

      final normalStart = DateTime.now();
      await normal.runChefModelling();
      final normalTime = DateTime.now().difference(normalStart);

      expect(
        pacedTime.inMilliseconds,
        greaterThan((normalTime.inMilliseconds * 0.6).round()),
      );
    });
  });

  test('leaving the kitchen silences the chef', () async {
    final sink = SlowSink();
    final provider = buildProvider(sink);
    provider.start(
      sound: soundB,
      bank: testBank,
      settings: const AppSettings(pantrySize: 6),
    );

    provider.clear();

    expect(provider.session, isNull);
    expect(provider.chefItemsShown, 0);
    expect(provider.chefLine, isEmpty);
  });
}
