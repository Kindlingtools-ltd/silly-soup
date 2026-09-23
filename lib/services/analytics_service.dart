import '../models/models.dart';
import 'analytics_sink.dart';

/// What Silly Soup reports about how it is used.
///
/// Every event here describes the *app*: which sound was picked, how many
/// things went into the pot, which setting an adult moved. Nothing here
/// describes a child. No name, no free text, no initials, no observation
/// note, no microphone, no camera frame and no device identifier of our own
/// ever reaches this class — see PRIVACY.md, which lists the events by name.
///
/// Every method is fire-and-forget. Analytics must never be able to slow a
/// tap down or fail a turn, so nothing here returns a future and nothing
/// here throws.
class AnalyticsService {
  AnalyticsService({AnalyticsSink? sink})
    : _sink = sink ?? const GtagAnalyticsSink();

  final AnalyticsSink _sink;

  /// Report one event. Snake case, like the rest of GA4.
  void logEvent(String name, [Map<String, Object> parameters = const {}]) {
    _sink.send(name, parameters);
  }

  /// A screen the adult or child has arrived at.
  ///
  /// Sent as `page_view` rather than `screen_view`: this is a web stream, and
  /// GA4 reserves `screen_view` for app streams and drops it. The app is a
  /// single page whose URL never changes, so the screen travels in the title
  /// and `send_page_view` is off in the tag — see `web/index.html`.
  void logScreenView(String screen) {
    logEvent('page_view', {
      'page_title': 'Silly Soup — $screen',
      'screen_name': screen,
    });
  }

  /// The app has finished loading and the sound picker is up.
  void logAppStarted(AppSettings settings, {required int soundCount}) {
    logEvent('app_started', {
      'sounds_available': soundCount,
      'pantry_size': settings.pantrySize,
      'show_letters': settings.showLetters,
      'whiteboard_mode': settings.whiteboardMode,
      'input_mode': settings.inputMode.name,
      'mirror_enabled': settings.mirrorModeEnabled,
    });
  }

  /// The app could not load its ingredients.
  void logStartupFailed() => logEvent('app_start_failed');

  /// A sound was picked and a new soup opened.
  void logSoupStarted(PhonemeSound sound, {required int pantrySize}) {
    logEvent('soup_started', {'sound': sound.id, 'pantry_size': pantrySize});
  }

  /// The child asked to hear the sound again.
  void logSoundRepeated(PhonemeSound sound) =>
      logEvent('sound_repeated', {'sound': sound.id});

  /// The chef started modelling a soup of its own.
  void logChefModelled(PhonemeSound sound) =>
      logEvent('chef_modelled', {'sound': sound.id});

  /// The pot was handed over. This is the part of the activity that matters,
  /// so it is worth knowing how many soups get this far.
  void logChildsTurnStarted(PhonemeSound sound) =>
      logEvent('childs_turn_started', {'sound': sound.id});

  /// Something went into the pot.
  void logIngredientAdded({
    required PhonemeSound sound,
    required SoupWord word,
    required int potSize,
  }) {
    logEvent('ingredient_added', {
      'sound': sound.id,
      'word': word.word,
      'pot_size': potSize,
      'has_cluster': word.hasCluster,
    });
  }

  /// Something came back out — an adult undoing a mis-tap, usually.
  void logIngredientRemoved({
    required PhonemeSound sound,
    required SoupWord word,
    required int potSize,
  }) {
    logEvent('ingredient_removed', {
      'sound': sound.id,
      'word': word.word,
      'pot_size': potSize,
    });
  }

  /// The pot was stirred on purpose, rather than automatically.
  void logSoupStirred(PhonemeSound sound) =>
      logEvent('soup_stirred', {'sound': sound.id});

  /// "All done!" — the soup ran to the silly tasting.
  void logSoupFinished({
    required PhonemeSound sound,
    required int ingredientCount,
    required Duration duration,
  }) {
    logEvent('soup_finished', {
      'sound': sound.id,
      'ingredient_count': ingredientCount,
      'duration_ms': duration.inMilliseconds,
    });
  }

