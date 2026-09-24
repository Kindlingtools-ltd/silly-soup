"""Shaping ordinary speech into phonics audio.

The app used to hand the text-to-speech engine its phonics notation and hope:
`sss`, `sssun`, `b-b-banana`. An engine reads those as spelling, so they came
back as "S S S", "Son" and "Buh buh banana" — letter names, a lost stretch,
and an added "uh". Modelling "buh" is the single mistake Letters and Sounds
Phase One tells you never to make, so the app was teaching the opposite of
what it exists to teach.

Nothing here asks the engine for a pure sound. It asks for an ordinary word
and then works on the waveform: find where the word's first phoneme ends, and
either hold that phoneme on (a continuant: "sssun") or bounce it
(a stop: "b-b-banana"). The stretched /s/ is the very /s/ the engine said at
the front of "sun" — same voice, same pitch, same recording, just held on,
which is exactly what an adult does when they model a sound.

The boundary is found acoustically rather than guessed from spelling, and
every clip is measured afterwards: a stop that has picked up a vowel shows up
as voiced energy where there should be none, and the audit fails on it.
"""

from __future__ import annotations

import os
import subprocess
import tempfile

import numpy as np

SR = 24000  # what the speech API returns; kept end to end, no resampling


# --------------------------------------------------------------- containers


def decode(path: str, sr: int = SR) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"],
        capture_output=True,
        check=True,
    ).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def encode(x: np.ndarray, path: str, sr: int = SR, bitrate: str = "48k") -> None:
    """Write mono MP3.

    48 kbit/s mono is transparent for a single voice and a third the size of
    the 128 kbit/s the API hands back. There are several hundred of these and
    the app fetches them over the network, so the difference is the child
    waiting or not waiting.
    """
    x = np.clip(x, -1.0, 1.0).astype(np.float32)
    with tempfile.NamedTemporaryFile(suffix=".f32", delete=False) as handle:
        handle.write(x.tobytes())
        tmp = handle.name
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    try:
        subprocess.run(
            ["ffmpeg", "-y", "-v", "error", "-f", "f32le", "-ar", str(sr), "-ac", "1",
             "-i", tmp, "-codec:a", "libmp3lame", "-b:a", bitrate, path],
            check=True,
        )
    finally:
        os.unlink(tmp)


# ---------------------------------------------------------------- analysis


