/// The stirring song.
///
/// The tune is "Pop Goes the Weasel", which is public domain. The words are
/// original to this app — the traditional soup-song words sung in many
/// settings are not reproduced here. An adult who sings a different version
/// can record their own in the adult area, and their recording replaces this.
class SoupSong {
  const SoupSong._();

  static const String title = 'The Silly Soup Song';

  /// Sung to the tune of "Pop Goes the Weasel".
  static const List<String> lyrics = [
    'Stir the pot and stir it round,',
    'Silly soup is bubbling.',
    'In go all the sounds we found —',
    'Whoosh! goes the soup!',
  ];

  /// The bundled recording. Missing until someone records it, at which point
  /// the audio checklist stops asking for it.
  static const String audioAssetPath = 'assets/audio/song/silly_soup_song.mp3';

  /// What the fallback voice says when there is no recording yet.
  static String get spokenLyrics => lyrics.join(' ');
}
