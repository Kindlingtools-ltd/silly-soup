/// How a child puts an item into the pot.
enum InputMode {
  /// Drag an item across, and tap it as well if dragging is hard today.
  dragAndTap,

  /// Tap only. Simpler, and kinder to children who find dragging fiddly.
  tapOnly;

  static InputMode fromId(String? id) {
    for (final mode in InputMode.values) {
      if (mode.name == id) return mode;
    }
    return InputMode.dragAndTap;
  }
}

/// The optional modes. None of these are part of the original DfE activity,
/// and all of them are off until an adult turns them on.
enum ExtensionMode {
  /// One or two items on the shelf start with a different sound.
  oddOneOut,

  /// The pot is already full; the child picks the shared sound.
  whatsInTheSoup,

  /// Aspect 4: the items rhyme rather than alliterate.
  rhymingSoup;

  static ExtensionMode? fromId(String? id) {
    for (final mode in ExtensionMode.values) {
      if (mode.name == id) return mode;
    }
    return null;
  }

  String get label => switch (this) {
    ExtensionMode.oddOneOut => 'Odd one out soup',
    ExtensionMode.whatsInTheSoup => "What's in the soup?",
    ExtensionMode.rhymingSoup => 'Rhyming soup',
  };
}

/// Everything an adult can change, all of it stored on the device.
class AppSettings {
  const AppSettings({
    this.soundOrder = const ['s', 'a', 't', 'p', 'i', 'n', 'm', 'd', 'b'],
    this.enabledSoundIds = const ['s', 'a', 't', 'p', 'b'],
    this.pantrySize = 8,
    this.showLetters = false,
    this.inputMode = InputMode.dragAndTap,
    this.mirrorModeEnabled = false,
    this.volume = 1.0,
    this.reducedMotion = false,
    this.whiteboardMode = false,
    this.enabledExtensions = const [],
    this.observationNotesEnabled = false,
    this.customSongRecordingId,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      soundOrder:
          (json['soundOrder'] as List?)?.cast<String>() ?? defaults.soundOrder,
      enabledSoundIds:
          (json['enabledSoundIds'] as List?)?.cast<String>() ??
          defaults.enabledSoundIds,
      pantrySize: (json['pantrySize'] as int? ?? defaults.pantrySize).clamp(
        minPantrySize,
        maxPantrySize,
      ),
      showLetters: json['showLetters'] as bool? ?? defaults.showLetters,
      inputMode: InputMode.fromId(json['inputMode'] as String?),
      mirrorModeEnabled:
          json['mirrorModeEnabled'] as bool? ?? defaults.mirrorModeEnabled,
      volume: (json['volume'] as num? ?? defaults.volume).toDouble().clamp(
        0.0,
        1.0,
      ),
      reducedMotion: json['reducedMotion'] as bool? ?? defaults.reducedMotion,
      whiteboardMode:
          json['whiteboardMode'] as bool? ?? defaults.whiteboardMode,
      enabledExtensions: (json['enabledExtensions'] as List? ?? [])
          .whereType<String>()
          .map(ExtensionMode.fromId)
          .whereType<ExtensionMode>()
          .toList(),
      observationNotesEnabled:
          json['observationNotesEnabled'] as bool? ??
          defaults.observationNotesEnabled,
      customSongRecordingId: json['customSongRecordingId'] as String?,
    );
  }

  /// Sound ids in the order the school teaches them. Sounds missing from the
  /// bank are ignored at read time, so reordering never loses data.
  final List<String> soundOrder;

  /// Which sounds show up in the picker.
  final List<String> enabledSoundIds;

  /// How many items sit on the pantry shelf, 6 to 10.
  final int pantrySize;

  /// Phase Two mode: show the grapheme on the chef's sound card and the pot.
  /// Off by default — Phase One is sounds only.
  final bool showLetters;

  final InputMode inputMode;

  /// Front-camera mirror in "Watch my mouth". Live view only, never recorded.
  final bool mirrorModeEnabled;

  /// 0.0 to 1.0, applied to every clip and to speech.
  final double volume;

  /// Adult override for the system's reduce-motion preference.
  final bool reducedMotion;

  /// Extra-large, adult-paced layout for group sessions on a big screen.
  final bool whiteboardMode;

  /// Extension modes the adult has switched on.
  final List<ExtensionMode> enabledExtensions;

  /// "Look, listen and note" panel. Off by default, local only. (Stage 2)
  final bool observationNotesEnabled;

  /// Id of an adult's own recording of the soup song, when they have made one.
  final String? customSongRecordingId;

  static const AppSettings defaults = AppSettings();

  /// Smallest and largest pantry the shelf layout is designed for.
  static const int minPantrySize = 6;
  static const int maxPantrySize = 10;

  bool isSoundEnabled(String id) => enabledSoundIds.contains(id);

  bool isExtensionEnabled(ExtensionMode mode) =>
      enabledExtensions.contains(mode);

  Map<String, dynamic> toJson() {
    return {
      'soundOrder': soundOrder,
      'enabledSoundIds': enabledSoundIds,
      'pantrySize': pantrySize,
      'showLetters': showLetters,
      'inputMode': inputMode.name,
      'mirrorModeEnabled': mirrorModeEnabled,
      'volume': volume,
      'reducedMotion': reducedMotion,
      'whiteboardMode': whiteboardMode,
      'enabledExtensions': enabledExtensions.map((mode) => mode.name).toList(),
      'observationNotesEnabled': observationNotesEnabled,
      'customSongRecordingId': customSongRecordingId,
    };
  }

  AppSettings copyWith({
    List<String>? soundOrder,
    List<String>? enabledSoundIds,
    int? pantrySize,
    bool? showLetters,
    InputMode? inputMode,
    bool? mirrorModeEnabled,
    double? volume,
    bool? reducedMotion,
    bool? whiteboardMode,
    List<ExtensionMode>? enabledExtensions,
    bool? observationNotesEnabled,
    String? customSongRecordingId,
    bool clearCustomSongRecording = false,
  }) {
    return AppSettings(
      soundOrder: soundOrder ?? this.soundOrder,
      enabledSoundIds: enabledSoundIds ?? this.enabledSoundIds,
      pantrySize: (pantrySize ?? this.pantrySize).clamp(
        minPantrySize,
        maxPantrySize,
      ),
      showLetters: showLetters ?? this.showLetters,
      inputMode: inputMode ?? this.inputMode,
      mirrorModeEnabled: mirrorModeEnabled ?? this.mirrorModeEnabled,
      volume: (volume ?? this.volume).clamp(0.0, 1.0),
      reducedMotion: reducedMotion ?? this.reducedMotion,
      whiteboardMode: whiteboardMode ?? this.whiteboardMode,
      enabledExtensions: enabledExtensions ?? this.enabledExtensions,
      observationNotesEnabled:
          observationNotesEnabled ?? this.observationNotesEnabled,
      customSongRecordingId: clearCustomSongRecording
          ? null
          : (customSongRecordingId ?? this.customSongRecordingId),
    );
  }
}
