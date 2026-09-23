import 'dart:math';

import '../models/models.dart';

/// The rules of the game, with no UI attached.
///
/// Everything here is pure: given the same bank, settings and random seed it
/// always builds the same pantry, which is what makes the phonics guarantees
/// testable rather than hopeful.
class SoupService {
  const SoupService._();

  /// How many items the chef models with. Three is what the DfE activity
  /// describes: banana, bumble bee, bug.
  static const int chefSoupSize = 3;

  /// Build the pantry shelf for a sound.
  ///
  /// In the core game every item on the shelf starts with [sound], full stop.
  /// [distractorCount] is only ever non-zero for the odd-one-out extension,
  /// and any distractor that shares the target sound is dropped rather than
  /// shown, because a "wrong" item that is actually right would be unfair.
  ///
  /// Items are never duplicated: the shelf is a set of distinct words.
  static List<SoupWord> buildPantry({
    required PhonemeSound sound,
    required List<SoupWord> candidates,
    required int size,
    List<SoupWord> distractors = const [],
    int distractorCount = 0,
    Random? random,
    bool allowClusters = true,
  }) {
    final rng = random ?? Random();

    final pool = _distinct(
      candidates.where(
        (word) =>
            word.phoneme == sound.id &&
            !word.hidden &&
            (allowClusters || !word.hasCluster),
      ),
    );

    final wantedDistractors = distractorCount.clamp(0, size);
    final distractorPool = _distinct(
      distractors.where((word) => word.phoneme != sound.id && !word.hidden),
    );

    final chosenDistractors = _take(distractorPool, wantedDistractors, rng);
    final chosenTargets = _take(
      pool,
      max(0, size - chosenDistractors.length),
      rng,
    );

    final shelf = [...chosenTargets, ...chosenDistractors]..shuffle(rng);
    return shelf;
  }

  /// The three items the chef drops in while modelling.
  ///
  /// Prefers the simplest, most familiar words and avoids consonant clusters,
  /// because this is the moment the child hears the sound done properly.
  static List<SoupWord> buildChefSoup({
    required PhonemeSound sound,
    required List<SoupWord> candidates,
    int size = chefSoupSize,
    Random? random,
  }) {
    final rng = random ?? Random();
    final pool =
        _distinct(
          candidates.where((word) => word.phoneme == sound.id && !word.hidden),
        )..sort((a, b) {
          final cluster = (a.hasCluster ? 1 : 0).compareTo(
            b.hasCluster ? 1 : 0,
          );
          if (cluster != 0) return cluster;
          return a.difficulty.compareTo(b.difficulty);
        });

    // Draw from the easiest half so the modelled soup is always clear, but
    // still varies between goes.
    final headroom = min(
      pool.length,
      max(size, (size * 2).clamp(0, pool.length)),
    );
    final head = pool.take(headroom).toList()..shuffle(rng);
    return head.take(min(size, head.length)).toList();
  }

  /// The sounds offered in the picker: enabled, present in the bank, not
  /// hidden, and in the order the adult set.
  static List<PhonemeSound> availableSounds({
    required SoundBank bank,
    required AppSettings settings,
  }) {
    final byId = {for (final sound in bank.visibleSounds) sound.id: sound};
    final ordered = <PhonemeSound>[];

    for (final id in settings.soundOrder) {
      final sound = byId.remove(id);
      if (sound != null && settings.isSoundEnabled(id)) ordered.add(sound);
    }
    // Sounds the adult added but never ordered still show up, at the end.
    for (final sound in byId.values) {
      if (settings.isSoundEnabled(sound.id)) ordered.add(sound);
    }
    return ordered;
  }

  static List<SoupWord> _distinct(Iterable<SoupWord> words) {
    final seen = <String>{};
    final result = <SoupWord>[];
    for (final word in words) {
      if (seen.add(word.id)) result.add(word);
    }
    return result;
  }

  static List<SoupWord> _take(List<SoupWord> pool, int count, Random rng) {
    if (count <= 0 || pool.isEmpty) return [];
    final copy = [...pool]..shuffle(rng);
    return copy.take(min(count, copy.length)).toList();
  }
}
