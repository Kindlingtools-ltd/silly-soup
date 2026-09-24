# The chef's voice

Audio is the whole of this app. A child in an EYFS classroom is copying what
they hear, so a clip that says "ess" instead of "sss", or says "buh" instead of
bouncing a clean /b/, does not just sound bad — it teaches the wrong thing.

This is what the recordings are, how they are made, and what was measured to
decide it.

## How British English is actually obtained

x.ai's text-to-speech takes a `language` parameter. It documents twenty BCP-47
codes — `en`, `zh`, `pt-BR`, `es-ES`, `auto`, and so on — and **`en-GB` is not
one of them.** Sending it is not an error either. The API accepts any string
there; `en-GB`, `en-ZZ` and `klingon` all return 200 and audio. Nothing tells
you the code was ignored.

So the accent cannot be requested. It is written out instead:

- Every sound and every word in `assets/data/sound_bank.json` carries a
  `pronunciation` field: Received Pronunciation in IPA, between slashes.
- `tool/generate_audio.py` passes those to the API's `replace` map, which
  accepts "a respelling or IPA phonetics written between forward slashes".
- So "banana" is `/bəˈnɑːnə/` and not `/bəˈnænə/`, "tomato" is `/təˈmɑːtəʊ/`,
  "sausage" keeps its `/ɒ/`, "newspaper" keeps its yod, and every `-er` and
  `-or` ending is non-rhotic: `/ˈtaɪɡə/`, `/dɔː/`, `/ˈdaɪnəsɔː/`.

Ten words were checked plain against their IPA, three takes each. The IPA
version came out consistently a little longer — which is what a correct RP
reading of `/ɑː/`, `/ɔː/` and `/əʊ/` should be — and never long enough to
suggest the transcription was being spelled out symbol by symbol. The
`audio_assets_test` keeps every transcription starting with the sound its word
is filed under, which is also what lets the chef stretch it.

## The pure sounds, which are the point of the app

Asked for the text `sss`, the voice produces something with vowel in it: a
zero-crossing analysis of the returned audio shows alternating vowel and
fricative segments, which is the voice reading the letter name "ess". That is
exactly the mistake this app exists to avoid, and it is why the previous pass
shipped no pure-sound clips at all.

Asked for `sss` with `replace: {"sss": "/sːː/"}`, the same voice produces one
continuous stretch of friction with no voiced segment anywhere in it.

Stops cannot be held on, which is why Phase One bounces them. `/b/` repeated
three times gives three separate bursts, and the recording is only kept if
three bursts are actually what came back.

## The voice itself

All 28 built-in voices were auditioned on the one thing that matters most
here — whether they can produce a clean held /s/ with no voicing in it — plus
pitch and level. Eight of them cannot: `atlas`, `cosmo`, `iris` and `naksh`
returned no friction at all, and `rigel` returned 2.7 seconds of vowel. Any of
those would teach letter names.

The shortlist was then re-run five times each, because one take proves nothing
(see below). On the medians, `eve` holds the sound longest and most reliably
(0.90 s, never below 0.52, no voicing in any take) and sits at about 229 Hz —
a warm middle register rather than a rumble or a shriek. `ara` is the closest
runner-up. `eve` is what ships; `--voice` changes it, and the audition is
cheap to repeat.

What could **not** be established from here is how any of these voices sound
to a British ear. The API exposes no accent for its built-in voices, and none
of this can be judged by listening. If the chef still sounds American to you,
the lever is `POST /v1/custom-voices`, which takes a reference recording and
an `accent: British` field — a real adult's voice, recorded with their
permission, would be better than any of the built-in ones for this app.

## Nothing here trusts one take

The API is not deterministic. The same request sent three times returns three
different recordings, of different lengths, with different envelopes. Some
fraction of takes are silent, clipped, swallowed, or have a vowel where there
should not be one.

A single blind pass over two hundred clips therefore ships a handful of
recordings that are wrong, and no amount of care in the request prevents it.
So every clip is recorded several times — eight for a pure sound, four for
everything else — each take is measured, and the best survivor is kept:

| check | catches |
| --- | --- |
| any audio above the noise floor | a silent take |
| no samples at full scale | a clipped take |
| speech length inside the band for its kind | a swallowed take, or one where the IPA got spelled out |
| burst count | a bounced stop that merged or dropped a bounce |
| envelope flatness | a held nasal or vowel that came back as a letter name |
| no voicing in a voiceless fricative | "ess" creeping into "sss" |

`/s/` needed six takes before one passed. Several words needed two or three.
That is the machinery earning its keep rather than misbehaving.

Because the takes differ, **clips are committed and never regenerated
casually**. Re-running the tool only fills gaps; `--force` replaces good
recordings with untested ones.

## After the take is chosen

- **Silence trimmed.** Every response arrives with 0.3–0.6 s of dead air on
  the end. The chef waits for each clip to finish before starting the next, so
  that silence used to land between every word the child heard — about two
  seconds of nothing across a five-item recital.
- **Loudness matched** to −20 dBFS RMS with a −1.5 dBFS ceiling. Peak
  normalising alone leaves a hissed "sss" far quieter than "banana", because a
  fricative has a low peak and plenty of energy.
- **10 ms fades** so a trimmed edge does not click.
- **Encoded** as mono 24 kHz 64 kbps MP3. 189 clips come to 1.9 MiB — more
  than twice the clips the app used to have, in a little over the bytes.

## What the chef says, and how

There is no way to pre-record every sentence, because the child chooses the
ingredients. So the fixed parts are recorded once and the sentence is built
from them: `phrases/inGoes` + `emphasis/sun` + `emphasis/sock` is "In goes a
sssun… a sssock…". `ChefVoice` does that, and returns both the clips and the
same line in words. If any one clip in a line is missing, the whole line is
spoken rather than played — half a sentence in the chef's voice followed by
silence is worse than the whole thing in the device's.

`assets/data/chef_script.json` holds the fixed lines. It is there rather than
in Dart because both the app and the audio tool need them and they must not
drift: the caption on screen is what an adult reads aloud, so a caption that
disagrees with the clip under it is a phonics error.

## Running it

```sh
pip install -r tool/requirements.txt

python3 tool/generate_audio.py --dry-run     # what is missing
python3 tool/generate_audio.py               # record what is missing
python3 tool/generate_audio.py --audit       # check what is committed
python3 tool/generate_audio.py --only phonemes --takes 12
dart run tool/audio_checklist.dart           # the list for a human recording it
```

The tool holds no API key. It reaches x.ai through the Agent IAP proxy using
`AGENT_IAM_HOST` and `AGENT_IAM_TOKEN`, and the proxy attaches the real
credential. `--audit` needs neither, and is what CI runs.
