import '../models/models.dart';

/// Turns words into the things the chef says out loud.
///
/// All pure functions: what the chef says is a phonics decision, not a UI
/// one, so it is decided here and tested here.
class RecitalService {
  const RecitalService._();

  /// How many times a continuant is repeated when written out: "sssun".
  static const int _stretchRepeats = 3;

  /// The sound on its own, the way an adult should model it.
  ///
  /// Continuants are held on ("sss"); stops are bounced ("b-b-b"). Neither
  /// ever gains an "uh" — that is the mistake this whole app exists to avoid.
  static String pureSound(PhonemeSound sound) => sound.spokenPureSound;

  /// A word with its first sound emphasised.
  ///
  /// * continuant: `sun` -> `sssun`, `snake` -> `sssnake`
  /// * stop:       `banana` -> `b-b-banana`
  ///
  /// The grapheme comes from the word rather than the sound, so `cat` and
  /// `kite` both sit under /k/ and still come out as "c-c-cat" and "k-k-kite".
  static String emphasise(SoupWord word, PhonemeSound sound) {
    if (word.word.isEmpty) return '';
    final grapheme = word.emphasisGrapheme;
    if (grapheme.isEmpty) return word.word;

    if (sound.isContinuant) {
      final rest = word.word.length >= grapheme.length
          ? word.word.substring(grapheme.length)
          : '';
      return '${grapheme * _stretchRepeats}$rest';
    }
    return '$grapheme-$grapheme-${word.word}';
  }

  /// "a" or "an", chosen by the sound the word starts with rather than by its
  /// spelling — the whole app works in sounds.
  static String article(SoupWord word, PhonemeSound sound) =>
      sound.isVowel ? 'an' : 'a';

  /// The growing list, recited after every item goes in:
  /// "In goes a sssun… a sssock… a sssausage…"
  static String reciteList(List<SoupWord> pot, PhonemeSound sound) {
    if (pot.isEmpty) return '';
    final parts = pot
        .map((word) => '${article(word, sound)} ${emphasise(word, sound)}')
        .toList();
    return 'In goes ${parts.join('… ')}…';
  }

  /// The chef's read-back of a finished soup, used at tasting time.
  static String reciteFinishedSoup(List<SoupWord> pot, PhonemeSound sound) {
    if (pot.isEmpty) return 'An empty pan! That is the silliest soup of all.';
    final parts = pot
        .map((word) => '${article(word, sound)} ${emphasise(word, sound)}')
        .toList();
    if (parts.length == 1) {
      return 'Your silly soup has ${parts.single} in it!';
    }
    final last = parts.removeLast();
    return 'Your silly soup has ${parts.join(', ')} and $last in it!';
  }

  /// Praise. Never a judgement — in the core game there is nothing to get
  /// wrong, so these only ever celebrate the child's choice.
  static const List<String> praiseLines = [
    'Ooh, what a silly soup!',
    'What a wonderful wobbly recipe!',
    'That is the silliest soup I have ever seen!',
    'Mmm, what a clever cook you are!',
    'Look at all those lovely sounds!',
    'What a splendid, sloppy soup!',
  ];

  /// A praise line, chosen by [seed] so a test can pin one down.
  static String praise(int seed) =>
      praiseLines[seed.abs() % praiseLines.length];

  /// The chef's commentary as a single item goes in.
  static String commentateOnItem(SoupWord word, PhonemeSound sound) =>
      'In goes ${article(word, sound)} ${emphasise(word, sound)}!';
}
