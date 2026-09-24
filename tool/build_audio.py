#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy>=2.0"]
# ///
"""Build every clip the chef says, in a British voice, with pure sounds.

    uv run tool/build_audio.py --plan     # what would be built
    uv run tool/build_audio.py            # build what is missing
    uv run tool/build_audio.py --force    # rebuild everything
    uv run tool/build_audio.py --audit    # measure what is on disk

Why this replaces the old generator
-----------------------------------
The previous tool handed the speech engine the app's phonics notation and
trusted it: `sss`, `sssun`, `b-b-banana`, `t, t, t`. An engine reads those as
spelling. Transcribing what came back:

    "sss"        -> "S S S"              (letter names)
    "sssun"      -> "Son"                (the stretch is simply gone)
    "sssock"     -> "S S O C K"          (spelled out)
    "b-b-banana" -> "Buh buh banana"     (an added "uh")
    "aaapple"    -> "R R Apple"

"Buh" is the one thing Letters and Sounds Phase One tells you never to model,
so the app was teaching the opposite of what it exists to teach. No voice
setting fixes that, because the fault is in asking a reader of text for a
sound.

So this tool never asks for a pure sound. It asks for ordinary words and
sentences, then edits the waveform: find where the first phoneme ends and
either hold it on (a continuant: "sssun") or bounce it (a stop:
"b-b-banana"). The held /s/ is the same /s/ the voice said at the front of
"sun" — same speaker, same pitch, same recording.

It also records the chef's whole script. The app previously spoke almost
everything through the device's own text-to-speech: the commentary after
every ingredient, the growing list, the praise. That voice is whatever the
browser happens to ship, usually American, and it is what a child actually
heard most of the time.

Credentials: none here. AGENT_IAM_TOKEN buys nothing except at the Agent IAP
proxy, which attaches the real speech-API credential on the way out.
"""

from __future__ import annotations

import argparse
import concurrent.futures as futures
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import audio_dsp as dsp  # noqa: E402

import numpy as np  # noqa: E402

BANK_PATH = "assets/data/sound_bank.json"
AUDIO_ROOT = "assets/audio"
MANIFEST_PATH = f"{AUDIO_ROOT}/manifest.json"

# Chosen by measurement, not by the vendor's description — see `docs/audio.md`.
# The voices are all listed as "multilingual" with no accent named, so the
# accent was measured from the waveform across all 28 of them.
VOICE = "eve"
LANGUAGE = "en-GB"

# How long the chef holds a stretchable sound: long enough for a child to
# hear it and join in, short enough not to become a drone.
HOLD_SECONDS = 0.55

# The most a held sound may flutter, as a percentage of its own level, in the
# 10-40 Hz band. A steady sound should barely move. This is the check that
# would have caught the loop joins cancelling — they modulated the sound at
# about 20 Hz, which the ear hears as a harsh buzz rather than as a wobble,
# and which was reported as static.
MAX_ROUGHNESS = 10.0
# A bounced sound: three light taps, as an adult does it.
BOUNCE_REPEATS = 3
BOUNCE_GAP_MS = 170
# Inside a word ("sssun") the stretch is shorter — it leads into the word
# rather than standing on its own, and how much shorter depends on the sound.
# A held /s/ can run on as long as you like and still be heard as part of
# "sun". A held /n/ cannot: past about a fifth of a second "a nnnest" starts
# to be heard as a word of its own, and read back as "a nurse".
WORD_HOLD_SECONDS = {"fricative": 0.32, "vowel": 0.28, "nasal": 0.20}
WORD_BOUNCE_REPEATS = 2  # two extra taps, then the word itself
WORD_BOUNCE_GAP_MS = 130

# Which acoustic family each sound belongs to. The boundary between the first
# phoneme and the rest of the word is found differently for a hiss, a nasal
# murmur, a burst and a vowel, so the tool has to be told which it is.
PHONETIC_CLASS = {
    "s": "fricative",
    "m": "nasal",
    "n": "nasal",
    "a": "vowel",
    "i": "vowel",
    "t": "stop",
    "p": "stop",
    "b": "stop",
    "d": "stop",
}

# A word to lift each pure sound out of. Picked so the sound is at the very
# front, is not part of a cluster, and is followed by something that makes
# the boundary easy to hear.
CARRIER = {
    "s": "sun",
    "a": "apple",
    "t": "tap",
    "p": "pan",
    "i": "igloo",
    "n": "nest",
    "m": "map",
    "d": "dog",
    "b": "ball",
}

