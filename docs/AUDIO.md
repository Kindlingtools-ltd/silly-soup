# The chef's voice

Audio is the whole of this app. A child in an EYFS classroom copies what they
hear, so a clip that says "ess" where it should say /s/, or "buh" where it
should say /b/, does not merely sound bad — it teaches the opposite of what the
app exists to teach.

This is what the recordings are, how they are made, and how each one is
checked.

## The engine cannot say a phoneme

This is the fact everything else follows from, and it took reading the clips
back to find it. Every route was tried and transcribed:

| asked for | comes back as |
| --- | --- |
| `sss` | "S S S." |
| `b` | "B." |
| `b b b` | **"Buh buh buh."** |
| `t t t` with IPA `/t/` | **"Tuh, tuh, tuh."** |
| `sun` with IPA `/sːːʌn/` | "Son." — length marks ignored |
| `apple` with IPA `/ˈæːːpəl/` | "An app." — the word truncated |
| any text, with `speed: 0.7` | ignored |

An engine reads text. `sss` is a spelling, so it gets the letter name. `b-b-`
gets the added vowel. IPA length marks and the `speed` parameter are accepted
and silently discarded — the request succeeds, the audio comes back, and
nothing says the parameter did nothing.

"Buh" for /b/ is the single thing Letters and Sounds Phase One says never to
model. So no clip here is ever asked for as a phoneme.

## What it does instead

It says an ordinary word, checks the word came out right, and cuts the sound
out of it — which is exactly what an adult does when they model /s/ by saying
"sssun" and holding on to the front of it. The /s/ a child hears on its own is
the same /s/ from the same take of "sun": same speaker, same pitch.

Each manner of sound is cut on its own terms, because the boundary is in a
different place for each:

- **a fricative** (/s/) ends where the voice switches on — zero crossings fall
  away
- **a nasal** (/m/, /n/) is voiced, so zero crossings see nothing; it ends
  where the sound gets louder and brighter, which is the vowel starting
- **a vowel** (/a/, /i/) ends where the next consonant closes it down
- **a stop** (/t/, /p/, /b/, /d/) is a closure and a burst. The burst *is* the
  sound, and it is never held on, because holding a stop is precisely what
  makes "buh". It is taken with 32 ms of release and bounced three times.

A cut that comes out implausibly short or long is refused rather than used. A
five-millisecond "nasal" that gets stretched produces a clip which passes every
acoustic measurement and teaches the wrong sound.

## Holding a sound on without wrecking it

This is where the previous attempt at the same idea produced audible static,
and it is worth being precise about why, because there are two different
artifacts and only one of them is a click.

Repeating a chunk of audio at an arbitrary offset puts a **step** in the
waveform every time it wraps. In a periodic signal a step is a click, and a run
of them is a buzz. Cross-fading the join fixes that.

But cross-fading introduces the second artifact. Overlap two copies of a
*voiced* sound that are half a period out of step and they **cancel** where they
meet. The waveform stays perfectly continuous — there is no click to find — and
the level dips once per splice. A run of dips is heard as a warble or a rasp.

So noise may be spliced anywhere, and anything with a pitch must be spliced a
whole number of pitch periods along. That distinction is the whole of
`audio_dsp.hold`, and `envelope_ripple` is how you can tell whether it worked:

| held sound | loudness wobble |
| --- | --- |
| spliced without regard to pitch | 0.40 – 0.68 |
| spliced on pitch periods | **0.03 – 0.09** |

The loop material is also the *flattest* window in the cut, not its middle.
Phoneme boundaries are never clean, and a loop that straddles the transition
into the next sound repeats that transition however carefully it is spliced.

## Every clip is read back before it is kept

The lesson of the pass before this one. It measured zero-crossing purity,
envelope flatness and burst counts, and every number came out right — on clips
that said "Tuh, tuh, tuh" and "A tea tea tomato". **No acoustic measurement can
tell you what a clip says.** A recording can be a textbook unbroken stretch of
friction and still be the voice spelling out "S S S".

x.ai's `/v1/stt` does tell you, with word-level timings, which also makes it the
most reliable way to find where a word starts inside a phrase. It is used three
ways:

1. **The word must be the right word.** Held against its spelling, tolerantly:
   the transcriber writes what it hears in ordinary spelling, so "sun" comes
   back as "Son", "ink" as "Inc.", "anchor" as "Anka" and "pear" as "Paya".
   Those last two are it spelling Received Pronunciation correctly — RP is
   non-rhotic. Consonant skeletons are compared, so those pass while "app" for
   "apple", "nurse" for "nest" and "muck" for "milk" do not.
