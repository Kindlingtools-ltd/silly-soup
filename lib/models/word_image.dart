/// A picture for a pantry item.
///
/// Stored as a single prefixed string in the word bank JSON so a sound pack
/// stays one flat, human-editable file:
///
/// * `emoji:🍌`      — placeholder art, easy to swap for real illustrations
/// * `asset:items/banana.svg` — artwork bundled with the app
/// * `custom:<id>`   — an adult's photo or upload, held in local storage
enum WordImageKind { emoji, asset, custom }

class WordImage {
  const WordImage(this.kind, this.value);

  /// Parse the `image` field. An unprefixed value is treated as an emoji,
  /// which is what a teacher typing straight into the JSON will expect.
  factory WordImage.parse(String raw) {
    final separator = raw.indexOf(':');
    if (separator > 0) {
      final prefix = raw.substring(0, separator);
      final value = raw.substring(separator + 1);
      for (final kind in WordImageKind.values) {
        if (kind.name == prefix) return WordImage(kind, value);
      }
    }
    return WordImage(WordImageKind.emoji, raw);
  }
  final WordImageKind kind;
  final String value;

  /// The full asset path for [WordImageKind.asset] images.
  String get assetPath => 'assets/images/$value';

  String encode() => '${kind.name}:$value';

  @override
  String toString() => encode();

  @override
  bool operator ==(Object other) =>
      other is WordImage && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}
