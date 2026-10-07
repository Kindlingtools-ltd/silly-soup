import '../models/models.dart';
import 'clip_catalogue.dart';
import 'recital_service.dart';

/// One thing the chef says: the recordings that say it, and the words to fall
/// back on.
///
/// [clips] and [text] always mean the same thing. That is the whole contract:
/// whichever way the line comes out, the child hears the same sentence, and
/// the caption on screen is still true.
class Utterance {
  const Utterance(this.clips, this.text);

  /// Asset paths, played back to back. Empty when there is nothing recorded.
  final List<String> clips;

  /// The same line as words, for the device voice.
  final String text;

  bool get isEmpty => clips.isEmpty && text.isEmpty;

  @override
  String toString() => 'Utterance(${clips.length} clips, "$text")';
}

/// Turns what the chef wants to say into recordings of the chef saying it.
///
/// Before this, one word in the app was recorded and every sentence around it
/// was read out by whatever voice the device happened to have — which on a
/// school Chromebook is a flat American one that says "ess" for /s/ and reads
/// "sssun" letter by letter. The clips exist for all of it now, so the chef
/// builds a sentence out of them: "In goes" + "a sssun" + "a sssock".
///
/// Built from fragments rather than whole sentences because the child chooses
/// the ingredients — there is no way to record every list a child might make.
/// The fragments are deliberate rather than seamless, which is also how an
/// adult recites a list of ingredients to a four-year-old.
///
/// Everything here is a pure function of the bank, the script and the
/// catalogue, so what the chef would say is testable without a speaker.
class ChefVoice {
  const ChefVoice({
    this.script = ChefScript.empty,
    this.catalogue = ClipCatalogue.empty,
  });

  final ChefScript script;
  final ClipCatalogue catalogue;

  static const String _audioRoot = 'assets/audio';

  /// Where the chef's recital form of a word lives: "a sssun", "a b-b-banana".
  static String emphasisClip(SoupWord word) =>
      '$_audioRoot/emphasis/${word.word}.mp3';

  static String phraseClip(String key) => '$_audioRoot/phrases/$key.mp3';

  static String praiseClip(int index) => '$_audioRoot/praise/$index.mp3';

  static String actionClip(PhonemeSound sound) =>
      '$_audioRoot/actions/${sound.id}.mp3';

  /// Keep the clips only if every one of them is there. A sentence that runs
  /// out of recordings half way through is worse than one spoken throughout.
  Utterance _utterance(List<String> clips, String text) =>
      Utterance(catalogue.hasAll(clips) ? clips : const [], text);

  /// The sound on its own: "sss", "b-b-b".
  Utterance pureSound(PhonemeSound sound) {
    final clip = sound.audioAssetPath;
    return _utterance(
      clip == null ? const [] : [clip],
      RecitalService.pureSound(sound),
    );
  }

  /// A single word, said plainly. Used by the adult area's preview.
  Utterance word(SoupWord word) {
    final clip = word.audioAssetPath;
    return _utterance(clip == null ? const [] : [clip], word.word);
  }

  /// What the chef does with the sound: "Bounce your hands like a ball."
  Utterance action(PhonemeSound sound) =>
      _utterance([actionClip(sound)], sound.action);

  /// One of the chef's fixed lines.
  Utterance phrase(String key) =>
      _utterance([phraseClip(key)], script.phrase(key));

  /// Praise, chosen by [seed]. Never a judgement.
  Utterance praise(int seed) {
    if (script.praise.isEmpty) return const Utterance([], '');
    final index = seed.abs() % script.praise.length;
    return _utterance([praiseClip(index)], script.praise[index]);
  }

  /// A single item going in: "In goes a sssun!"
  Utterance commentateOnItem(SoupWord word, PhonemeSound sound) => _utterance([
    phraseClip(ChefScript.inGoes),
    emphasisClip(word),
  ], RecitalService.commentateOnItem(word, sound));

  /// The growing list, recited after every item: "In goes a sssun… a sssock…"
  Utterance reciteList(List<SoupWord> pot, PhonemeSound sound) {
    if (pot.isEmpty) return const Utterance([], '');
    return _utterance([
      phraseClip(ChefScript.inGoes),
      ...pot.map(emphasisClip),
    ], RecitalService.reciteList(pot, sound));
  }

  /// The read-back at tasting time: "Your silly soup has a sssun, a sssock and
  /// a sssausage in it!"
  Utterance reciteFinishedSoup(List<SoupWord> pot, PhonemeSound sound) {
    final text = RecitalService.reciteFinishedSoup(pot, sound);
    if (pot.isEmpty) {
      return _utterance([phraseClip(ChefScript.emptyPan)], text);
    }
    final clips = [phraseClip(ChefScript.yourSoupHas)];
    for (var i = 0; i < pot.length; i++) {
      // "and" goes in front of the last one, exactly where the caption has it.
      if (i == pot.length - 1 && pot.length > 1) {
        clips.add(phraseClip(ChefScript.and));
      }
      clips.add(emphasisClip(pot[i]));
    }
    clips.add(phraseClip(ChefScript.inIt));
    return _utterance(clips, text);
  }

  /// The stirring song.
  Utterance song() =>
      _utterance([SoupSong.audioAssetPath], SoupSong.spokenLyrics);
}