2. **A pure sound must not read back as a letter name or as "buh".** Silence
   from the transcriber is the right answer here: an isolated consonant is not
   a word, so there is nothing to write down. What matters is that it did not
   find "ess", "tee", "bee" or "tuh". All nine currently read back empty.
3. **The edit must not have changed the word.** The stretched clip is held
   against the take it was made from, not against a spelling. This is the check
   that matters, because stretching really can change a word — a long enough
   /n/ turns "a nest" into "a nurse" — and it is also the only check that works
   for a word like "bear", which is /ə beə/ in RP and which the transcriber
   spells "Abia" no matter how good the recording is.

When a take fails, another is recorded. When a stretch fails, the next attempt
stretches less: 330 ms, then 250, then 190. "a net" needed that (it came back
as the name "Annette"), and so did "milk", which at full stretch becomes
"muck".

## Where it stands

All 189 clips are recorded and verified:

- **9 pure sounds**, cut from `sun`, `apple`, `tap`, `pan`, `ink`, `nest`,
  `moon`, `dog`, `ball`. None reads back as a letter name or an added vowel.
- **78 words**, each read back as its own word.
- **78 words with the first sound stretched or bounced**, each read back as the
  same thing the unedited take said. The transcriber writes several of them out
  as "A p-pig" and "A t-tomato", which is positive evidence that the bounce is
  heard as a bounce rather than as "puh".
- **8 fixed phrases, 6 praise lines, 9 sound actions, the song** — these the
  engine can simply say, and they are read back too.

1.7 MiB in total, mono 24 kHz 64 kbps MP3.

A note on the transcriber: it is not perfect either. Reading all 189 back twice
gives two or three different isolated words each time — "train" as "Crane",
"tiger" as "Hyga" — because a short word with no context is genuinely
ambiguous. Every clip passed a check against a fresh transcription when it was
recorded; a second pass agreeing on all 78 emphasis clips and 76 of 78 isolated
words, with the disagreements moving between runs, is what that noise floor
looks like.

## On the voice

28 voices are offered, every one described as "multilingual" with no accent
named, so the catalogue cannot settle it. `eve` is used. What can be said from
here is that it is consistent and sits in a warm middle register (around
230 Hz), which suits three- to five-year-olds.

What **cannot** be established from a terminal is how any of them sound to a
British ear, and the British pronunciation in this app does not depend on the
answer: it comes from the `pronunciation` field on every sound and word —
Received Pronunciation in IPA, passed to the API's pronunciation map — so
"banana" is `/bəˈnɑːnə/` rather than `/bəˈnænə/`, "tomato" is `/təˈmɑːtəʊ/`,
and nothing is rhotic.

If the chef still sounds wrong, the lever is `POST /v1/custom-voices`, which
takes a reference recording and an explicit `accent: British` field. A real
adult's voice, recorded with their permission, would beat all 28 for a
classroom — and the app already supports adults recording their own content.

## What the chef says, and how

A child's choices cannot be pre-recorded, so the fixed parts are recorded once
and a sentence is built from them: `phrases/inGoes` + `emphasis/sun` +
`emphasis/sock` is "In goes a sssun… a sssock…". `ChefVoice` decides that and
hands back both the clips and the same line in words. If any one clip in a line
is missing the whole line is spoken instead — half a sentence in the chef's
voice followed by silence is worse than all of it in the device's.

`assets/data/chef_script.json` holds the fixed lines, shared by the app and the
audio tool so a caption can never disagree with the clip under it.

## Running it

```sh
pip install -r tool/requirements.txt

python3 tool/generate_audio.py --dry-run   # what is missing
python3 tool/generate_audio.py             # record what is missing
python3 tool/generate_audio.py --listen    # transcribe every committed clip
python3 tool/generate_audio.py --audit     # check every committed clip plays
python3 -m unittest discover -s tool -p 'test_*.py'
dart run tool/audio_checklist.dart         # the list for a human with a microphone
```

Clips are committed and never re-recorded unless asked. That is not only about
cost: the engine is not deterministic, so re-running would quietly swap
verified takes for untested ones.

`--audit` and the unit tests need no credentials and are what CI runs.
`--listen` and recording reach x.ai through the Agent IAP proxy, which holds
the real key — this tool never does.
