import 'models.dart' show PhonemeSound;
import 'phoneme_sound.dart' show PhonemeSound;
import 'word_image.dart';

/// One pantry item: a word a child can drop into the soup.
///
/// The JSON shape is the contract for adult-authored sound packs, so the
/// field names here are also the field names a teacher will type by hand.
class SoupWord {
  const SoupWord({
    required this.word,
    required this.phoneme,
    required this.image,
    this.audio,
    this.hasCluster = false,
    this.difficulty = 1,
    this.notes = '',
    String? initialGrapheme,
    this.isCustom = false,
    this.hidden = false,
  }) : initialGrapheme = initialGrapheme ?? '';

  factory SoupWord.fromJson(Map<String, dynamic> json) {
    return SoupWord(
      word: (json['word'] as String? ?? '').trim(),
      phoneme: (json['phoneme'] as String? ?? '').trim(),
      image: (json['image'] as String? ?? '').trim(),
      audio: (json['audio'] as String?)?.trim(),
      hasCluster: json['hasCluster'] as bool? ?? false,
      difficulty: json['difficulty'] as int? ?? 1,
      notes: json['notes'] as String? ?? '',
      initialGrapheme: (json['initialGrapheme'] as String?)?.trim(),
      isCustom: json['isCustom'] as bool? ?? false,
      hidden: json['hidden'] as bool? ?? false,
    );
  }

  /// The word itself, lower case: `banana`.
  final String word;

  /// Id of the [PhonemeSound] this word starts with. Sounds, not letters —
  /// `cat` and `kite` would both carry the phoneme `k`.
  final String phoneme;

  /// Picture for the pantry shelf. See [WordImage] for the prefixes.
  final String image;

  /// Path of the recorded clip, relative to `assets/audio/`.
  /// Null or missing means "fall back to speech and log it".
  final String? audio;

  /// True when the word actually starts with a consonant cluster
  /// (`spoon`, `star`). These are fine to listen to, but children are not
  /// expected to produce clusters in Phase One, so adults can filter them.
  final bool hasCluster;

  /// 1 = shortest and most familiar, 3 = longer or less common.
  final int difficulty;

  /// Free text for the adult: picture caveats, accent warnings, anything a
  /// teacher should read before using the word.
  final String notes;

  /// The letters that spell the initial sound. Usually the first letter, but
  /// a custom sound like `sh` needs two, and `kite` under phoneme `k` needs
  /// `k` rather than `c`. Used when the chef bounces a stop sound.
  final String initialGrapheme;

  /// True for adult-added words. Built-in words can be hidden but not deleted.
  final bool isCustom;

  /// Hidden words stay in the bank but never reach the pantry.
  final bool hidden;

  /// Stable identity for a word within the bank.
  String get id => '$phoneme:$word';

  /// The letters to bounce or stretch. Falls back to the first letter of the
  /// word when a pack does not spell it out.
  String get emphasisGrapheme => initialGrapheme.isNotEmpty
      ? initialGrapheme
      : (word.isEmpty ? '' : word[0]);

  WordImage get parsedImage => WordImage.parse(image);

  /// Full asset path of the recorded clip, or null when there is none.
  String? get audioAssetPath =>
      audio == null || audio!.isEmpty ? null : 'assets/audio/$audio';

  Map<String, dynamic> toJson() {
    return {
      'word': word,
      'phoneme': phoneme,
      'image': image,
      'audio': audio,
      'hasCluster': hasCluster,
      'difficulty': difficulty,
      'notes': notes,
      if (initialGrapheme.isNotEmpty) 'initialGrapheme': initialGrapheme,
      if (isCustom) 'isCustom': true,
      if (hidden) 'hidden': true,
    };
  }

  SoupWord copyWith({
    String? word,
    String? phoneme,
    String? image,
    String? audio,
    bool? hasCluster,
    int? difficulty,
    String? notes,
    String? initialGrapheme,
    bool? isCustom,
    bool? hidden,
  }) {
    return SoupWord(
      word: word ?? this.word,
      phoneme: phoneme ?? this.phoneme,
      image: image ?? this.image,
      audio: audio ?? this.audio,
      hasCluster: hasCluster ?? this.hasCluster,
      difficulty: difficulty ?? this.difficulty,
      notes: notes ?? this.notes,
      initialGrapheme: initialGrapheme ?? this.initialGrapheme,
      isCustom: isCustom ?? this.isCustom,
      hidden: hidden ?? this.hidden,
    );
  }

  @override
  bool operator ==(Object other) => other is SoupWord && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SoupWord($id)';
}
