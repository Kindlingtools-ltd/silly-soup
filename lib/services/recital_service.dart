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

/// The chef's script, as lines that can be played rather than only spoken.
///
/// Every one of these carries both the recordings and the words. The words
/// are what goes on screen, and what the device voice says on a device where
/// the recordings have not been built — so the app degrades to exactly its
/// old behaviour rather than to silence.
extension ChefScript on RecitalService {
  static ChefLine _fixed(String key, String text) =>
      ChefLine(text: text, clips: [ChefLine.line(key)]);

  /// "Watch me make my silly soup!"
  static ChefLine get watchMe =>
      _fixed('watch_me', 'Watch me make my silly soup!');

  /// "Now you make a silly soup!"
  static ChefLine get nowYou => _fixed('now_you', 'Now you make a silly soup!');

  /// The sound on its own, and the action that goes with it.
  static ChefLine soundAction(PhonemeSound sound) => ChefLine(
    text: sound.action,
    clips: sound.action.isEmpty ? const [] : [ChefLine.action(sound.id)],
  );

  /// "My sound today is sss." — the words, then the recorded sound itself.
  static ChefLine soundOfTheDay(PhonemeSound sound) {
    final clip = sound.audioAssetPath;
    return ChefLine(
      text: 'My sound today is ${RecitalService.pureSound(sound)}.',
      clips: clip == null ? const [] : [ChefLine.line('my_sound_today'), clip],
    );
  }

  /// "In goes a sssun!" — one recording per word, with the first sound
  /// already held or bounced in the waveform.
  static ChefLine commentateOnItem(SoupWord word, PhonemeSound sound) =>
      ChefLine(
        text: RecitalService.commentateOnItem(word, sound),
        clips: [ChefLine.commentary(word.word)],
      );

  /// The growing list: "In goes" and then one clip per ingredient.
  ///
  /// There is no recording of a whole soup, because a soup is whatever the
  /// child decides to put in it. Recording each item as it sounds part-way
  /// through a list — "a sssun…", trailing rather than finished — means any
  /// soup can be recited by playing them in a row.
  static ChefLine reciteList(List<SoupWord> pot, PhonemeSound sound) {
    if (pot.isEmpty) return const ChefLine(text: '');
    return ChefLine(
      text: RecitalService.reciteList(pot, sound),
      clips: [
        ChefLine.line('in_goes'),
        for (final word in pot) ChefLine.listItem(word.word),
      ],
    );
  }

  /// The read-back at tasting time: "Your silly soup has a sssun, a sssock
  /// and a sssausage in it!"
  static ChefLine reciteFinishedSoup(List<SoupWord> pot, PhonemeSound sound) {
    final text = RecitalService.reciteFinishedSoup(pot, sound);
    if (pot.isEmpty) {
      return ChefLine(text: text, clips: [ChefLine.line('empty_pan')]);
    }
    return ChefLine(
      text: text,
      clips: [
        ChefLine.line('soup_has'),
        for (var i = 0; i < pot.length; i++) ...[
          if (i > 0 && i == pot.length - 1) ChefLine.line('and'),
          ChefLine.listItem(pot[i].word),
        ],
        ChefLine.line('in_it'),
      ],
    );
  }

  /// Praise, chosen by [seed] so a test can pin one down.
  static ChefLine praise(int seed) {
    final index = seed.abs() % RecitalService.praiseLines.length;
    return ChefLine(
      text: RecitalService.praiseLines[index],
      clips: [ChefLine.line('praise_$index')],
    );
  }
}
