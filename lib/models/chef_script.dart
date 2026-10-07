/// Every fixed line the chef says, loaded from `assets/data/chef_script.json`.
///
/// The lines live in an asset rather than in Dart because two things need
/// them and they must not drift: the app shows them on screen, and
/// `tool/generate_audio.py` records them. A caption that does not match the
/// clip under it is worse than no caption, and in a phonics app an adult
/// reading along out loud makes that mismatch audible.
class ChefScript {
  const ChefScript({required this.phrases, required this.praise});

  factory ChefScript.fromJson(Map<String, dynamic> json) {
    final phrases = json['phrases'] as Map<String, dynamic>? ?? const {};
    final praise = json['praise'] as List<dynamic>? ?? const [];
    return ChefScript(
      phrases: {
        for (final entry in phrases.entries)
          entry.key: (entry.value as String? ?? '').trim(),
      },
      praise: [
        for (final line in praise)
          if ((line as String? ?? '').trim().isNotEmpty)
            (line as String).trim(),
      ],
    );
  }

  /// No lines at all. The chef then speaks everything with the device voice,
  /// which is what the app did before any of this was recorded.
  static const ChefScript empty = ChefScript(phrases: {}, praise: []);

  /// Keys the app asks for by name. Kept as constants so a typo is a compile
  /// error rather than a silent fall back to the device voice.
  static const String mySoundToday = 'mySoundToday';
  static const String watchMeMake = 'watchMeMake';
  static const String nowYouMake = 'nowYouMake';
  static const String inGoes = 'inGoes';
  static const String and = 'and';
  static const String yourSoupHas = 'yourSoupHas';
  static const String inIt = 'inIt';
  static const String emptyPan = 'emptyPan';

  final Map<String, String> phrases;

  /// Praise lines, in the order they are used. Never a judgement: in the core
  /// game there is nothing to get wrong.
  final List<String> praise;

  bool get isEmpty => phrases.isEmpty && praise.isEmpty;

  /// The line for [key], or an empty string when the script has no such line.
  String phrase(String key) => phrases[key] ?? '';

  /// A praise line, chosen by [seed] so a test can pin one down.
  String praiseFor(int seed) =>
      praise.isEmpty ? '' : praise[seed.abs() % praise.length];
}
