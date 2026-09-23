/// Whether a phoneme can be held on (stretched) or has to be bounced.
///
/// This is the difference between modelling "sssun" and "b-b-banana", and it
/// is the single most important phonics rule in the app: a stop consonant
/// must never be stretched into "suh"-style added vowels.
enum Articulation {
  /// Can be held on: /s/, /m/, /n/, /f/, /l/ and all vowels.
  continuant,

  /// Has to be bounced: /p/, /b/, /t/, /d/, /k/, /g/.
  stop;

  static Articulation fromId(String? id) {
    for (final value in Articulation.values) {
      if (value.name == id) return value;
    }
    // Bouncing a continuant sounds odd; stretching a stop teaches "suh".
    // When in doubt, bounce — it is the safer mistake.
    return Articulation.stop;
  }

  String get id => name;
}
