/// How the mouth looks while a sound is being made.
///
/// Drives the "Watch my mouth" animation, so every value must be something
/// a four-year-old can actually see and copy.
enum MouthShape {
  /// /m/, /b/, /p/ — lips pressed together, then released.
  lipsTogether,

  /// /f/, /v/ — top teeth resting on the bottom lip.
  teethOnLip,

  /// /t/, /d/, /n/, /l/ — tongue tip behind the top teeth.
  tongueBehindTeeth,

  /// /s/, /z/ — teeth nearly closed, air hissing through.
  teethNearlyTogether,

  /// /a/ — mouth open wide, tongue flat.
  openWide,

  /// /i/, /e/ — mouth open a little, corners pulled back.
  openSmall,

  /// /o/, /oo/, /w/ — lips pushed forward into a circle.
  roundedLips;

  /// Parse the `mouthShape` field of a sound, falling back to [openSmall]
  /// so an unknown value from an imported pack can never crash the app.
  static MouthShape fromId(String? id) {
    for (final shape in MouthShape.values) {
      if (shape.name == id) return shape;
    }
    return MouthShape.openSmall;
  }

  String get id => name;

  /// True when the shape closes the mouth completely at the start of the sound.
  bool get startsClosed => this == MouthShape.lipsTogether;
}
