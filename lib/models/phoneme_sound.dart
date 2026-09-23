import 'articulation.dart';
import 'mouth_shape.dart';

/// A speech sound the chef can cook with.
///
/// Phase One is about sounds, not letters, so [grapheme] is only ever shown
/// when an adult turns on "Show letters" (Phase Two mode).
class PhonemeSound {
  const PhonemeSound({
    required this.id,
    required this.label,
    required this.grapheme,
    required this.articulation,
    required this.pureSound,
    this.audio,
    this.mouthShape = MouthShape.openSmall,
    this.mouthTip = '',
    this.action = '',
    this.isVowel = false,
    this.enabledByDefault = false,
    this.notes = '',
    this.isCustom = false,
    this.hidden = false,
  });

  factory PhonemeSound.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String? ?? '').trim();
    return PhonemeSound(
      id: id,
      label: (json['label'] as String? ?? id).trim(),
      grapheme: (json['grapheme'] as String? ?? id).trim(),
      articulation: Articulation.fromId(json['articulation'] as String?),
      pureSound: (json['pureSound'] as String? ?? id).trim(),
      audio: (json['audio'] as String?)?.trim(),
      mouthShape: MouthShape.fromId(json['mouthShape'] as String?),
      mouthTip: json['mouthTip'] as String? ?? '',
      action: json['action'] as String? ?? '',
      isVowel: json['isVowel'] as bool? ?? false,
      enabledByDefault: json['enabledByDefault'] as bool? ?? false,
      notes: json['notes'] as String? ?? '',
      isCustom: json['isCustom'] as bool? ?? false,
      hidden: json['hidden'] as bool? ?? false,
    );
  }

  /// Stable id used everywhere else in the data: `s`, `b`, `sh`.
  final String id;

  /// How an adult refers to the sound in the adult area: `s`, `sh`.
  final String label;

  /// The letter(s) to show in Phase Two mode.
  final String grapheme;

  /// Whether the sound is stretched or bounced. See [Articulation].
  final Articulation articulation;

  /// How the pure sound is written out for the chef: `sss`, `b`.
  /// Never contains an added "uh".
  final String pureSound;

  /// Path of the recorded pure sound, relative to `assets/audio/`.
  final String? audio;

  final MouthShape mouthShape;

  /// One sentence a child can follow: "Press your lips together and hum."
  final String mouthTip;

  /// The action the chef does with the sound.
  final String action;

  final bool isVowel;

  /// Whether the sound is switched on the first time the app is opened.
  final bool enabledByDefault;

  /// Adult-facing notes: accent warnings, "keep away from /n/", and so on.
  final String notes;

  /// True for adult-added sounds.
  final bool isCustom;

  /// Hidden sounds stay in the bank but never reach the sound picker.
  final bool hidden;

  /// True when the sound can be held on rather than bounced.
  bool get isContinuant => articulation == Articulation.continuant;

  /// Full asset path of the recorded pure sound, or null when there is none.
  String? get audioAssetPath =>
      audio == null || audio!.isEmpty ? null : 'assets/audio/$audio';

  /// How the chef says the sound on its own: `sss` or `b-b-b`.
  String get spokenPureSound =>
      isContinuant ? pureSound : List.filled(3, pureSound).join('-');

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'grapheme': grapheme,
      'articulation': articulation.id,
      'pureSound': pureSound,
      'audio': audio,
      'mouthShape': mouthShape.id,
      'mouthTip': mouthTip,
      'action': action,
      'isVowel': isVowel,
      'enabledByDefault': enabledByDefault,
      'notes': notes,
      if (isCustom) 'isCustom': true,
      if (hidden) 'hidden': true,
    };
  }

  PhonemeSound copyWith({
    String? id,
    String? label,
    String? grapheme,
    Articulation? articulation,
    String? pureSound,
    String? audio,
    MouthShape? mouthShape,
    String? mouthTip,
    String? action,
    bool? isVowel,
    bool? enabledByDefault,
    String? notes,
    bool? isCustom,
    bool? hidden,
  }) {
    return PhonemeSound(
      id: id ?? this.id,
      label: label ?? this.label,
      grapheme: grapheme ?? this.grapheme,
      articulation: articulation ?? this.articulation,
      pureSound: pureSound ?? this.pureSound,
      audio: audio ?? this.audio,
      mouthShape: mouthShape ?? this.mouthShape,
      mouthTip: mouthTip ?? this.mouthTip,
      action: action ?? this.action,
      isVowel: isVowel ?? this.isVowel,
      enabledByDefault: enabledByDefault ?? this.enabledByDefault,
      notes: notes ?? this.notes,
      isCustom: isCustom ?? this.isCustom,
      hidden: hidden ?? this.hidden,
    );
  }

  @override
  bool operator ==(Object other) => other is PhonemeSound && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PhonemeSound($id)';
}
