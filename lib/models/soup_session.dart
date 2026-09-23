import 'phoneme_sound.dart';
import 'soup_word.dart';

/// Where a soup has got to.
enum SoupStage {
  /// The chef says the sound and does the action.
  meetTheSound,

  /// The chef makes a soup first, so the child has seen it done.
  chefModelling,

  /// The child's turn. This is the part of the activity that matters.
  childsTurn,

  /// Silly tasting, then "Make another soup?".
  tasting,
}

/// One child's go at making a soup.
///
/// Immutable so the game rules stay testable without a widget tree: every
/// change returns a new session. There is deliberately no score, no timer and
/// no notion of a wrong move in the core game — the child cannot lose.
class SoupSession {
  const SoupSession({
    required this.sound,
    required this.pantry,
    this.chefSoup = const [],
    this.pot = const [],
    this.stage = SoupStage.meetTheSound,
  });
  final PhonemeSound sound;

  /// Items still on the shelf.
  final List<SoupWord> pantry;

  /// The three items the chef put in when modelling.
  final List<SoupWord> chefSoup;

  /// What the child has put in, in the order they chose.
  final List<SoupWord> pot;

  final SoupStage stage;

  bool get isPotEmpty => pot.isEmpty;

  bool get isPantryEmpty => pantry.isEmpty;

  /// Move an item from the shelf into the pot.
  ///
  /// An item the child has already used is not on the shelf any more, so a
  /// pot can never hold the same picture twice — the same as the real
  /// activity, where there is one banana and it is now in the pan.
  SoupSession addToPot(SoupWord word) {
    if (!pantry.contains(word)) return this;
    return copyWith(
      pantry: pantry.where((item) => item != word).toList(),
      pot: [...pot, word],
    );
  }

  /// Put an item back on the shelf. Used by the odd-one-out extension, where
  /// the item floats out again, and by an adult undoing a mis-tap.
  SoupSession removeFromPot(SoupWord word) {
    if (!pot.contains(word)) return this;
    return copyWith(
      pantry: [...pantry, word],
      pot: pot.where((item) => item != word).toList(),
    );
  }

  SoupSession withStage(SoupStage next) => copyWith(stage: next);

  SoupSession copyWith({
    PhonemeSound? sound,
    List<SoupWord>? pantry,
    List<SoupWord>? chefSoup,
    List<SoupWord>? pot,
    SoupStage? stage,
  }) {
    return SoupSession(
      sound: sound ?? this.sound,
      pantry: pantry ?? this.pantry,
      chefSoup: chefSoup ?? this.chefSoup,
      pot: pot ?? this.pot,
      stage: stage ?? this.stage,
    );
  }
}