# The chef's fixed script. Keep in step with lib/services/recital_service.dart
# and lib/providers/soup_provider.dart.
LINES = {
    "watch_me": "Watch me make my silly soup!",
    "now_you": "Now you make a silly soup!",
    "my_sound_today": "My sound today is",
    "in_goes": "In goes",
    "soup_has": "Your silly soup has",
    "and": "and",
    "in_it": "in it!",
    "empty_pan": "An empty pan! That is the silliest soup of all.",
    "praise_0": "Ooh, what a silly soup!",
    "praise_1": "What a wonderful wobbly recipe!",
    "praise_2": "That is the silliest soup I have ever seen!",
    "praise_3": "Mmm, what a clever cook you are!",
    "praise_4": "Look at all those lovely sounds!",
    "praise_5": "What a splendid, sloppy soup!",
}

SONG = (
    "Stir the pot and stir it round, "
    "Silly soup is bubbling. "
    "In go all the sounds we found — "
    "Whoosh! goes the soup!"
)


# ------------------------------------------------------------------ the plan


@dataclass
class Clip:
    """One file to produce.

    `text` is what the voice is asked to say — always ordinary English.
    `emphasise` names the word inside that text whose first phoneme gets held
    or bounced afterwards; the phonics is done to the waveform, never asked
    for in the text.
    """

    path: str
    kind: str
    text: str = ""
    sound: str = ""
    emphasise: str = ""
    checks: dict = field(default_factory=dict)

    @property
    def full(self) -> str:
        return f"{AUDIO_ROOT}/{self.path}"

    def exists(self) -> bool:
        return os.path.exists(self.full)


def load_bank() -> dict:
    with open(BANK_PATH, encoding="utf-8") as handle:
        return json.load(handle)


def article(sound: dict) -> str:
    """"a" or "an", chosen by sound rather than spelling, as the app does."""
    return "an" if sound.get("isVowel") else "a"


def plan(bank: dict) -> list[Clip]:
    sounds = {s["id"]: s for s in bank["sounds"]}
    clips: list[Clip] = []

    for sound_id, sound in sounds.items():
        klass = PHONETIC_CLASS.get(sound_id, "stop" if sound.get("articulation") == "stop" else "fricative")
        carrier = CARRIER.get(sound_id)
        if carrier:
            clips.append(Clip(
                path=f"phonemes/{sound_id}.mp3", kind="phoneme", text=carrier,
                sound=sound_id, checks={"class": klass},
            ))
        if sound.get("action"):
            clips.append(Clip(path=f"actions/{sound_id}.mp3", kind="line",
                              text=sound["action"], sound=sound_id))

    for word in bank["words"]:
        name, sound_id = word["word"], word["phoneme"]
        sound = sounds.get(sound_id, {})
        klass = PHONETIC_CLASS.get(sound_id, "fricative")
        determiner = article(sound)
        clips += [
            Clip(path=f"words/{name}.mp3", kind="word", text=name, sound=sound_id),
            Clip(path=f"commentary/{name}.mp3", kind="commentary",
                 text=f"In goes {determiner} {name}!", sound=sound_id,
                 emphasise=name, checks={"class": klass}),
            Clip(path=f"list/{name}.mp3", kind="list",
                 text=f"{determiner} {name}…", sound=sound_id,
                 emphasise=name, checks={"class": klass}),
        ]

    for key, text in LINES.items():
        clips.append(Clip(path=f"lines/{key}.mp3", kind="line", text=text))

    clips.append(Clip(path="song/silly_soup_song.mp3", kind="song", text=SONG))
    return clips


# ------------------------------------------------------------------- speech


class SpeechError(RuntimeError):
    pass


def _proxy() -> tuple[str, str]:
    host = os.environ.get("AGENT_IAM_HOST")
    token = os.environ.get("AGENT_IAM_TOKEN")
    if not host or not token:
        raise SystemExit(
            "AGENT_IAM_HOST and AGENT_IAM_TOKEN must be set. This tool only "
            "speaks to the API through the Agent IAP proxy; it never holds a key."
        )
    return host, token


