import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/models/models.dart';
import 'package:silly_soup/services/services.dart';

import '../test_data.dart';

void main() {
  late RecordingAnalyticsSink sink;
  late AnalyticsService analytics;

  setUp(() {
    sink = RecordingAnalyticsSink();
    analytics = AnalyticsService(sink: sink);
  });

  group('screen views', () {
    test(
      'go out as page_view, because GA4 drops screen_view on a web stream',
      () {
        analytics.logScreenView('soup');

        final event = sink.events.single;
        expect(event.name, 'page_view');
        expect(event.parameters['screen_name'], 'soup');
        expect(event.parameters['page_title'], contains('soup'));
      },
    );
  });

  group('soup events', () {
    test('carry the sound, not anything about the child', () {
      analytics.logSoupFinished(
        sound: soundS,
        ingredientCount: 4,
        duration: const Duration(seconds: 42),
      );

      final event = sink.events.single;
      expect(event.name, 'soup_finished');
      expect(event.parameters, {
        'sound': 's',
        'ingredient_count': 4,
        'duration_ms': 42000,
      });
    });

    test('an added ingredient reports the pantry word and the pot size', () {
      analytics.logIngredientAdded(
        sound: soundS,
        word: word('spoon', 's', hasCluster: true),
        potSize: 2,
      );

      expect(sink.events.single.parameters, {
        'sound': 's',
        'word': 'spoon',
        'pot_size': 2,
        'has_cluster': true,
      });
    });

    test('an abandoned soup says which stage it was left at', () {
      analytics.logSoupAbandoned(
        sound: soundB,
        stage: SoupStage.childsTurn,
        ingredientCount: 1,
        duration: const Duration(seconds: 3),
      );

      expect(sink.events.single.parameters['stage'], 'childsTurn');
    });
  });

  group('settingChanges', () {
    test('is empty when nothing moved', () {
      expect(
        AnalyticsService.settingChanges(
          AppSettings.defaults,
          AppSettings.defaults,
        ),
        isEmpty,
      );
    });

    test('reports one entry per setting that actually moved', () {
      final changes = AnalyticsService.settingChanges(
        AppSettings.defaults,
        AppSettings.defaults.copyWith(showLetters: true, pantrySize: 10),
      );

      expect(changes, {'pantry_size': 10, 'show_letters': true});
    });

    test('rounds the volume, so a slider does not invent buckets', () {
      final changes = AnalyticsService.settingChanges(
        AppSettings.defaults.copyWith(volume: 1),
        AppSettings.defaults.copyWith(volume: 0.7000000000000001),
      );

      expect(changes, {'volume': 0.7});
    });

    test('sends counts for sound and extension lists, not their contents', () {
      final changes = AnalyticsService.settingChanges(
        AppSettings.defaults,
        AppSettings.defaults.copyWith(enabledSoundIds: ['s', 'a']),
      );

      expect(changes, {'sounds_enabled': 2});
    });

    test('sends the sound order, capped at what GA4 will keep', () {
      final long = [for (var i = 0; i < 60; i++) 'sound$i'];
      final changes = AnalyticsService.settingChanges(
        AppSettings.defaults,
        AppSettings.defaults.copyWith(soundOrder: long),
      );

      expect(
        (changes['sound_order']! as String).length,
        lessThanOrEqualTo(100),
      );
    });

    test('a reorder of the same sounds still counts as a change', () {
      final changes = AnalyticsService.settingChanges(
        AppSettings.defaults.copyWith(soundOrder: ['s', 'a', 't']),
        AppSettings.defaults.copyWith(soundOrder: ['t', 'a', 's']),
      );

      expect(changes, {'sound_order': 't,a,s'});
    });

    test('logSettingsChanged sends one event per change', () {
      analytics.logSettingsChanged(
        AppSettings.defaults,
        AppSettings.defaults.copyWith(showLetters: true, whiteboardMode: true),
      );

      expect(sink.names, ['setting_changed', 'setting_changed']);
      expect(
        sink.allOf('setting_changed').map((e) => e.parameters['setting']),
        containsAll(<String>['show_letters', 'whiteboard_mode']),
      );
    });
  });

  test('every parameter GA4 is given is a string, number or boolean', () {
    analytics
      ..logAppStarted(AppSettings.defaults, soundCount: 5)
      ..logSoupStarted(soundS, pantrySize: 8)
      ..logSoundRepeated(soundS)
      ..logChefModelled(soundS)
      ..logChildsTurnStarted(soundS)
      ..logIngredientAdded(sound: soundS, word: word('sun', 's'), potSize: 1)
      ..logIngredientRemoved(sound: soundS, word: word('sun', 's'), potSize: 0)
      ..logSoupStirred(soundS)
      ..logMouthViewOpened(soundS, mirrorShown: false)
      ..logSongPlayed()
      ..logAudioStopped()
      ..logAdultAreaOpened()
      ..logStartupFailed();

    for (final event in sink.events) {
      for (final value in event.parameters.values) {
        expect(
          value,
          anyOf(isA<String>(), isA<num>(), isA<bool>()),
          reason: '${event.name} sends a value GA4 cannot take',
        );
      }
    }
  });
}
