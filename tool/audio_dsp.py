"""Cut a phoneme out of a spoken word, and hold it on without wrecking it.

Why this exists: the speech engine cannot say a phoneme. Asked for `sss` it
says the letter name "S S S"; asked for `b` it says "B"; asked for `b b b` it
says "Buh buh buh", which is the one thing Letters and Sounds Phase One tells
you never to model. IPA length marks and the `speed` parameter are accepted
and ignored, so `/sːːʌn/` comes back as plain "sun". Every route through the
API was tried and transcribed; none of them works.

What does work is what an adult does. Say the word, then hold on to the sound
it starts with: "sssun — sss". So the engine is only ever asked for ordinary
words, and the sound is cut out of one.

The hard part is lengthening it. Repeating a chunk of a *voiced* sound at an
arbitrary offset puts a step in the waveform every time it wraps, and a step
in a periodic signal is a click — a run of them is the buzz you hear as
static. Noise can be spliced anywhere; anything with a pitch has to be
spliced a whole number of pitch periods along. That distinction is the whole
of `_lengthen`.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

FRAME_MS = 5
# A hiss crosses zero far more often than a vowel does. The gap between the
# two is wide, so this threshold does not need to be delicate.
FRICATIVE_ZCR = 0.18
# Under this share of the loudest frame is closure or silence, not a sound.
QUIET = 0.10


@dataclass
class Frames:
    """Per-frame measurements of one clip, at FRAME_MS resolution."""

    rms: list[float]
    zcr: list[float]
    tilt: list[float]
    step: int
    rate: int

    @property
    def peak(self) -> float:
        return max(self.rms) or 1.0

    def at(self, index: int) -> int:
        """Sample offset of frame [index]."""
        return index * self.step


def measure(values: list[int], rate: int) -> Frames:
    step = max(1, rate * FRAME_MS // 1000)
    rms: list[float] = []
    zcr: list[float] = []
    tilt: list[float] = []
    for start in range(0, max(1, len(values) - step + 1), step):
        window = values[start : start + step]
        n = len(window)
        rms.append(math.sqrt(sum(v * v for v in window) / n))
        zcr.append(
            sum(1 for a, b in zip(window, window[1:]) if (a >= 0) != (b >= 0))
            / max(1, n - 1)
        )
        # Spectral tilt, the cheap way: a one-tap difference is a high-pass,
        # so comparing its energy with the signal's says how bright the frame
        # is. A nasal is dark, the vowel after it is brighter, and that is
        # what separates the /n/ in "nest" from the /e/ — they are both
        # voiced, so zero crossings cannot tell them apart.
        high = math.sqrt(
            sum((b - a) ** 2 for a, b in zip(window, window[1:])) / max(1, n - 1)
        )
        tilt.append(high / (rms[-1] or 1.0))
    return Frames(rms=rms, zcr=zcr, tilt=tilt, step=step, rate=rate)


def _first_loud(f: Frames) -> int:
    floor = f.peak * QUIET
    for i, level in enumerate(f.rms):
        if level > floor:
            return i
    return 0


# A phoneme shorter than this is a transient, not a sound worth holding on
# to; longer than this and the cut has run into the rest of the word.
MIN_ONSET_MS = 35
MAX_ONSET_MS = 200


def onset_span(f: Frames, manner: str) -> tuple[int, int]:
    """Frame range covering the word's first phoneme.

    `manner` is `fricative`, `nasal`, `vowel` or `stop` — the bank knows which
    because it knows the sound, and working it out from the audio when the
    answer is already in the data would only add a way to be wrong.

    Raises ValueError when the answer is not credible. A cut that is five
    milliseconds long, or that has swallowed half the word, has to fail
    loudly: silently lengthening the wrong piece of audio produces a clip
    that measures perfectly and teaches the wrong sound.
    """
    start = _first_loud(f)
    n = len(f.rms)
    floor = f.peak * QUIET
    lo = max(1, MIN_ONSET_MS // FRAME_MS)
    hi = max(lo + 1, MAX_ONSET_MS // FRAME_MS)

    if manner == "stop":
        # A stop is a closure and then a burst. There is nothing to hold on
        # to — the burst *is* the sound. It is taken with the barest onset of
        # voicing after it; any more of that and it becomes "buh".
        return start, start + 1

    if manner == "fricative":
        # Ends where the voice switches on: zero crossings fall away.
        i = start
        while i < n and f.zcr[i] >= FRICATIVE_ZCR:
            i += 1
    elif manner == "nasal":
        # Voiced, so zero crossings cannot see the boundary. A nasal is
        # markedly quieter and darker than the vowel that follows it, so the
        # boundary is the first sustained rise. Compared against the opening
        # of the nasal rather than one frame of it, because a single frame at
        # a voicing onset is not a reliable baseline — measuring from one is
        # what made this return five milliseconds.
        window = f.rms[start : start + lo] or [f.peak]
        quiet = sorted(window)[len(window) // 2]
        dark = sorted(f.tilt[start : start + lo] or [0.0])
        base_tilt = dark[len(dark) // 2]
        i = start + lo
        while i < n:
            rising = f.rms[i] > quiet * 1.7 and f.rms[min(i + 1, n - 1)] > quiet * 1.7
            brighter = f.tilt[i] > base_tilt * 1.8
            if rising or brighter:
                break
            i += 1
    elif manner == "vowel":
        # Ends where the next consonant closes it down.
        i = start + lo
        while i < n and f.rms[i] > floor * 1.5:
            i += 1
    else:
        raise ValueError(f"unknown manner {manner!r}")

    length = i - start
    if length < lo:
        raise ValueError(
            f"{manner} onset measured only {length * FRAME_MS} ms — too short "
            f"to be the sound"
        )
    return start, start + min(length, hi)


def period(values: list[int], rate: int, fmin: int = 70, fmax: int = 400) -> int:
    """Pitch period in samples, or 0 when the segment is not periodic.

    A splice has to land a whole number of these along, or it clicks.

    The correlation is normalised over the overlapping part only. Dividing by
    the whole window's energy instead biases long lags downwards — enough to
    report every voiced sound in this bank as unpitched, which silently sends
    them all down the noise path.
    """
    lo, hi = rate // fmax, rate // fmin
    if len(values) < lo * 3:
        return 0
    hi = min(hi, len(values) // 2)
    if hi <= lo:
        return 0
    scores = []
    for lag in range(lo, hi):
        overlap = len(values) - lag
        num = sum(values[i] * values[i + lag] for i in range(overlap))
        a = sum(values[i] * values[i] for i in range(overlap))
        b = sum(values[i + lag] * values[i + lag] for i in range(overlap))
        denom = math.sqrt(a * b) or 1.0
        scores.append((lag, num / denom))
    if not scores:
        return 0
    best = max(score for _, score in scores)
    if best <= 0.5:
        return 0
    # The smallest lag that correlates about as well as the best one. A signal
    # correlates with itself just as strongly at twice its period as at its
    # period, and taking the highest score alone returns the multiple often
    # enough to matter: the loop is then twice as long as it needs to be, and
    # on a short cut there may not be room for two of them.
    for lag, score in scores:
        if score >= best * 0.99:
            return lag
    return 0


def _steadiest(segment: list[int], width: int, rate: int) -> list[int]:
    """The least changeable stretch of [segment], [width] samples long.

    Looping the middle of the cut is not good enough. Phoneme boundaries are
    not clean — the detector routinely takes a little of the vowel that
    follows — and a loop that straddles the transition repeats the transition,
    which is heard as a wobble however carefully it is spliced. So the loop
    material is the flattest window available, searched over the earlier part
    of the cut where the sound itself is least likely to have ended.
    """
    width = min(width, len(segment))
    if width <= 0:
        return segment
    # Only the front of the cut: the back is where a boundary error lives.
    limit = max(width, int(len(segment) * 0.7))
    step = max(1, rate // 500)  # 2 ms
    frame = max(1, rate * 5 // 1000)

    def spread(start: int) -> float:
        levels = []
        for i in range(start, start + width - frame + 1, frame):
            w = segment[i : i + frame]
            levels.append(math.sqrt(sum(v * v for v in w) / len(w)))
        if len(levels) < 2:
            return 0.0
        loudest = max(levels) or 1.0
        return (loudest - min(levels)) / loudest

    best, best_at = None, 0
    for start in range(0, max(1, limit - width + 1), step):
        score = spread(start)
        if best is None or score < best:
            best, best_at = score, start
    return segment[best_at : best_at + width]


def _crossfade(a: list[int], b: list[int], overlap: int) -> list[int]:
    """Join two segments with a raised-cosine overlap, so there is no step."""
    if overlap <= 0 or overlap > min(len(a), len(b)):
        return a + b
    out = a[: len(a) - overlap]
    for i in range(overlap):
        w = 0.5 - 0.5 * math.cos(math.pi * i / overlap)
        out.append(int(a[len(a) - overlap + i] * (1 - w) + b[i] * w))
    return out + b[overlap:]


def envelope_ripple(values: list[int], rate: int, skip_ms: int = 0) -> float:
    """How much the loudness wobbles across a held sound, 0 is dead steady.

    This is the artifact a cross-fade does not prevent. Overlapping two copies
    of a *voiced* sound that are out of phase makes them cancel where they
    meet, so the level dips once per splice. There is no click to find — the
    waveform is perfectly continuous — but a run of dips is heard as a warble
    or a rasp. Looping a whole number of pitch periods is what stops it, and
    this is how you can tell whether it worked.
    """
    step = max(1, rate * 20 // 1000)
    body = values[rate * skip_ms // 1000 :]
    levels = []
    for start in range(0, max(1, len(body) - step + 1), step):
        window = body[start : start + step]
        levels.append(math.sqrt(sum(v * v for v in window) / len(window)))
    if len(levels) < 3:
        return 0.0
    # Ignore the fade in and out at the ends.
    levels = levels[1:-1] or levels
    loudest = max(levels) or 1.0
    return 1.0 - (min(levels) / loudest)


def hold(segment: list[int], rate: int, target_ms: int, voiced: bool) -> list[int]:
    """Hold a sound on for [target_ms], built out of its own steadiest part.

    Not by growing the original: the original carries its onset ramp and,
    often, a little of whatever came next, and repeating that repeats the
    change in it. What gets repeated here is the flattest window in the cut,
    spliced to itself — a whole number of pitch periods along when the sound
    is voiced, anywhere at all when it is noise.
    """
    target = rate * target_ms // 1000
    if len(segment) < rate // 100:  # under 10 ms there is nothing to loop
        return segment[:target]

    t = period(segment, rate) if voiced else 0
    if voiced and t == 0:
        voiced = False

    if voiced:
        periods = max(2, min(6, len(segment) // t))
        loop = _steadiest(segment, periods * t, rate)
        overlap = t
    else:
        loop = _steadiest(segment, min(len(segment), rate * 60 // 1000), rate)
        overlap = min(len(loop) // 2, rate * 20 // 1000)

    out = list(loop)
    guard = 0
    while len(out) < target and guard < 400:
        out = _crossfade(out, loop, overlap)
        guard += 1
    return out[:target]


def stretch_onset(
    word: list[int],
    rate: int,
    span: tuple[int, int],
    target_ms: int,
    voiced: bool,
) -> list[int]:
    """The same word with its first sound held on: "sun" becomes "sssun".

    The word's own start and its own transition into the vowel are kept —
    only the steady middle of the first sound is stretched. That is what makes
    it still sound like one person saying one word, rather than two clips
    stuck together.
    """
    s0, s1 = span
    onset = word[s0:s1]
    # Keep the last of the onset: that is where it moves into the vowel, and
    # cutting it off is what turns "a nest" into something else.
    tail = min(len(onset), rate * 40 // 1000)
    body_ms = max(0, target_ms - tail * 1000 // rate)
    body = hold(onset[: len(onset) - tail] or onset, rate, body_ms, voiced)
    joined = _crossfade(body, onset[len(onset) - tail :], min(tail, rate * 15 // 1000))
    return word[:s0] + joined + word[s1:]


def lengthen(segment: list[int], rate: int, target_ms: int, voiced: bool) -> list[int]:
    """Kept as the name the tests use; [hold] is the implementation."""
    return hold(segment, rate, target_ms, voiced)