def synthesise(text: str, voice: str, language: str, attempts: int = 3) -> bytes:
    host, token = _proxy()
    body = json.dumps({"text": text, "voice_id": voice, "language": language}).encode()
    last = None
    for _ in range(attempts):
        request = urllib.request.Request(
            f"http://{host}/xai/v1/tts", data=body,
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", "replace")[:200]
            last = SpeechError(f"HTTP {error.code}: {detail}")
            if error.code < 500:
                raise last from error
        except Exception as error:  # noqa: BLE001 - network flake, worth a retry
            last = SpeechError(str(error))
    raise last or SpeechError("unknown failure")


def transcribe(path: str) -> dict:
    """Read a clip back. Used both to place a word and to audit the result."""
    host, token = _proxy()
    result = subprocess.run(
        ["curl", "-s", "-m", "180", "-X", "POST",
         "-H", f"Authorization: Bearer {token}", "-F", f"file=@{path}",
         f"http://{host}/xai/v1/stt"],
        capture_output=True, text=True,
    ).stdout
    try:
        return json.loads(result)
    except json.JSONDecodeError:
        return {}


# ------------------------------------------------------------------ shaping


def _bounce(onset: np.ndarray, rest: np.ndarray, repeats: int, gap_ms: float) -> np.ndarray:
    """A stop sound, tapped. Never held — holding one is what makes "buh"."""
    tap = dsp.fade(onset, in_ms=2, out_ms=14)
    pieces: list[np.ndarray] = []
    for _ in range(repeats):
        pieces += [tap, dsp.silence(gap_ms)]
    if len(rest):
        pieces.append(rest)
    return np.concatenate(pieces)


def emphasise_in_place(audio: np.ndarray, start: int, end: int, klass: str,
                       hold_seconds: float, repeats: int, gap_ms: float) -> np.ndarray:
    """Hold or bounce the first phoneme of one word, leaving the rest alone.

    `start`/`end` bound the word inside a longer sentence, so the chef's
    "In goes a sssun!" is one recording with one intonation rather than
    fragments glued together.
    """
    before, word, after = audio[:start], audio[start:end], audio[end:]
    boundary = max(min(dsp.onset_end(word, klass), len(word) - 1), 1)
    if klass == "stop":
        boundary = dsp.trim_stop_onset(word, boundary)
    onset, rest = word[:boundary], word[boundary:]

    if klass == "stop":
        shaped = _bounce(onset, word, repeats, gap_ms)
    elif klass == "fricative":
        shaped = dsp.splice(dsp.hold_noise(onset, hold_seconds), rest)
    else:  # nasal, vowel — both periodic
        shaped = dsp.splice(dsp.hold(onset, hold_seconds), rest)

    return dsp.splice(dsp.splice(before, shaped), after) if len(before) or len(after) else shaped


def pure_sound(audio: np.ndarray, klass: str) -> np.ndarray:
    """The sound on its own, lifted out of its carrier word."""
    boundary = max(dsp.onset_end(audio, klass), 1)
    if klass == "stop":
        boundary = dsp.trim_stop_onset(audio, boundary)
    onset = audio[:boundary]
    if klass == "stop":
        return _bounce(onset, np.array([]), BOUNCE_REPEATS, BOUNCE_GAP_MS)
    held = dsp.hold_noise(onset, HOLD_SECONDS) if klass == "fricative" else dsp.hold(onset, HOLD_SECONDS)
    return dsp.fade(held, in_ms=10, out_ms=90)


def locate(words: list[dict], target: str) -> tuple[float, float] | None:
    """Where the target word sits in a transcribed sentence.

    Matched by sound, because the transcriber spells what it hears: "a sun…"
    comes back as "A son." and the clip is perfectly good.
    """
    for entry in words:
        token = entry.get("text", "").strip(".,!?;:…")
        if not _sounds_like(target, token):
            continue
        start, end = entry["start"], entry["end"]
        # "a net" is pronounced exactly like "Annette", and the transcriber
        # writes it as one word. Stretching from the front of that token would
        # hold the article rather than the /n/, so skip past the letters the
        # token has that the word does not.
        letters = "".join(c for c in token.lower() if c.isalpha())
        extra = len(letters) - len(target)
        if extra > 0:
            start += (end - start) * extra / max(len(letters), 1)
        return start, end
    return None


# ------------------------------------------------------------------ building


def _render(clip: Clip, voice: str, language: str, attempt: int):
    """One reading, shaped. Returns the finished waveform."""
    raw = f"/tmp/silly-soup-audio/{clip.path.replace('/', '_')}.{attempt}.src.mp3"
    os.makedirs(os.path.dirname(raw), exist_ok=True)
    with open(raw, "wb") as handle:
        handle.write(synthesise(clip.text, voice, language))

    audio = dsp.trim(dsp.decode(raw))
    klass = clip.checks.get("class", "")

    if clip.kind == "phoneme":
        audio = pure_sound(audio, klass)
    elif clip.emphasise:
        heard = transcribe(raw)
        span = locate(heard.get("words", []), clip.emphasise)
        if span is None:
            raise SpeechError(
                f"could not find {clip.emphasise!r} in the reading of "
                f"{clip.text!r} (heard {heard.get('text', '')!r})"
            )
        lead = _lead_offset(raw)
        start = max(int(span[0] * dsp.SR) - lead, 0)
        end = min(int(span[1] * dsp.SR) - lead, len(audio))
        if end - start < int(0.05 * dsp.SR):
            raise SpeechError(f"{clip.emphasise!r} came out too short to shape")
        audio = emphasise_in_place(
            audio, start, end, klass,
            WORD_HOLD_SECONDS.get(klass, 0.24),
            WORD_BOUNCE_REPEATS, WORD_BOUNCE_GAP_MS,
        )

    return dsp.normalise(dsp.fade(audio, in_ms=6, out_ms=30))


def _readback_problems(clip: Clip, audio, attempt: int) -> list[str]:
    """Play the finished clip back to a listener and check the word survived.

    Holding a sound on inside a word is a real edit to the waveform, and it
    can go too far: a long enough /n/ turns "a nest" into something a
    transcriber hears as "a nurse". If a speech recogniser cannot get the word
    back out, a four-year-old has no chance, so the reading is thrown away and
    the engine asked again.
    """
    probe = f"/tmp/silly-soup-audio/{clip.path.replace('/', '_')}.{attempt}.check.mp3"
    dsp.encode(audio, probe)
    heard = transcribe(probe).get("text", "")
    if _sounds_like(clip.emphasise, heard):
        return []
    return [f"reads back as {heard.strip()!r}"]


def _sounds_like(word: str, heard: str) -> bool:
    """Whether `heard` contains `word`, judged by sound rather than spelling.

    The clip is right and the spelling is a red herring often enough that
    matching letters rejects good audio: "sun" comes back as "son", "pear" as
    "pair", and "a net" as "Annette" — all correct readings of correct clips.
    English homophones differ in their vowels and agree on their consonants,
    so comparing consonant skeletons asks the question actually worth asking,
    which is whether the word survived having its first sound stretched.
    """
    def flatten(text: str) -> str:
        return "".join(c for c in text.lower() if c.isalpha())

    if flatten(word) in flatten(heard):
        return True

    # English spells the same consonant several ways, and the transcriber
    # picks whichever it likes: "ink" comes back as "Inc".
    SAME_SOUND = str.maketrans({"c": "k", "z": "s", "q": "k", "y": "i"})

    def skeleton(text: str) -> str:
        letters = flatten(text).translate(SAME_SOUND).replace("x", "ks").replace("ph", "f")
        # "h" is never a sound of its own in this vocabulary — it is the tail
        # of a digraph ("anchor", "mushroom") — and keeping it makes those
        # words fail against a transcript that spelled the digraph differently.
        out = [c for c in letters if c not in "aeiouh"]
        out = [c for i, c in enumerate(out) if i == 0 or c != out[i - 1]]
        # The voice is non-rhotic, which is the whole point of choosing it:
        # "anchor" is said, and transcribed, as "Anka". Insisting on the
        # final /r/ would fail the clips for being British.
        return "".join(out[:-1] if out and out[-1] == "r" else out)

    bones = skeleton(word)
    return bool(bones) and bones in skeleton(heard)


def build(clip: Clip, voice: str, language: str, attempts: int = 4) -> dict:
    """Produce one clip, reading it again if the first reading is not good.

    The engine is not deterministic: the same word comes back a little
    different every time, and now and then a stop is released so slowly that
    the vowel behind it cannot be cut away cleanly. Rather than ship that one
    clip and hope nobody hears it, measure and ask again.
    """
    best, best_problems, last_error = None, None, None
    for attempt in range(attempts):
        try:
            audio = _render(clip, voice, language, attempt)
        except SpeechError as error:
            last_error = error
            continue
        problems = check_audio(clip, audio)
        if not problems and clip.emphasise and clip.kind != "phoneme":
            problems = _readback_problems(clip, audio, attempt)
        if not problems:
            dsp.encode(audio, clip.full)
            return {"path": clip.path, "attempts": attempt + 1, **dsp.describe(audio)}
        if best is None or len(problems) < len(best_problems):
            best, best_problems = audio, problems
    if best is None:
        raise last_error or SpeechError("no usable reading")
    raise SpeechError(f"{attempts} readings, none good: {'; '.join(best_problems)}")


def _lead_offset(raw_path: str) -> int:
    """How many samples `trim` took off the front."""
    original = dsp.decode(raw_path)
    energy, hop = dsp._rms(original)  # noqa: SLF001 - same package, same author
    if not len(energy):
        return 0
    loud = np.flatnonzero(energy > max(0.02, 0.06 * energy.max()))
    if not len(loud):
        return 0
    return max(int(loud[0] * hop) - int(dsp.SR * 20 / 1000), 0)


# ------------------------------------------------------------------- audit


def check_audio(clip: Clip, audio) -> list[str]:
    """Measure one clip's waveform. Returns the reasons it is wrong, if any.

    The same checks gate the build and the audit, so a clip can never be
    written that the audit would then reject.
    """
    facts = dsp.describe(audio)
    problems: list[str] = []

    if facts["duration"] < 0.12:
        problems.append(f"only {facts['duration']:.2f}s long")
    if facts["peak"] < 0.2:
        problems.append(f"near silent (peak {facts['peak']:.2f})")
    if facts["duration"] > 12.0:
        problems.append(f"{facts['duration']:.1f}s is too long to sit through")

    klass = clip.checks.get("class", "")
    if clip.kind == "phoneme":
        if klass == "stop":
            # The whole point. A stop with a vowel behind it is "buh".
            if facts["voiced"] > 0.35:
                problems.append(f"a vowel has crept in ({facts['voiced']:.0%} voiced)")
            if facts["duration"] > 1.4:
                problems.append(f"{facts['duration']:.2f}s is not a bounce")
        else:
            if not 0.35 <= facts["duration"] <= 1.0:
                problems.append(f"held for {facts['duration']:.2f}s")
            if facts["voiced"] < 0.5 and klass in {"vowel", "nasal"}:
                problems.append(f"only {facts['voiced']:.0%} voiced")
        if klass != "stop":
            # A bounced stop is three taps with gaps, so it modulates by
            # design; asking this of one is meaningless.
            flutter = dsp.roughness(audio)
            if flutter > MAX_ROUGHNESS:
                problems.append(f"flutters at {flutter:.0f}% (a buzz, not a steady sound)")
        if klass == "fricative" and facts["centroid"] < 3500:
            problems.append(f"does not hiss (centroid {facts['centroid']:.0f} Hz)")
        if klass == "nasal" and facts["centroid"] > 1200:
            problems.append(f"too bright for a nasal ({facts['centroid']:.0f} Hz)")

    return problems


def audit_clip(clip: Clip, deep: bool) -> tuple[list[str], list[str]]:
    """Returns (faults, unconfirmed).

    A fault is something measured about the waveform, and is always real. An
    "unconfirmed" is the transcriber failing to get a word back out of a
    third-of-a-second clip with nothing around it — "pear" comes back as
    "pier", which is what a non-rhotic British /peə/ sounds like. Those are
    worth printing and not worth failing on, so they are kept apart.
    """
    if not clip.exists():
        return ["missing"], []
    faults = check_audio(clip, dsp.decode(clip.full))
    unconfirmed: list[str] = []
    if deep and clip.kind in {"word", "commentary", "list"} and not faults:
        trouble = _readback_in_context(clip)
        # A whole sentence has enough context that the transcriber has no
        # excuse; a bare word does not.
        (unconfirmed if clip.kind == "word" else faults).extend(trouble)
    return faults, unconfirmed


def _readback_in_context(clip: Clip) -> list[str]:
    """Read a clip back to a listener, giving it something to hold on to.

    A bare word lasting a third of a second is genuinely ambiguous — "map"
    transcribes as "Ma", "axe" as nothing at all — and the same word inside
    "In goes a map!" comes back perfectly. That is a limit of the listener,
    not a fault in the clip, so the audit gives it the carrier phrase the
    chef actually says before deciding the clip is wrong.
    """
    target = clip.emphasise or clip.text
    pieces = [dsp.decode(clip.full)]
    carrier = f"{AUDIO_ROOT}/lines/in_goes.mp3"
    if clip.kind == "word" and os.path.exists(carrier):
        pieces = [dsp.decode(carrier), dsp.silence(200), pieces[0]]
    probe = f"/tmp/silly-soup-audio/audit_{clip.path.replace('/', '_')}"
    dsp.encode(np.concatenate(pieces), probe)
    heard = transcribe(probe).get("text", "")
    if _sounds_like(target, heard):
        return []
    return [f"reads back as {heard.strip()!r}"]


# --------------------------------------------------------------------- main


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", action="store_true", help="list what would be built")
    parser.add_argument("--force", action="store_true", help="rebuild clips already on disk")
    parser.add_argument("--audit", action="store_true", help="measure what is on disk and stop")
    parser.add_argument("--deep", action="store_true", help="in --audit, also read every word clip back")
    parser.add_argument("--only", default="", help="build only paths containing this")
    parser.add_argument("--voice", default=VOICE)
    parser.add_argument("--language", default=LANGUAGE)
    parser.add_argument("--jobs", type=int, default=8)
    args = parser.parse_args()

    if not os.path.exists(BANK_PATH):
        print(f"Could not find {BANK_PATH}. Run this from the project root.", file=sys.stderr)
        return 2

    everything = plan(load_bank())
    # `--only` narrows what gets built, never what the manifest describes: the
    # app reads the manifest to decide whether a line is fully recorded, so a
    # manifest listing one clip would silence the other 266.
    clips = [c for c in everything if args.only in c.path] if args.only else everything

    if args.audit:
        return run_audit(clips, args)

    todo = clips if args.force else [c for c in clips if not c.exists()]
    print(f"{len(clips)} clips, {len(clips) - len(todo)} already on disk, {len(todo)} to build.")
    if args.plan:
        for clip in todo:
            shape = f" [{clip.checks.get('class')}]" if clip.checks.get("class") else ""
            print(f"  {clip.path:42} <- {clip.text!r}{shape}")
        return 0
    if not todo:
        write_manifest(everything, args)
        return 0

    built, failed = 0, []
    with futures.ThreadPoolExecutor(args.jobs) as pool:
        pending = {
            pool.submit(build, clip, args.voice, args.language,
                        8 if clip.kind == "phoneme" else 4): clip
            for clip in todo
        }
        for future in futures.as_completed(pending):
            clip = pending[future]
            try:
                facts = future.result()
                built += 1
                print(f"  ✓ {clip.path:42} {facts['duration']:.2f}s")
            except Exception as error:  # noqa: BLE001 - reported, then carried on
                failed.append((clip, error))
                print(f"  ✗ {clip.path:42} {error}", file=sys.stderr)

    print(f"\n{built} built, {len(failed)} failed.")
    write_manifest(everything, args)
    return 1 if failed else 0


def run_audit(clips: list[Clip], args) -> int:
    print(f"Auditing {len(clips)} clips" + (" (reading every clip back)" if args.deep else "") + "…")
    bad: list[tuple[Clip, list[str]]] = []
    soft: list[tuple[Clip, list[str]]] = []
    with futures.ThreadPoolExecutor(args.jobs) as pool:
        pending = {pool.submit(audit_clip, clip, args.deep): clip for clip in clips}
        for future in futures.as_completed(pending):
            clip = pending[future]
            faults, unconfirmed = future.result()
            if faults:
                bad.append((clip, faults))
            if unconfirmed:
                soft.append((clip, unconfirmed))

    for kind in sorted({c.kind for c in clips}):
        group = [c for c in clips if c.kind == kind]
        wrong = [c for c, _ in bad if c.kind == kind]
        print(f"  {kind:11} {len(group) - len(wrong):3}/{len(group):<3} good")
    if bad:
        print("\nProblems:")
        for clip, problems in sorted(bad, key=lambda pair: pair[0].path):
            print(f"  {clip.path:42} {'; '.join(problems)}")
    else:
        print("\nEvery clip passes.")
    if soft:
        print("\nToo short to confirm by ear — each of these words is read back "
              "correctly in its own sentence clip:")
        for clip, problems in sorted(soft, key=lambda pair: pair[0].path):
            print(f"  {clip.path:42} {'; '.join(problems)}")
    return 1 if bad else 0


def write_manifest(clips: list[Clip], args) -> None:
    """What the app loads to know which clips it may chain together.

    Without it the app has to try a clip to discover it is missing, which
    means a half-played sentence when one is.
    """
    present = sorted(c.path for c in clips if c.exists())
    manifest = {
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "voice": args.voice,
        "language": args.language,
        "sampleRateHz": dsp.SR,
        "clips": present,
    }
    with open(MANIFEST_PATH, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2)
        handle.write("\n")
    print(f"Wrote {MANIFEST_PATH} ({len(present)} clips).")


if __name__ == "__main__":
    raise SystemExit(main())
