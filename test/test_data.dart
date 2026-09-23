import 'package:silly_soup/models/models.dart';

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
