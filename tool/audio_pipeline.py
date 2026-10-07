"""Turn text into the clips Silly Soup ships, and refuse the bad takes.

The x.ai voice API is not deterministic: the same request twice comes back as
two different recordings, of different lengths, and every so often one of them
is silent, clipped, or has a vowel stuck on the end of a consonant. A single
blind pass over a hundred clips therefore produces a handful of recordings
that teach a four-year-old the wrong thing.

So nothing here trusts one take. Every clip is generated several times, each
take is measured, takes that fail their measurements are thrown away, and the
best survivor is trimmed, levelled and encoded. What the measurements are, and
why each one matters to a phonics app, is in `Spec` and `score` below.
"""

from __future__ import annotations

import io
import json
import math
import os
import struct
import urllib.error
import urllib.request
import wave
from dataclasses import dataclass, field

# 24 kHz mono is plenty for a voice and keeps the bundle small; the app is a
# PWA that has to work offline on a school tablet.
SAMPLE_RATE = 24_000
MP3_BITRATE = 64

# Peak normalising alone leaves a hissed "sss" far quieter than a shouted
# "banana", because a fricative has a low peak and plenty of energy. Matching
# loudness means matching RMS, then making sure the peak still fits.
TARGET_RMS_DBFS = -20.0
CEILING_DBFS = -1.5

FRAME_MS = 20
# Anything below this fraction of the clip's own peak is silence, not sound.
SILENCE_FLOOR = 0.08

LEAD_PAD_MS = 40
TRAIL_PAD_MS = 120
# The end of a word is judged far more gently than the start. A word that
# finishes on an unreleased /k/, /p/ or /t/ finishes quietly, and trimming the
# tail at the same threshold as the rest cut the consonant clean off: "sock"
# came back from the transcriber as "So", "soup" as "Sue", "map" as nothing at
# all. Every clip that failed ended in a voiceless stop.
TAIL_FLOOR = 0.015
FADE_MS = 10


class TtsError(RuntimeError):
    pass


@dataclass(frozen=True)
class Voice:
    """Everything about how the chef speaks.

    `language` is `en` and not `en-GB` on purpose. x.ai documents twenty
    BCP-47 codes and `en-GB` is not among them — it accepts the string and
    ignores it, which is exactly how the first pass at this audio ended up
    sounding American. British English is not requested here; it is spelled
    out, phoneme by phoneme, in the `pronunciation` fields of the sound bank.
    """

    voice_id: str = "eve"
    language: str = "en"
    # 1.0 is a news-reader's pace. A little under it is the pace an adult
    # naturally uses with a three-year-old.
    speed: float = 0.9


@dataclass
class Analysis:
    seconds: float
    peak: int
    clipped: int
    lead: float
    speech: float
    trail: float
    segments: list[tuple[float, float]]
    flatness: float
    fricative: float
    vowel: float
    first: int
    last: int


@dataclass
class Spec:
    """One clip, and what a good recording of it has to look like."""

    path: str
    kind: str
    text: str
    replace: dict[str, str] = field(default_factory=dict)
    # Bounds on the spoken part, in seconds. Too short means the take was
    # swallowed; too long means the voice has read something it should not
    # have — a letter name, or the IPA spelled out symbol by symbol.
    min_speech: float = 0.15
    max_speech: float = 4.0
    # Stops are modelled by bouncing them three times ("b-b-b"), so a good
    # take really does contain three separate bursts. Counting them is the
    # cheapest way to catch a take that merged or dropped one.
    want_segments: int | None = None
    # A held sound ("mmm", "sss") has a flat envelope. A letter name ("em")
    # is a loud vowel followed by a quiet consonant, which is not flat.
    min_flatness: float | None = None
    # A held /s/ or /f/ should be almost entirely friction. Any stretch of
    # loud, low-zero-crossing sound in one is a vowel that does not belong.
    max_vowel: float | None = None
    speed: float | None = None

    @property
    def ideal_speech(self) -> float:
        return (self.min_speech + self.max_speech) / 2