  /// The kitchen was left before the tasting. Not a failure — three-year-olds
  /// wander off — but it is the difference between a soup and a glance.
  void logSoupAbandoned({
    required PhonemeSound sound,
    required SoupStage stage,
    required int ingredientCount,
    required Duration duration,
  }) {
    logEvent('soup_abandoned', {
      'sound': sound.id,
      'stage': stage.name,
      'ingredient_count': ingredientCount,
      'duration_ms': duration.inMilliseconds,
    });
  }

  /// "Watch my mouth" was opened.
  void logMouthViewOpened(PhonemeSound sound, {required bool mirrorShown}) {
    logEvent('mouth_view_opened', {
      'sound': sound.id,
      'mirror_shown': mirrorShown,
    });
  }

  /// The soup song was played.
  void logSongPlayed() => logEvent('song_played');

  /// The mute button was used.
  void logAudioStopped() => logEvent('audio_stopped');

  /// The press-and-hold gate was held long enough to open the adult area.
  void logAdultAreaOpened() => logEvent('adult_area_opened');

  /// One setting an adult changed. Reported one event per setting so a
  /// single save that flips two things reads as two changes.
  void logSettingChanged(String setting, Object value) {
    logEvent('setting_changed', {'setting': setting, 'value': value});
  }

  /// Report everything that differs between two sets of settings.
  void logSettingsChanged(AppSettings before, AppSettings after) {
    settingChanges(before, after).forEach(logSettingChanged);
  }

  /// What changed between two sets of settings, as GA4-safe values.
  ///
  /// Pure, so the thing that decides what leaves the device is testable
  /// without a tag. Lists are reduced to a count or a short id list rather
  /// than sent whole: a teacher's sound order is nine ids, but a Stage 2
  /// custom pack could be any length, and an event parameter is capped at
  /// 100 characters.
  static Map<String, Object> settingChanges(
    AppSettings before,
    AppSettings after,
  ) {
    final changes = <String, Object>{};

    void compare(String name, Object was, Object now) {
      if (was != now) changes[name] = now;
    }

    compare('pantry_size', before.pantrySize, after.pantrySize);
    compare('show_letters', before.showLetters, after.showLetters);
    compare('input_mode', before.inputMode.name, after.inputMode.name);
    compare(
      'mirror_enabled',
      before.mirrorModeEnabled,
      after.mirrorModeEnabled,
    );
    // One decimal place. The slider has ten stops, and a raw double would
    // make 0.7000000000000001 its own reporting bucket.
    compare(
      'volume',
      double.parse(before.volume.toStringAsFixed(1)),
      double.parse(after.volume.toStringAsFixed(1)),
    );
    compare('reduced_motion', before.reducedMotion, after.reducedMotion);
    compare('whiteboard_mode', before.whiteboardMode, after.whiteboardMode);
    compare(
      'observation_notes',
      before.observationNotesEnabled,
      after.observationNotesEnabled,
    );
    compare(
      'sounds_enabled',
      before.enabledSoundIds.length,
      after.enabledSoundIds.length,
    );
    if (!_sameOrder(before.soundOrder, after.soundOrder)) {
      changes['sound_order'] = _cap(after.soundOrder.join(','));
    }
    compare(
      'extensions_enabled',
      before.enabledExtensions.length,
      after.enabledExtensions.length,
    );

    return changes;
  }

  static bool _sameOrder(List<String> before, List<String> after) {
    if (before.length != after.length) return false;
    for (var index = 0; index < before.length; index++) {
      if (before[index] != after[index]) return false;
    }
    return true;
  }

  /// GA4 truncates an event parameter at 100 characters. Do it here instead,
  /// so a long Stage 2 sound pack is visibly clipped rather than mangled.
  static String _cap(String value) =>
      value.length <= 100 ? value : '${value.substring(0, 97)}...';
}
