import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/models/models.dart';
import 'package:silly_soup/providers/providers.dart';
import 'package:silly_soup/services/services.dart';

import '../test_data.dart';

/// A clock that moves a second every time it is read, so a duration in an
/// event is something the test can actually assert on.
class TickingClock {
  var _seconds = 0;

  DateTime call() => DateTime(2026).add(Duration(seconds: _seconds++));
}

void main() {
  late RecordingAnalyticsSink sink;
  late SoupProvider provider;

  const settings = AppSettings(pantrySize: 6);

  setUp(() {
    sink = RecordingAnalyticsSink();
    provider = SoupProvider(
      audio: AudioService(sink: RecordingAudioSink()),
      analytics: AnalyticsService(sink: sink),
      random: Random(7),
      now: TickingClock().call,
    )..reducedMotion = true;
  });

  void startSoup() =>
      provider.start(sound: soundB, bank: testBank, settings: settings);

  test('opening a soup reports the sound and the pantry it was given', () {
    startSoup();

    final event = sink.firstOf('soup_started')!;
    expect(event.parameters['sound'], 'b');
    expect(event.parameters['pantry_size'], provider.session!.pantry.length);
  });

  test('the chef modelling and the hand-over are both reported', () async {
    startSoup();
    await provider.runChefModelling();

    expect(
      sink.names,
      containsAllInOrder(<String>[
        'soup_started',
        'chef_modelled',
        'childs_turn_started',
      ]),
    );
  });

  test(
    'each item in and out of the pot is reported with the pot size',
    () async {
      startSoup();
      provider.beginChildsTurn();
      final item = provider.session!.pantry.first;

      await provider.addItem(item);
      expect(sink.firstOf('ingredient_added')!.parameters, {
        'sound': 'b',
        'word': item.word,
        'pot_size': 1,
        'has_cluster': item.hasCluster,
      });

      provider.removeItem(item);
      expect(sink.firstOf('ingredient_removed')!.parameters['pot_size'], 0);
    },
  );

  test('taking out something that was never in reports nothing', () {
    startSoup();
    provider.beginChildsTurn();

    provider.removeItem(provider.session!.pantry.first);

    expect(sink.allOf('ingredient_removed'), isEmpty);
  });

  test('only a deliberate stir is reported, not the automatic ones', () async {
    startSoup();
    provider.beginChildsTurn();
    await provider.addItem(provider.session!.pantry.first);

    expect(sink.allOf('soup_stirred'), isEmpty);

    await provider.stirOnDemand();

    expect(sink.allOf('soup_stirred'), hasLength(1));
  });

  test(
    'a finished soup reports how much went in and how long it took',
    () async {
      startSoup();
      provider.beginChildsTurn();
      await provider.addItem(provider.session!.pantry.first);
      await provider.finish();

      final event = sink.firstOf('soup_finished')!;
      expect(event.parameters['sound'], 'b');
      expect(event.parameters['ingredient_count'], 1);
      expect(event.parameters['duration_ms'], greaterThan(0));
      expect(sink.allOf('soup_abandoned'), isEmpty);
    },
  );

  test('leaving a finished soup is not abandoning it', () async {
    startSoup();
    provider.beginChildsTurn();
    await provider.addItem(provider.session!.pantry.first);
    await provider.finish();

    provider.clear();

    expect(sink.allOf('soup_abandoned'), isEmpty);
  });

  test('backing out mid-turn is reported, with the stage it got to', () async {
    startSoup();
    provider.beginChildsTurn();
    await provider.addItem(provider.session!.pantry.first);

    provider.clear();

    final event = sink.firstOf('soup_abandoned')!;
    expect(event.parameters['stage'], 'childsTurn');
    expect(event.parameters['ingredient_count'], 1);
    expect(event.parameters['duration_ms'], greaterThan(0));
  });

  test('"Make another soup?" over a live soup abandons the old one', () {
    startSoup();
    provider.beginChildsTurn();

    startSoup();

    expect(sink.allOf('soup_abandoned'), hasLength(1));
    expect(sink.allOf('soup_started'), hasLength(2));
  });

  test('clearing when there is no soup reports nothing', () {
    provider.clear();

    expect(sink.events, isEmpty);
  });

  test('asking for the sound again is reported', () async {
    startSoup();

    await provider.repeatSound();

    expect(sink.allOf('sound_repeated'), hasLength(1));
  });
}
