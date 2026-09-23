import 'dart:convert';

import '../models/models.dart';

/// The result of reading a sound pack file.
class SoundPackImport {
  const SoundPackImport(this.bank, this.validation);

  /// Null when the pack could not be read. Warnings still yield a bank.
  final SoundBank? bank;
  final ValidationResult validation;

  bool get isValid => bank != null && validation.isValid;
}

/// Reads and writes the single-file sound pack a teacher moves between
/// classroom devices.
///
/// Deliberately plain JSON: a pack is something a school can open, read and
/// keep, not an opaque blob.
class SoundPackCodec {
  const SoundPackCodec._();

  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');

  /// Serialise a bank for export.
  static String encode(SoundBank bank, {String? name}) {
    final payload = bank.toJson()
      ..['schemaVersion'] = SoundBank.currentSchemaVersion
      ..['name'] = name ?? bank.name
      ..['exportedAt'] = DateTime.now().toUtc().toIso8601String();
    return _encoder.convert(payload);
  }

  /// Read a pack, validating before anything is handed to the app.
  ///
  /// A pack with warnings still imports — the adult is told what is thin and
  /// decides for themselves. A pack with errors does not import at all.
  static SoundPackImport decode(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      return const SoundPackImport(
        null,
        ValidationResult([
          ValidationIssue.error('That file is not readable as a sound pack.'),
        ]),
      );
    }

    final validation = SoundBank.validate(decoded);
    if (!validation.isValid) return SoundPackImport(null, validation);

    return SoundPackImport(
      SoundBank.fromJson(decoded as Map<String, dynamic>),
      validation,
    );
  }
}
