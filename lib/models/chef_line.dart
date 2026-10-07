/// Something the chef says: the words, and the recordings that say them.
///
/// The app used to pass plain strings to the voice, which meant everything
/// beyond the nine pure sounds came out of whatever text-to-speech the device
/// happened to ship — usually American, and the thing a child heard most.
/// A [ChefLine] carries both, so a line can be played as a recording and
/// still have something to fall back on and something to put on screen.
///
/// [clips] is played in order. A line assembled from several clips — "In
/// goes" followed by one clip per ingredient — is how the growing list is
/// said without needing a recording of every possible soup.
class ChefLine {
  const ChefLine({required this.text, this.clips = const []});

  /// Spoken by the device voice when the recordings are not all there, and
  /// shown on screen either way.
  final String text;

  /// Full asset paths, played one after another. Empty means there is no
  /// recording for this line and it can only be spoken.
  final List<String> clips;

  /// Where the recordings live, relative to nothing — these are the paths
  /// `tool/build_audio.py` writes and lists in `assets/audio/manifest.json`.
  static const String root = 'assets/audio';

  static String line(String key) => '$root/lines/$key.mp3';

  static String action(String soundId) => '$root/actions/$soundId.mp3';

  /// "In goes a sssun!" — one recording, with the first sound already held
  /// or bounced in the waveform.
  static String commentary(String word) => '$root/commentary/$word.mp3';

  /// "a sssun…" — an item as it appears part-way through a recited list.
  static String listItem(String word) => '$root/list/$word.mp3';

  @override
  String toString() => 'ChefLine($text, ${clips.length} clips)';
}
