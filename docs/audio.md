# The chef's voice

Audio is the whole app. This is what it is built from, how the voice was
chosen, and how a change to any of it is checked.

## What was wrong

The app asked the speech engine to pronounce phonics notation and trusted
whatever came back. Reading the old clips back through a transcriber:

| asked for    | came back as        |
| ------------ | ------------------- |
| `sss`        | "S S S"             |
| `sssun`      | "Son"               |
| `sssock`     | "S S O C K"         |
| `aaapple`    | "R R Apple"         |
| `b-b-banana` | **"Buh buh banana"** |
| `t, t, t`    | "T T T" (tee tee tee) |

A speech engine reads text. `sss` is a spelling, so it gets the letter name;
`b-b-` gets the added vowel. "Buh" for /b/ is the one thing Letters and Sounds
Phase One tells you never to model, so every core utterance in a phonics app
was teaching the opposite of what the app exists to teach.

No voice setting fixes that. The fault is in asking a reader of text for a
sound.

Two things made it worse. The nine pure sounds were not shipped at all, so the
most important audio in the app came from the device's own text-to-speech. And
so did nearly everything else — the commentary after every ingredient, the
growing recital, the praise, the chef's asides. On the web that is the Web
Speech API, whose default voice is whatever the browser ships and is usually
American. Recorded clips existed for 78 words and were barely reachable.

## Choosing the voice

The speech API lists 28 voices. Every one of them is described as
`"language": "multilingual"` and none of them names an accent, so "use a
British voice" cannot be settled from the catalogue. It was measured instead,
from the waveform, on two markers that separate Received Pronunciation from
General American:

- **Rhoticity.** In *car*, *father*, *parked* the /r/ is pronounced in GA and
  dropped in RP. A pronounced /r/ pulls the third formant down sharply across
  the end of the word; a dropped one leaves it flat. Measured as the fall in
  F3 from the vowel to the tail of the word, so it is self-normalising per
  voice.
- **The TRAP–BATH split.** *bath*, *last*, *dance* take /ɑː/ in RP (F2 around
  1100 Hz) and /æ/ in GA (F2 around 1700–2000 Hz).

All 28 voices were synthesised saying "Father parked the car." and "The last
dance in the bath.", located in the audio by transcript word timings, and
measured. The range was real — the F3 fall ran from −318 Hz (firmly
non-rhotic) to +518 Hz (firmly rhotic) — so the markers discriminate rather
than measuring noise.

Five voices came out British on the rhoticity marker and four on the vowel.
The three that agreed on both were re-measured across repeats, and then
against the words the app actually ships, which contain their own shibboleths:
*banana* and *tomato* take /ɑː/ in RP, and *star*, *torch*, *door*, *bear*,
*turtle* and *dinosaur* all end in an /r/ that RP drops.

| voice | F3 fall in the /r/ slot | F2 of the PALM vowel | words read back correctly |
| ----- | ----------------------: | -------------------: | ------------------------: |
| eve   |                  −87 Hz |              1370 Hz |                     15/15 |
| rigel |                  −65 Hz |              1378 Hz |                     15/15 |
| leo   |                   −8 Hz |              1361 Hz |                     15/15 |

All three are non-rhotic, and all three say "ban-**ah**-na" and
"tom-**ah**-to". **`eve`** is what ships: it is the most consistently
non-rhotic of the three across repeats, it is the slowest (2.59 words per
second against 2.82 and 3.04), which matters for three- to five-year-olds, and
at about 190 Hz it sits where an early-years practitioner's voice sits — the
voice children are used to hearing model a sound.

So the accent was never the problem, and saying so is part of the answer: the
old clips were already British. What made them unusable was the notation.

Three further things were established and are worth not rediscovering:

- **Style direction does not work.** Prefixing a line with `[warmly, slowly]`
  or `(warm, gentle)` gets it *read aloud* — the clip says "Warm, gentle,
  unhurried. What a silly soup." Extra body fields (`speed`, `instructions`,
  `style`) are accepted and ignored. The only levers are the voice, the
  language and the punctuation.