def _rms(x: np.ndarray, win: int = 240, hop: int = 120):
    n = max((len(x) - win) // hop + 1, 0)
    return np.array([np.sqrt(np.mean(x[i * hop:i * hop + win] ** 2)) for i in range(n)]), hop


def _voicing(x: np.ndarray, win: int = 480, hop: int = 120):
    """Per frame: how periodic it is, and how bass-heavy it is.

    Periodicity separates a vowel from a hiss; the band ratio separates a
    nasal murmur (almost nothing above 3 kHz) from the vowel after it.
    """
    n = max((len(x) - win) // hop + 1, 0)
    periodicity, ratio = np.zeros(n), np.zeros(n)
    freqs = np.fft.rfftfreq(win, 1 / SR)
    window = np.hanning(win)
    for i in range(n):
        frame = x[i * hop:i * hop + win]
        frame = frame - np.mean(frame)
        if np.sqrt(np.mean(frame ** 2)) < 1e-4:
            continue
        auto = np.correlate(frame, frame, "full")[win - 1:]
        lo, hi = SR // 400, min(SR // 70, win - 1)  # 70-400 Hz, a speaking range
        if hi > lo and auto[0] > 0:
            periodicity[i] = np.max(auto[lo:hi]) / auto[0]
        power = np.abs(np.fft.rfft(frame * window)) ** 2
        ratio[i] = power[freqs < 1000].sum() / (power[freqs > 3000].sum() + 1e-12)
    return periodicity, ratio, hop


def trim(x: np.ndarray, lead_ms: float = 20, tail_ms: float = 45) -> np.ndarray:
    """Cut the dead air the engine leaves at both ends.

    It returns clips with up to a third of a second of silence on the end.
    That is a third of a second of the chef apparently saying nothing after
    every single ingredient, and it makes chaining clips into a list
    impossible.
    """
    energy, hop = _rms(x)
    if not len(energy):
        return x
    peak = energy.max()
    loud = np.flatnonzero(energy > max(0.02, 0.06 * peak))
    if not len(loud):
        return x

    # A word ending in /t/ or /p/ goes quiet for the closure and then releases
    # in a short, faint burst — "ant" loses its /t/ and becomes "an" if the cut
    # is made at the last loud frame. So having found that frame, keep walking
    # forward over anything still audible within a closure's length of it.
    last = int(loud[-1])
    reach = int(0.25 * SR / hop)
    faint = max(0.008, 0.015 * peak)
    while True:
        window = energy[last + 1:last + 1 + reach]
        later = np.flatnonzero(window > faint)
        if not len(later):
            break
        last = last + 1 + int(later[-1])

    a = max(int(loud[0] * hop) - int(SR * lead_ms / 1000), 0)
    b = min(int(last * hop + 240) + int(SR * tail_ms / 1000), len(x))
    return x[a:b]


def onset_end(x: np.ndarray, kind: str) -> int:
    """Sample index where the word's first phoneme gives way to what follows."""
    periodicity, ratio, hop = _voicing(x)
    energy, ehop = _rms(x)
    if not len(periodicity) or not len(energy):
        return int(0.08 * SR)
    peak = energy.max()

    def band(i: int) -> float:
        return ratio[min(int(i * ehop // hop), len(ratio) - 1)]

    def period(i: int) -> float:
        return periodicity[min(int(i * ehop // hop), len(periodicity) - 1)]

    if kind == "fricative":
        # /s/ is unvoiced hiss. It ends the moment the voice switches on.
        for i in range(len(periodicity)):
            if periodicity[i] > 0.42 and ratio[i] > 1.0:
                return int(i * hop)
        return int(0.12 * SR)

    if kind == "stop":
        # Closure (near silence), a burst, then a vowel.
        #
        # Loudness alone cannot mark the end of the burst. After /b/ the vowel
        # swells slowly, so "louder than half the peak" lands well inside it;
        # after /t/ the burst itself is loud, so the same rule lands before
        # the aspiration has finished. The vowel is the first thing that is
        # both properly periodic and properly loud — a voiced stop's murmur
        # during closure is periodic but quiet, so it does not qualify.
        #
        # The cap matters more than the search. A stop release in English runs
        # 10-90 ms, and aspiration takes it to about 150; past that the clip
        # has a vowel in it whatever the measurements say, and a vowel is the
        # "uh" we are here to prevent.
        floor_, cap = int(0.025 * SR), int(0.15 * SR)
        start = int(np.argmax(energy > 0.10 * peak))
        for i in range(start, len(energy)):
            if period(i) > 0.50 and energy[i] > 0.35 * peak:
                return int(min(max(i * ehop, floor_), cap))
        return cap

    if kind == "nasal":
        # /m/ and /n/ are voiced, so voicing cannot mark the boundary. The
        # murmur is quiet and bass-heavy; the vowel is loud and is not.
        start = int(np.argmax(energy > 0.10 * peak))
        for i in range(start, len(energy)):
            if energy[i] > 0.62 * peak and band(i) < 12:
                return int(i * ehop)
        return int(0.09 * SR)

    if kind == "vowel":
        # The word opens on the vowel: hold the first loud, periodic run.
        strong = [energy[i] > 0.45 * peak and period(i) > 0.40 for i in range(len(energy))]
        if True in strong:
            first = strong.index(True)
            last = first
            while last < len(strong) and strong[last]:
                last += 1
            if (last - first) * ehop > 0.05 * SR:
                return int(last * ehop)
        return int(min(0.18 * SR, len(x) * 0.5))

    return int(0.09 * SR)


# ----------------------------------------------------------------- shaping


def period_of(x: np.ndarray) -> int:
    """Length of one pitch period, in samples."""
    frame = x - np.mean(x)
    auto = np.correlate(frame, frame, "full")[len(frame) - 1:]
    lo, hi = SR // 400, min(SR // 70, len(auto) - 1)   # 70-400 Hz
    if hi <= lo:
        return 0
    return int(lo + np.argmax(auto[lo:hi]))


def hold(x: np.ndarray, seconds: float) -> np.ndarray:
    """Hold a voiced sound on, at its own pitch.

    A nasal murmur or a vowel is periodic, so it lengthens cleanly by
    repeating a whole number of pitch periods: cut the loop on a period
    boundary and the join is inaudible, because the waveform on either side
    of it is the same shape. Cut it anywhere else and it clicks once per
    repeat.

    These segments are short — an /m/ is about 90 ms — so there is no room
    for the sliding-window search a general time-stretcher would use.
    """
    target = int(seconds * SR)
    if len(x) < 240 or target <= len(x):
        return x.copy()

    # Loop the steady middle, not the transitions at either edge.
    core = x[int(len(x) * 0.25):int(len(x) * 0.85)] if len(x) > 600 else x
    period = period_of(core)
    if period <= 0 or period * 2 > len(core):
        body = core
    else:
        repeats = max(int(len(core) // period), 1)
        body = core[:repeats * period]

    out = x[:len(x) // 2].copy()
    cross = min(int(0.008 * SR), len(body) // 3)
    while len(out) < target:
        out = splice(out, body, cross_ms=1000 * cross / SR)
    return out[:target]


def hold_noise(x: np.ndarray, seconds: float, seed: int = 7) -> np.ndarray:
    """Lengthen a hiss by tiling it from random offsets.

    A fricative is noise, and the similarity search in `hold` is the wrong
    tool for noise: lining windows up by correlation imposes a period on
    something that has none, and the held /s/ picks up an audible buzz. Taking
    the windows from random places keeps it hissing.
    """
    target = int(seconds * SR)
    if len(x) < 480 or target <= len(x):
        return x.copy()
    rng = np.random.default_rng(seed)
    win = min(len(x), int(0.06 * SR))
    cross = int(0.015 * SR)
    out = x[:len(x) - cross].copy()
    while len(out) < target:
        start = int(rng.integers(0, max(len(x) - win, 1)))
        out = splice(out, x[start:start + win], cross_ms=1000 * cross / SR)
    return out[:target]


def fade(x: np.ndarray, in_ms: float = 8, out_ms: float = 25) -> np.ndarray:
    x = x.copy()
    a, b = int(SR * in_ms / 1000), int(SR * out_ms / 1000)
    if a and len(x) > a:
        x[:a] *= np.linspace(0, 1, a)
    if b and len(x) > b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def silence(ms: float) -> np.ndarray:
    return np.zeros(int(SR * ms / 1000))


def splice(head: np.ndarray, tail: np.ndarray, cross_ms: float = 10) -> np.ndarray:
    """Join two pieces with a short crossfade so the seam does not click."""
    n = int(SR * cross_ms / 1000)
    if n == 0 or len(head) < n or len(tail) < n:
        return np.concatenate([head, tail])
    ramp = np.linspace(0, 1, n)
    middle = head[-n:] * (1 - ramp) + tail[:n] * ramp
    return np.concatenate([head[:-n], middle, tail[n:]])


def normalise(x: np.ndarray, peak: float = 0.89) -> np.ndarray:
    """Even loudness across every clip, so no line makes a child jump."""
    loudest = float(np.max(np.abs(x))) if len(x) else 0.0
    return x * (peak / loudest) if loudest > 1e-9 else x


# ---------------------------------------------------------------- measuring


def describe(x: np.ndarray) -> dict:
    """The few numbers that say what a clip actually is.

    `voiced` is the one that matters most: a pure stop must be a burst of air
    with no vowel behind it, so anything much above zero means the clip has
    picked up the "uh" this whole module exists to prevent.
    """
    if len(x) < 480:
        return {"duration": len(x) / SR, "voiced": 0.0, "centroid": 0.0,
                "peak": float(np.max(np.abs(x))) if len(x) else 0.0}
    periodicity, _, hop = _voicing(x)
    energy, ehop = _rms(x)
    floor = max(0.08 * energy.max(), 0.01)
    voiced = [periodicity[min(int(i * ehop // hop), len(periodicity) - 1)] > 0.45
              for i in range(len(energy)) if energy[i] > floor]
    power = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    return {
        "duration": len(x) / SR,
        "voiced": float(np.mean(voiced)) if voiced else 0.0,
        "centroid": float((power * freqs).sum() / max(power.sum(), 1e-12)),
        "peak": float(np.max(np.abs(x))),
    }


def trim_stop_onset(word: np.ndarray, boundary: int, ceiling: float = 0.25) -> int:
    """Pull a stop's boundary back until no vowel is left in it.

    `onset_end` finds where the burst gives way to the vowel, and on a short
    word it can land a little late — enough of "tap" to be heard as "tap"
    rather than as /t/, so bouncing it produced "tap, tap, tap" instead of
    "t-t-tap". Measuring the segment settles it: a stop release carries almost
    no periodic energy, so anything voiced in there is vowel, and the boundary
    comes back until it is gone.
    """
    floor_ = int(0.025 * SR)
    while boundary > floor_ and describe(word[:boundary])["voiced"] > ceiling:
        boundary -= int(0.01 * SR)
    return max(boundary, floor_)
