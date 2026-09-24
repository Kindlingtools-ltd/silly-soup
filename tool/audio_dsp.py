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

    A nasal murmur or a vowel is periodic, so it lengthens by repeating a
    whole number of pitch periods: cut the loop on a period boundary and the
    waveform either side of the join has the same shape, so there is no join
    to hear.

    The length of the crossfade is the whole game here, and getting it wrong
    is worse than having none. A pitch period is about 4.5 ms; an 8 ms
    crossfade therefore overlaps 1.8 periods, which lands the two copies out
    of phase and makes them cancel. That put a 9 to 23 dB hole in the sound
    at every join — an amplitude dip repeating every 40 to 65 ms, which is
    modulation at 15 to 24 Hz, right in the band the ear hears as roughness.
    It sounded like static sitting inside the vowel.

    So the repeats are butt-joined on exact period boundaries and not
    crossfaded at all. Aligned that way the waveform simply continues.
    """
    target = int(seconds * SR)
    if len(x) < 240 or target <= len(x):
        return x.copy()

    # Loop the steady middle, not the transitions at either edge.
    core = x[int(len(x) * 0.25):int(len(x) * 0.85)] if len(x) > 600 else x
    period = period_of(core)
    if period <= 0 or period * 2 > len(core):
        # No usable pitch: fall back to a crossfade, which is at least smooth.
        body = core
        out = x[:len(x) // 2].copy()
        while len(out) < target:
            out = splice(out, body, cross_ms=8)
        return out[:target]

    repeats = max(int(len(core) // period), 1)
    body = core[:repeats * period]

    # Keep the sound's own attack, then run on with whole copies of the body.
    # The body has to start at the phase the attack ended on, or that one
    # junction is a step in the middle of a waveform — so rotate it until it
    # lines up. Every join after that is exact, because the body is a whole
    # number of periods and tiling it just continues the waveform.
    attack = x[:int(len(x) * 0.25)]
    if len(attack) > period:
        tail = attack[-period:]
        offset = int(np.argmax([
            float(np.dot(tail, np.roll(body, -lag)[:period]))
            for lag in range(period)
        ]))
        body = np.roll(body, -offset)
    else:
        attack = x[:0]
    tiles = int(np.ceil((target - len(attack)) / len(body))) + 1
    return np.concatenate([attack, np.tile(body, tiles)])[:target]


def hold_noise(x: np.ndarray, seconds: float, seed: int = 7) -> np.ndarray:
    """Lengthen a hiss by tiling it, from its steady middle.

    A fricative is noise, and the similarity search a time-stretcher uses is
    the wrong tool for noise: lining windows up by correlation imposes a
    period on something that has none, and the held /s/ picks up a buzz.
    Taking the windows from random places keeps it hissing.

    Two details it goes wrong without. The tiles come from the middle of the
    sound rather than anywhere in it, because an /s/ ramps up at the start
    and is already bending towards the vowel at the end, and tiles taken from
    those ends make the hiss wobble. And the joins are equal-power, because
    two uncorrelated pieces of noise do not add in amplitude — a straight
    crossfade leaves a 3 dB dip at every join, which flutters.
    """
    target = int(seconds * SR)
    if len(x) < 480 or target <= len(x):
        return x.copy()
    middle = x[int(len(x) * 0.30):int(len(x) * 0.95)]
    if len(middle) < 240:
        middle = x
    rng = np.random.default_rng(seed)
    win = min(len(middle), int(0.06 * SR))
    cross_ms = 12.0
    out = x[:int(len(x) * 0.30)] if len(x) > 800 else middle[:win]
    while len(out) < target:
        start = int(rng.integers(0, max(len(middle) - win, 1)))
        out = splice(out, middle[start:start + win], cross_ms=cross_ms, equal_power=True)
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


def splice(head: np.ndarray, tail: np.ndarray, cross_ms: float = 10,
           equal_power: bool = False) -> np.ndarray:
    """Join two pieces with a short crossfade so the seam does not click.

    `equal_power` matters when the two sides are uncorrelated — two pieces of
    hiss, say. A straight fade adds their amplitudes, and uncorrelated
    amplitudes do not add: the sum sits 3 dB down in the middle of every
    crossfade, so a tiled hiss flutters at the tiling rate. Fading by the
    square root keeps the power constant instead.
    """
    n = int(SR * cross_ms / 1000)
    if n == 0 or len(head) < n or len(tail) < n:
        return np.concatenate([head, tail])
    ramp = np.linspace(0, 1, n)
    down, up = (np.sqrt(1 - ramp), np.sqrt(ramp)) if equal_power else (1 - ramp, ramp)
    middle = head[-n:] * down + tail[:n] * up
    return np.concatenate([head[:-n], middle, tail[n:]])


def a_weighted_level(x: np.ndarray) -> float:
    """Roughly how loud this sounds, in dB. Not how tall its waveform is.

    Peak height is the wrong measure for a set of clips that includes both
    vowels and hisses. Matching peaks left the nine pure sounds 15 dB apart
    to the ear — /t/ shouting and /b/ almost inaudible — because the ear is
    far more sensitive around 2-6 kHz, which is exactly where a /t/ release
    sits and a /b/ release does not.
    """
    if len(x) < 240:
        return -120.0
    energy, hop = _rms(x)
    if not len(energy):
        return -120.0
    live = np.flatnonzero(energy > max(0.08 * energy.max(), 0.01))
    if not len(live):
        return -120.0
    # Judge the clip on the part of it that makes a sound, so a bounced stop
    # is not marked quiet for the silence between its taps.
    sounding = np.concatenate([x[int(i * hop):int(i * hop) + 240] for i in live])
    power = np.abs(np.fft.rfft(sounding * np.hanning(len(sounding)))) ** 2
    freqs = np.maximum(np.fft.rfftfreq(len(sounding), 1 / SR), 1e-6)
    ra = (12194 ** 2 * freqs ** 4) / (
        (freqs ** 2 + 20.6 ** 2)
        * np.sqrt((freqs ** 2 + 107.7 ** 2) * (freqs ** 2 + 737.9 ** 2))
        * (freqs ** 2 + 12194 ** 2)
    )
    weighted = power * 10 ** ((20 * np.log10(ra) + 2.0) / 10)
    # Parseval: the power spectrum sums to N times the signal's total energy,
    # so mean power is that sum over N squared. Dividing by N once instead
    # made the number grow with the length of the clip, which quietly turned
    # "match the loudness" into "punish the long ones".
    return float(10 * np.log10(max(weighted.sum() / len(sounding) ** 2, 1e-20)))


# Chosen from the clips themselves: the loudness three quarters of them can
# reach before their peak hits the ceiling. Aiming higher would only mean
# more clips stopping short of the target, which is the spread we are trying
# to remove.
TARGET_LOUDNESS_DB = -27.5


def normalise(x: np.ndarray, target_db: float = TARGET_LOUDNESS_DB,
              ceiling: float = 0.89) -> np.ndarray:
    """Bring a clip to a common loudness, without letting it clip.

    `ceiling` is a limit, not a goal: a clip that would have to go over it to
    reach the target simply stops there. That is the right way round — a clip
    slightly under the target is quiet, a clip over full scale is distorted.
    """
    if not len(x):
        return x
    gain = 10 ** ((target_db - a_weighted_level(x)) / 20)
    loudest = float(np.max(np.abs(x)))
    if loudest > 1e-9:
        gain = min(gain, ceiling / loudest)
    return x * gain


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


def roughness(x: np.ndarray) -> float:
    """How much the clip's level flutters, as a percentage, in the 10-40 Hz band.

    This is the measurement that found the bug this module was shipped with.
    A held sound is supposed to be steady; a loop whose crossfade does not
    line up with the pitch cancels a little at every join, and the result is
    a level dip repeating at the loop rate. Between roughly 15 and 75 Hz the
    ear does not hear that as separate events — it hears one harsh, buzzing
    sound. It was described, fairly, as static.

    Only meaningful for sounds that are meant to be continuous. A bounced
    stop is three taps with gaps, so it modulates by design and scores
    enormously; do not ask this about one.
    """
    window, hop = 480, 120  # 20 ms window: averages out the pitch, keeps the flutter
    if len(x) < window * 8:
        return 0.0
    envelope = np.array([
        np.sqrt(np.mean(x[i:i + window] ** 2))
        for i in range(0, len(x) - window, hop)
    ])
    core = envelope[int(len(envelope) * 0.15):int(len(envelope) * 0.85)]
    if len(core) < 24 or core.mean() <= 0:
        return 0.0
    envelope_sr = SR / hop
    spectrum = np.abs(np.fft.rfft((core - core.mean()) * np.hanning(len(core))))
    freqs = np.fft.rfftfreq(len(core), 1 / envelope_sr)
    band = (freqs >= 10) & (freqs <= 40)
    if not band.any():
        return 0.0
    # Parseval, back to an RMS in the band, against the clip's own level.
    rms_in_band = np.sqrt(2 * np.sum(spectrum[band] ** 2)) / len(core)
    return float(100 * rms_in_band / core.mean())