- **The endpoint is `POST /v1/tts`**, taking `{text, voice_id, language}`.
  `/v1/audio/speech` returns 403 for this account, and `/v1/realtime` is a
  WebSocket, which the Agent IAP proxy cannot carry.
- **`/v1/stt` exists**, returns word-level timings, and is what makes the
  build and the audit possible at all.

## How the clips are made

`tool/build_audio.py` never asks for a pure sound. It asks for ordinary words
and ordinary sentences, and then edits the waveform.

For each sound it takes a carrier word — /s/ from "sun", /b/ from "ball" —
finds where that first phoneme ends, and either **holds it on** or **bounces
it**:

- A **fricative** ends where the voice switches on. The held /s/ is built by
  tiling the hiss from random offsets, because a similarity search would
  impose a pitch on noise and make it buzz.
- A **nasal** is voiced, so voicing cannot mark its end; the murmur is quiet
  and bass-heavy and the vowel after it is neither. It is held on by repeating
  a whole number of pitch periods, so the loop joins are inaudible.
- A **vowel** is the first loud, periodic run of the word.
- A **stop** is a burst, and is never held — holding one is exactly what makes
  "buh". It is cut short (capped at 150 ms, then pulled back further if any
  voicing is left in it) and played three times with a gap.

The same machinery does the emphasis inside a word. "In goes a sssun!" is one
recording of "In goes a sun!" with that word's own /s/ held on in place —
same speaker, same pitch, same take. It is what an adult does when they model
a sound, rather than a different recording glued to the front.

The chef's whole script is recorded, 267 clips in all:

| | |
| --- | --- |
| `phonemes/` | 9 — the pure sounds |
| `words/` | 78 — each word on its own |
| `commentary/` | 78 — "In goes a sssun!" |
| `list/` | 78 — "a sssun…", played in a row to recite any soup |
| `actions/` | 9 — the action that goes with each sound |
| `lines/` | 14 — the fixed script, including the six praise lines |
| `song/` | 1 |

A soup is whatever a child decides to put in it, so there is no recording of
one. The recital is assembled at playback: "In goes" followed by one `list/`
clip per ingredient. `assets/audio/manifest.json` records what was built, and
the app checks a whole line is there before playing any of it — half a recital
followed by silence is worse than the spoken fallback.

Every clip is trimmed to its own edges (the engine leaves up to a third of a
second of silence on the end, which is dead air after every ingredient),
loudness-matched, and written as 48 kbit/s mono — transparent for one voice
and a third the size of what the API returns. All 267 come to 2.3 MB.

## Checking it

```bash
uv run tool/build_audio.py --plan     # what would be built, and what it says
uv run tool/build_audio.py            # build what is missing
uv run tool/build_audio.py --force    # rebuild everything
uv run tool/build_audio.py --audit --deep
```

The build measures every clip before writing it, and reads it again if the
measurements are wrong — the engine is not deterministic, and now and then a
stop is released so slowly that the vowel cannot be cut away cleanly. The
checks that matter:

- a pure stop must be **under 35% voiced**. This is the "buh" test, and it is
  the reason any of this exists. The shipped stops measure 0%.
- a held sound must last between 0.35 s and 1.0 s
- /s/ must have its spectral energy high (it has to hiss); a nasal must have
  it low
- nothing silent, clipped, or too short to be a word

`--deep` additionally plays every sentence clip back through the transcriber
and checks the word survived being stretched — a long enough /n/ really does
turn "a nest" into something you hear as "a nurse". Comparison is by consonant
skeleton rather than spelling, because the transcriber writes "son" for *sun*
and "pair" for *pear*, and both clips are correct. Bare word clips are too
short for a transcriber to be sure about and are reported separately rather
than failed; each of those words is confirmed in its own sentence clip.

`test/data/audio_assets_test.dart` fails the build if a clip goes missing or
the manifest stops agreeing with what is on disk.