def synthesise(spec: Spec, voice: Voice, host: str, token: str) -> bytes:
    """One take, as a WAV. WAV rather than MP3 because every measurement
    below needs the samples, and nothing here can decode an MP3."""
    body = {
        "text": spec.text,
        "voice_id": voice.voice_id,
        "language": voice.language,
        "speed": spec.speed if spec.speed is not None else voice.speed,
        "output_format": {"codec": "wav", "sample_rate": SAMPLE_RATE},
    }
    if spec.replace:
        body["replace"] = spec.replace
    request = urllib.request.Request(
        f"http://{host}/xai/v1/tts",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            audio = response.read()
    except urllib.error.HTTPError as error:
        raise TtsError(f"HTTP {error.code}: {error.read().decode()[:300]}") from None
    if audio[:4] != b"RIFF":
        raise TtsError(f"not a WAV: {audio[:200]!r}")
    return audio


def samples(wav_bytes: bytes) -> tuple[list[int], int]:
    reader = wave.open(io.BytesIO(wav_bytes))
    if reader.getsampwidth() != 2:
        raise TtsError(f"expected 16-bit audio, got {reader.getsampwidth() * 8}-bit")
    raw = reader.readframes(reader.getnframes())
    values = list(struct.unpack(f"<{len(raw) // 2}h", raw))
    if reader.getnchannels() == 2:
        values = values[::2]
    return values, reader.getframerate()


def analyse(values: list[int], rate: int) -> Analysis:
    """Measure a take. Everything `score` decides is decided from this."""
    length = max(1, rate * FRAME_MS // 1000)
    frames = []
    for start in range(0, max(1, len(values) - length + 1), length):
        window = values[start : start + length]
        rms = math.sqrt(sum(v * v for v in window) / len(window))
        crossings = sum(
            1 for a, b in zip(window, window[1:]) if (a >= 0) != (b >= 0)
        ) / max(1, len(window) - 1)
        frames.append((start, rms, crossings))

    peak = max((abs(v) for v in values), default=0)
    floor = (peak or 1) * SILENCE_FLOOR
    loud = [f for f in frames if f[1] > floor]
    if not loud:
        return Analysis(
            seconds=len(values) / rate, peak=peak, clipped=0, lead=len(values) / rate,
            speech=0.0, trail=0.0, segments=[], flatness=0.0, fricative=0.0,
            vowel=0.0, first=0, last=0,
        )

    first, last = loud[0][0], loud[-1][0] + length
    # Bursts of sound with real gaps between them. The gap has to be long
    # enough not to trip on the closure inside a single "b".
    gap_frames = max(1, int(0.09 * rate / length))
    segments, run_start, quiet = [], None, 0
    for start, rms, _ in frames:
        if rms > floor:
            if run_start is None:
                run_start = start
            quiet = 0
        elif run_start is not None:
            quiet += 1
            if quiet >= gap_frames:
                segments.append((run_start / rate, (start - quiet * length) / rate))
                run_start = None
    if run_start is not None:
        segments.append((run_start / rate, last / rate))

    levels = sorted(f[1] for f in loud)
    median = levels[len(levels) // 2]
    strong = (peak or 1) * 0.15
    return Analysis(
        seconds=len(values) / rate,
        peak=peak,
        clipped=sum(1 for v in values if abs(v) >= 32_700),
        lead=first / rate,
        speech=(last - first) / rate,
        trail=max(0.0, (len(values) - last) / rate),
        segments=segments,
        flatness=median / (peak or 1),
        fricative=sum(
            FRAME_MS / 1000 for _, rms, zc in loud if rms > strong and zc >= 0.20
        ),
        vowel=sum(
            FRAME_MS / 1000 for _, rms, zc in loud if rms > strong and zc < 0.08
        ),
        first=first,
        last=last,
    )


def score(spec: Spec, a: Analysis) -> tuple[bool, str, float]:
    """(usable, why not, distance from ideal). Lower distance wins."""
    if a.speech <= 0:
        return False, "silent", 0.0
    if a.clipped:
        return False, f"{a.clipped} clipped samples", 0.0
    if a.peak < 3_000:
        return False, f"almost inaudible (peak {a.peak})", 0.0
    if a.speech < spec.min_speech:
        return False, f"only {a.speech:.2f}s of speech", 0.0
    if a.speech > spec.max_speech:
        return False, f"{a.speech:.2f}s of speech, expected under {spec.max_speech:.2f}s", 0.0
    if spec.want_segments is not None and len(a.segments) != spec.want_segments:
        return False, f"{len(a.segments)} bursts, expected {spec.want_segments}", 0.0
    if spec.min_flatness is not None and a.flatness < spec.min_flatness:
        return False, f"envelope not held (flatness {a.flatness:.2f})", 0.0
    if spec.max_vowel is not None and a.vowel > spec.max_vowel:
        return False, f"{a.vowel:.2f}s of vowel in a sound that has none", 0.0
    return True, "", abs(a.speech - spec.ideal_speech)


def _tail_end(values: list[int], rate: int, a: Analysis) -> int:
    """The last sample with anything in it, judged at [TAIL_FLOOR]."""
    step = max(1, rate * FRAME_MS // 1000)
    floor = (a.peak or 1) * TAIL_FLOOR
    end = a.last
    for start in range(a.last, len(values) - step + 1, step):
        window = values[start : start + step]
        rms = math.sqrt(sum(v * v for v in window) / len(window))
        if rms > floor:
            end = start + step
    return min(len(values), end)


def trim_and_level(values: list[int], rate: int, a: Analysis) -> list[int]:
    """Cut the dead air, match the loudness, and fade the edges.

    The dead air matters more than it sounds like it should. The chef waits
    for each clip to finish before starting the next, so a third of a second
    of silence at the end of every clip becomes a third of a second of silence
    between every word the child hears.
    """
    lead = max(0, a.first - int(LEAD_PAD_MS * rate / 1000))
    tail = min(len(values), _tail_end(values, rate, a) + int(TRAIL_PAD_MS * rate / 1000))
    clip = values[lead:tail]
    if not clip:
        return clip

    rms = math.sqrt(sum(v * v for v in clip) / len(clip)) or 1.0
    gain = (10 ** (TARGET_RMS_DBFS / 20) * 32_767) / rms
    peak = max(abs(v) for v in clip) or 1
    ceiling = 10 ** (CEILING_DBFS / 20) * 32_767
    gain = min(gain, ceiling / peak)
    clip = [int(max(-32_768, min(32_767, round(v * gain)))) for v in clip]

    fade = max(1, int(FADE_MS * rate / 1000))
    for i in range(min(fade, len(clip))):
        clip[i] = int(clip[i] * i / fade)
        clip[-1 - i] = int(clip[-1 - i] * i / fade)
    return clip


def encode_mp3(values: list[int], rate: int) -> bytes:
    import lameenc

    encoder = lameenc.Encoder()
    encoder.set_bit_rate(MP3_BITRATE)
    encoder.set_in_sample_rate(rate)
    encoder.set_channels(1)
    encoder.set_quality(2)
    data = encoder.encode(struct.pack(f"<{len(values)}h", *values))
    return bytes(data) + bytes(encoder.flush())


# --- reading back what actually shipped -------------------------------------
#
# Nothing here can decode an MP3, but an MP3's frame headers carry the sample
# rate, the bit rate and the number of samples, and walking them proves the
# file is a continuous run of valid frames rather than a truncated download or
# an HTML error page with the right first two bytes. That is the difference
# between "the clip is on disk" and "the clip will play in a classroom".

_MPEG_VERSIONS = {0b11: 1, 0b10: 2, 0b00: 25}
_SAMPLE_RATES = {
    1: {0b00: 44_100, 0b01: 48_000, 0b10: 32_000},
    2: {0b00: 22_050, 0b01: 24_000, 0b10: 16_000},
    25: {0b00: 11_025, 0b01: 12_000, 0b10: 8_000},
}
_BITRATES_V1 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
_BITRATES_V2 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]


@dataclass
class Mp3Info:
    seconds: float
    frames: int
    sample_rate: int
    bitrates: set[int]
    channels: int


def read_mp3(data: bytes) -> Mp3Info:
    """Walk every frame. Raises if the file is not one continuous MP3."""
    offset = 0
    if data[:3] == b"ID3":
        size = 0
        for byte in data[6:10]:
            size = (size << 7) | (byte & 0x7F)
        offset = 10 + size
    frames = samples_total = 0
    rate = 0
    bitrates: set[int] = set()
    channels = 1
    while offset + 4 <= len(data):
        header = int.from_bytes(data[offset : offset + 4], "big")
        if header >> 21 != 0x7FF:
            # Trailing tags (ID3v1, APE) are allowed; junk is not.
            if data[offset : offset + 3] in (b"TAG", b"APE") or offset >= len(data) - 4:
                break
            raise TtsError(f"not an MP3 frame at byte {offset}")
        version = _MPEG_VERSIONS.get((header >> 19) & 0b11)
        layer = 4 - ((header >> 17) & 0b11)
        if version is None or layer != 3:
            raise TtsError(f"unsupported MPEG version/layer at byte {offset}")
        bitrate_index = (header >> 12) & 0b1111
        rate_index = (header >> 10) & 0b11
        padding = (header >> 9) & 0b1
        channels = 1 if ((header >> 6) & 0b11) == 0b11 else 2
        table = _BITRATES_V1 if version == 1 else _BITRATES_V2
        if not 0 < bitrate_index < len(table) or rate_index == 0b11:
            raise TtsError(f"reserved bitrate or sample rate at byte {offset}")
        bitrate = table[bitrate_index]
        rate = _SAMPLE_RATES[version][rate_index]
        per_frame = 1152 if version == 1 else 576
        length = (per_frame // 8) * bitrate * 1000 // rate + padding
        if length <= 4:
            raise TtsError(f"impossible frame length at byte {offset}")
        bitrates.add(bitrate)
        samples_total += per_frame
        frames += 1
        offset += length
    if not frames:
        raise TtsError("no MPEG frames at all")
    return Mp3Info(samples_total / rate, frames, rate, bitrates, channels)


# --- listening to it ---------------------------------------------------------
#
# The lesson of the pass before this one: acoustic measurements say whether a
# clip is well formed, not whether it says the right thing. A recording can be
# a textbook unbroken stretch of friction and still be the voice reading out
# "S S S", and every number in this file will call it perfect. The only check
# that would have caught that is reading the clip back.
#
# x.ai's /v1/stt does that, with word-level timings, which also makes it the
# most reliable way to find where a word starts inside a phrase.

import uuid  # noqa: E402


def transcribe(audio: bytes, host: str, token: str, filename="clip.wav") -> dict:
    """Read a clip back. Returns {"text": ..., "words": [{text, start, end}]}."""
    boundary = "----" + uuid.uuid4().hex
    mime = "audio/wav" if audio[:4] == b"RIFF" else "audio/mpeg"
    body = (
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; "
        f"filename=\"{filename}\"\r\nContent-Type: {mime}\r\n\r\n"
    ).encode()
    body += audio + b"\r\n" + f"--{boundary}--\r\n".encode()
    request = urllib.request.Request(
        f"http://{host}/xai/v1/stt",
        data=body,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as error:
        raise TtsError(
            f"stt HTTP {error.code}: {error.read().decode()[:200]}"
        ) from None


def to_wav(values: list[int], rate: int) -> bytes:
    buffer = io.BytesIO()
    writer = wave.open(buffer, "wb")
    writer.setnchannels(1)
    writer.setsampwidth(2)
    writer.setframerate(rate)
    writer.writeframes(struct.pack(f"<{len(values)}h", *values))
    writer.close()
    return buffer.getvalue()


def spoken_words(text: str) -> list[str]:
    """The words of a transcript, lower case, with punctuation dropped."""
    cleaned = "".join(c if c.isalpha() or c.isspace() else " " for c in text.lower())
    return cleaned.split()


def _skeleton(word: str) -> str:
    """A word with its vowels dropped and its spellings regularised.

    The transcriber writes what it hears using ordinary spelling, so "sun"
    comes back as "Son", "ink" as "Inc." and "ball" as "Bull". Those are the
    same word said correctly, and rejecting them would throw away good takes
    all day. What must still be caught is a different word, or half a word —
    "app" for "apple" — so the consonants have to match.
    """
    mapped = []
    for i, c in enumerate(word):
        if c in "aeiou":
            continue
        # Received Pronunciation is non-rhotic, so an "r" that is not in front
        # of a vowel is not a consonant at all: "anchor" is /ˈæŋkə/ and the
        # transcriber quite correctly writes it "Anka". "h" goes the same way
        # — silent in "anchor", and in a digraph the letter in front of it
        # already carries the sound.
        if c == "r" and (i + 1 >= len(word) or word[i + 1] not in "aeiou"):
            continue
        if c == "h":
            continue
        if c == "c":
            c = "s" if i + 1 < len(word) and word[i + 1] in "ei" else "k"
        elif c in "qx":
            c = "k"
        elif c == "z":
            c = "s"
        elif c == "y":
            continue
        if mapped and mapped[-1] == c:
            continue
        mapped.append(c)
    return "".join(mapped)


def _edits(a: str, b: str) -> int:
    """Levenshtein distance, for the one-letter cases the skeleton misses."""
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(
                min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (ca != cb))
            )
        previous = current
    return previous[-1]


def sounds_like(heard: str, expected: str) -> bool:
    """Whether a transcript word is the word that was asked for."""
    heard, expected = heard.lower(), expected.lower()
    if heard == expected:
        return True
    if _skeleton(heard) == _skeleton(expected):
        return True
    return _edits(heard, expected) <= 1 and heard[:1] == expected[:1]


# Letter names, as a transcriber writes them. A pure-sound clip that reads
# back as one of these is the letter name being taught as the sound — which is
# the single defect this whole pipeline exists to prevent.
LETTER_NAMES = {
    "a", "ay", "b", "bee", "c", "cee", "d", "dee", "e", "ee", "f", "ef",
    "g", "gee", "h", "aitch", "i", "j", "jay", "k", "kay", "l", "el",
    "m", "em", "n", "en", "o", "oh", "p", "pee", "q", "queue", "r", "ar",
    "s", "es", "ess", "t", "tea", "tee", "u", "you", "v", "vee",
    "w", "x", "ex", "y", "why", "z", "zed", "zee",
}

# The added vowel, as a transcriber writes it. "Buh" for /b/ is precisely what
# Letters and Sounds Phase One says never to model.
ADDED_VOWEL_ENDINGS = ("uh", "ah", "er")
