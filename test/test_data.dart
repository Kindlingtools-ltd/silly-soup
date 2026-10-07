import 'package:silly_soup/models/models.dart';
import 'package:silly_soup/services/services.dart';

/// A tiny hand-built bank, so the rules can be tested without the real one.
PhonemeSound soundS = const PhonemeSound(
  id: 's',
  label: 's',
  grapheme: 's',
  articulation: Articulation.continuant,
  pureSound: 'sss',
  audio: 'phonemes/s.mp3',
  mouthShape: MouthShape.teethNearlyTogether,
  enabledByDefault: true,
);

PhonemeSound soundB = const PhonemeSound(
  id: 'b',
  label: 'b',
  grapheme: 'b',
  articulation: Articulation.stop,
  pureSound: 'b',
  mouthShape: MouthShape.lipsTogether,
  enabledByDefault: true,
);

PhonemeSound soundA = const PhonemeSound(
  id: 'a',
  label: 'a',
  grapheme: 'a',
  articulation: Articulation.continuant,
  pureSound: 'aaa',
  isVowel: true,
);

SoupWord word(
  String text,
  String phoneme, {
  bool hasCluster = false,
  bool hidden = false,
  String? audio,
}) {
  return SoupWord(
    word: text,
    phoneme: phoneme,
    image: 'emoji:🍲',
    audio: audio,
    hasCluster: hasCluster,
    hidden: hidden,
  );
}

List<SoupWord> sWords = [
  word('sun', 's'),
  word('sock', 's'),
  word('seal', 's'),
  word('soup', 's'),
  word('sofa', 's'),
  word('sandwich', 's'),
  word('star', 's', hasCluster: true),
  word('spoon', 's', hasCluster: true),
];

List<SoupWord> bWords = [
  word('banana', 'b'),
  word('bee', 'b'),
  word('bug', 'b'),
  word('ball', 'b'),
  word('bus', 'b'),
  word('bed', 'b'),
];

SoundBank testBank = SoundBank(
  name: 'test',
  sounds: [soundS, soundB, soundA],
  words: [...sWords, ...bWords],
);

/// The chef's fixed lines, small enough to read in a test.
const ChefScript testScript = ChefScript(
  phrases: {
    ChefScript.mySoundToday: 'My sound today is',
    ChefScript.watchMeMake: 'Watch me make my silly soup!',
    ChefScript.nowYouMake: 'Now you make a silly soup!',
    ChefScript.inGoes: 'In goes',
    ChefScript.and: 'and',
    ChefScript.yourSoupHas: 'Your silly soup has',
    ChefScript.inIt: 'in it!',
    ChefScript.emptyPan: 'An empty pan! That is the silliest soup of all.',
  },
  praise: [
    'Ooh, what a silly soup!',
    'What a wonderful wobbly recipe!',
    'That is the silliest soup I have ever seen!',
  ],
);

/// A chef whose every clip is present, so a test can check which recordings a
/// line is built from rather than which words it falls back to.
ChefVoice fullyRecordedVoice({
  ChefScript script = testScript,
  List<PhonemeSound> sounds = const [],
  List<SoupWord> words = const [],
}) {
  return ChefVoice(
    script: script,
    catalogue: ClipCatalogue({
      for (final key in script.phrases.keys) ChefVoice.phraseClip(key),
      for (var i = 0; i < script.praise.length; i++) ChefVoice.praiseClip(i),
      for (final sound in sounds) ...[
        if (sound.audioAssetPath != null) sound.audioAssetPath!,
        ChefVoice.actionClip(sound),
      ],
      for (final word in words) ...[
        if (word.audioAssetPath != null) word.audioAssetPath!,
        ChefVoice.emphasisClip(word),
      ],
      SoupSong.audioAssetPath,
    }),
  );
}
