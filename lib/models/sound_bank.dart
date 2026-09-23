import 'package:collection/collection.dart';

import 'phoneme_sound.dart';
import 'soup_word.dart';
import 'validation_issue.dart';

/// Everything the chef can cook with: the sounds, and the words for each.
///
/// The same shape is used for the built-in bank in `assets/data`, for an
/// adult's custom content, and for an exported sound pack file, so a teacher
/// can move a pack between classroom devices without any conversion.
class SoundBank {
  const SoundBank({
    this.schemaVersion = currentSchemaVersion,
    this.name = '',
    this.sounds = const [],
    this.words = const [],
  });

  factory SoundBank.fromJson(Map<String, dynamic> json) {
    return SoundBank(
      schemaVersion: json['schemaVersion'] as int? ?? currentSchemaVersion,
      name: json['name'] as String? ?? '',
      sounds: (json['sounds'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(PhonemeSound.fromJson)
          .toList(),
      words: (json['words'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(SoupWord.fromJson)
          .toList(),
    );
  }

  /// Bumped when the on-disk shape changes. Import refuses anything newer.
  static const int currentSchemaVersion = 1;

  /// A pantry with fewer than this many words is too thin to play with.
  static const int minWordsPerSound = 6;

  final int schemaVersion;
  final String name;
  final List<PhonemeSound> sounds;
  final List<SoupWord> words;

  static const SoundBank empty = SoundBank();

  /// Sounds an adult has not hidden, in bank order.
  List<PhonemeSound> get visibleSounds =>
      sounds.where((sound) => !sound.hidden).toList();

  PhonemeSound? soundById(String id) =>
      sounds.firstWhereOrNull((sound) => sound.id == id);

  /// Words for one sound, hidden ones removed.
  List<SoupWord> wordsFor(String phonemeId) =>
      words.where((word) => word.phoneme == phonemeId && !word.hidden).toList();

  /// Words that do *not* belong to [phonemeId] — the pool the odd-one-out
  /// extension draws its distractors from.
  List<SoupWord> wordsNotFor(String phonemeId) =>
      words.where((word) => word.phoneme != phonemeId && !word.hidden).toList();

  /// Sounds that do not have enough words to fill a pantry.
  List<PhonemeSound> get underfilledSounds => visibleSounds
      .where((sound) => wordsFor(sound.id).length < minWordsPerSound)
      .toList();

  /// Merge an overlay on top of this bank.
  ///
  /// Overlay entries win on id, so an adult can edit or hide a built-in sound
  /// or word without the built-in data ever being deleted. New entries are
  /// appended in overlay order.
  SoundBank mergedWith(SoundBank overlay) {
    final mergedSounds = <PhonemeSound>[];
    for (final sound in sounds) {
      mergedSounds.add(
        overlay.sounds.firstWhereOrNull((other) => other.id == sound.id) ??
            sound,
      );
    }
    for (final sound in overlay.sounds) {
      if (!mergedSounds.any((existing) => existing.id == sound.id)) {
        mergedSounds.add(sound);
      }
    }

    final mergedWords = <SoupWord>[];
    for (final word in words) {
      mergedWords.add(
        overlay.words.firstWhereOrNull((other) => other.id == word.id) ?? word,
      );
    }
    for (final word in overlay.words) {
      if (!mergedWords.any((existing) => existing.id == word.id)) {
        mergedWords.add(word);
      }
    }

    return SoundBank(name: name, sounds: mergedSounds, words: mergedWords);
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'name': name,
      'sounds': sounds.map((sound) => sound.toJson()).toList(),
      'words': words.map((word) => word.toJson()).toList(),
    };
  }

  /// Check a decoded sound pack before it is allowed anywhere near a child.
  ///
  /// Errors mean "do not import". Warnings mean "import, but tell the adult":
  /// a thin pantry is a judgement call a teacher may well want to make.
  static ValidationResult validate(Object? decoded) {
    final issues = <ValidationIssue>[];

    if (decoded is! Map<String, dynamic>) {
      return const ValidationResult([
        ValidationIssue.error('This file is not a Silly Soup sound pack.'),
      ]);
    }

    final version = decoded['schemaVersion'];
    if (version is! int) {
      issues.add(
        const ValidationIssue.error(
          'This file is missing its schemaVersion, so it is not a sound pack.',
        ),
      );
    } else if (version > currentSchemaVersion) {
      issues.add(
        ValidationIssue.error(
          'This pack was made with a newer version of Silly Soup '
          '(pack $version, app $currentSchemaVersion). Update the app first.',
        ),
      );
    }

    final rawSounds = decoded['sounds'];
    final rawWords = decoded['words'];
    if (rawSounds is! List) {
      issues.add(const ValidationIssue.error('This pack has no sounds list.'));
    }
    if (rawWords is! List) {
      issues.add(const ValidationIssue.error('This pack has no words list.'));
    }
    if (issues.any((issue) => issue.isError)) {
      return ValidationResult(issues);
    }

    final soundIds = <String>{};
    for (final entry in (rawSounds as List)) {
      if (entry is! Map<String, dynamic>) {
        issues.add(const ValidationIssue.error('A sound entry is not valid.'));
        continue;
      }
      final id = (entry['id'] as String? ?? '').trim();
      if (id.isEmpty) {
        issues.add(const ValidationIssue.error('A sound is missing its id.'));
        continue;
      }
      if (!soundIds.add(id)) {
        issues.add(
          ValidationIssue.error(
            'The sound "$id" appears more than once.',
            subject: id,
          ),
        );
      }
      if ((entry['pureSound'] as String? ?? '').trim().isEmpty) {
        issues.add(
          ValidationIssue.warning(
            'The sound "$id" has no pure sound written out, so the chef will '
            'use its id instead.',
            subject: id,
          ),
        );
      }
    }

    final wordIds = <String>{};
    final wordsPerSound = <String, int>{};
    for (final entry in (rawWords as List)) {
      if (entry is! Map<String, dynamic>) {
        issues.add(const ValidationIssue.error('A word entry is not valid.'));
        continue;
      }
      final word = (entry['word'] as String? ?? '').trim();
      final phoneme = (entry['phoneme'] as String? ?? '').trim();
      final image = (entry['image'] as String? ?? '').trim();

      if (word.isEmpty) {
        issues.add(const ValidationIssue.error('A word entry has no word.'));
        continue;
      }
      if (phoneme.isEmpty) {
        issues.add(
          ValidationIssue.error(
            '"$word" does not say which sound it belongs to.',
            subject: word,
          ),
        );
        continue;
      }
      if (!soundIds.contains(phoneme)) {
        issues.add(
          ValidationIssue.error(
            '"$word" belongs to the sound "$phoneme", which this pack does not '
            'contain.',
            subject: word,
          ),
        );
        continue;
      }
      // Every word needs a picture: the pantry shelf is pictures only, and a
      // blank tile is not something a four-year-old can choose.
      if (image.isEmpty) {
        issues.add(
          ValidationIssue.error(
            '"$word" has no picture. Every word needs one.',
            subject: word,
          ),
        );
      }
      if (!wordIds.add('$phoneme:$word')) {
        issues.add(
          ValidationIssue.error(
            '"$word" appears more than once under the sound "$phoneme".',
            subject: word,
          ),
        );
        continue;
      }
      if (entry['hidden'] as bool? ?? false) continue;
      wordsPerSound[phoneme] = (wordsPerSound[phoneme] ?? 0) + 1;
    }

    for (final id in soundIds) {
      final count = wordsPerSound[id] ?? 0;
      if (count < minWordsPerSound) {
        issues.add(
          ValidationIssue.warning(
            'The sound "$id" has only $count '
            '${count == 1 ? 'word' : 'words'} — too few to fill the pantry. '
            'Add at least ${minWordsPerSound - count} more.',
            subject: id,
          ),
        );
      }
    }

    return ValidationResult(issues);
  }
}
