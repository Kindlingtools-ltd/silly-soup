import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/models/models.dart';

void main() {
  group('defaults', () {
    test('Phase One out of the box: no letters on screen', () {
      expect(AppSettings.defaults.showLetters, isFalse);
    });

    test('the camera is off until an adult turns it on', () {
      expect(AppSettings.defaults.mirrorModeEnabled, isFalse);
    });

    test('no extension mode is on by default', () {
      expect(AppSettings.defaults.enabledExtensions, isEmpty);
    });

    test('observation notes are off by default', () {
      expect(AppSettings.defaults.observationNotesEnabled, isFalse);
    });

    test('the starter sounds are the ones Stage 1 ships', () {
      expect(AppSettings.defaults.enabledSoundIds, ['s', 'a', 't', 'p', 'b']);
    });
  });

  group('bounds', () {
    // Clamping happens where values come in from outside — the adult area
    // goes through copyWith, stored settings go through fromJson.
    test('pantry size is clamped to what the shelf can lay out', () {
      expect(
        AppSettings.defaults.copyWith(pantrySize: 2).pantrySize,
        AppSettings.minPantrySize,
      );
      expect(
        AppSettings.defaults.copyWith(pantrySize: 99).pantrySize,
        AppSettings.maxPantrySize,
      );
    });

    test('volume is clamped to 0..1', () {
      expect(AppSettings.defaults.copyWith(volume: 4).volume, 1.0);
      expect(AppSettings.defaults.copyWith(volume: -1).volume, 0.0);
    });
  });

  group('json', () {
    test('round trips', () {
      const settings = AppSettings(
        soundOrder: ['b', 's'],
        enabledSoundIds: ['b'],
        pantrySize: 10,
        showLetters: true,
        inputMode: InputMode.tapOnly,
        mirrorModeEnabled: true,
        volume: 0.5,
        reducedMotion: true,
        whiteboardMode: true,
        enabledExtensions: [ExtensionMode.oddOneOut],
        observationNotesEnabled: true,
      );

      final restored = AppSettings.fromJson(settings.toJson());

      expect(restored.soundOrder, settings.soundOrder);
      expect(restored.enabledSoundIds, settings.enabledSoundIds);
      expect(restored.pantrySize, 10);
      expect(restored.showLetters, isTrue);
      expect(restored.inputMode, InputMode.tapOnly);
      expect(restored.mirrorModeEnabled, isTrue);
      expect(restored.volume, 0.5);
      expect(restored.reducedMotion, isTrue);
      expect(restored.whiteboardMode, isTrue);
      expect(restored.enabledExtensions, [ExtensionMode.oddOneOut]);
      expect(restored.observationNotesEnabled, isTrue);
    });

    test('missing fields fall back to the defaults', () {
      final restored = AppSettings.fromJson(<String, dynamic>{});

      expect(restored.showLetters, AppSettings.defaults.showLetters);
      expect(restored.pantrySize, AppSettings.defaults.pantrySize);
      expect(restored.inputMode, AppSettings.defaults.inputMode);
    });

    test('an unknown extension mode is dropped rather than crashing', () {
      final restored = AppSettings.fromJson({
        'enabledExtensions': ['oddOneOut', 'somethingFromTheFuture'],
      });

      expect(restored.enabledExtensions, [ExtensionMode.oddOneOut]);
    });

    test('a clamped value on disk is clamped on the way back in', () {
      final restored = AppSettings.fromJson({'pantrySize': 40, 'volume': 9.0});

      expect(restored.pantrySize, AppSettings.maxPantrySize);
      expect(restored.volume, 1.0);
    });
  });

  test('copyWith can clear the adult song recording', () {
    const settings = AppSettings(customSongRecordingId: 'abc');

    expect(settings.copyWith().customSongRecordingId, 'abc');
    expect(
      settings.copyWith(clearCustomSongRecording: true).customSongRecordingId,
      isNull,
    );
  });
}
