"""Tests for the audio build tools.

    python3 -m unittest discover -s tool -p 'test_*.py'

These cover the decisions that determine whether a clip ships: whether a
transcript counts as the right word, where a phoneme ends, and whether holding
a sound on leaves a seam in it. No network, no API.
"""

import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from audio_dsp import (  # noqa: E402
    FRAME_MS,
    _crossfade,
    envelope_ripple,
    hold,
    measure,
    onset_span,
    period,
)
from audio_pipeline import (  # noqa: E402
    ADDED_VOWEL_ENDINGS,
    LETTER_NAMES,
    sounds_like,
    spoken_words,
)

RATE = 24_000


def tone(hz, ms, amplitude=8000, rate=RATE):
    n = rate * ms // 1000
    return [int(amplitude * math.sin(2 * math.pi * hz * i / rate)) for i in range(n)]


def noise(ms, amplitude=6000, rate=RATE, seed=1):
    # A deterministic pseudo-noise, so the tests do not wobble.
    out, x = [], seed
    for _ in range(rate * ms // 1000):
        x = (1103515245 * x + 12345) % (1 << 31)
        out.append(int((x / (1 << 30) - 1.0) * amplitude))
    return out


def silence(ms, rate=RATE):
    return [0] * (rate * ms // 1000)


class TranscriptMatching(unittest.TestCase):
    """The transcriber writes what it hears in ordinary spelling, which is not
    always the spelling that was asked for. Accepting its spelling is what
    keeps good takes; rejecting a different word is what keeps the audio
    honest."""

    def test_accepts_the_transcribers_own_spelling(self):
        for heard, expected in [
            ("son", "sun"),
            ("inc", "ink"),
            ("bull", "ball"),
            ("pun", "pan"),
            ("anka", "anchor"),  # non-rhotic: /ˈæŋkə/
            ("paya", "pear"),  # non-rhotic: /peə/
            ("abia", "abear"),
        ]:
            self.assertTrue(sounds_like(heard, expected), f"{heard} ~ {expected}")

    def test_rejects_a_different_word_or_half_a_word(self):
        for heard, expected in [
            ("app", "apple"),  # the word got truncated
            ("nurse", "nest"),  # a long /n/ really does do this
            ("suit", "soup"),
            ("dog", "duck"),
            ("muck", "milk"),
            ("egg", "ink"),
        ]:
            self.assertFalse(sounds_like(heard, expected), f"{heard} !~ {expected}")

    def test_letter_names_and_added_vowels_are_named(self):
        # The two ways a pure sound goes wrong, as a transcriber spells them.
        self.assertIn("ess", LETTER_NAMES)
        self.assertIn("tee", LETTER_NAMES)
        self.assertTrue("buh".endswith(ADDED_VOWEL_ENDINGS))
        self.assertEqual(spoken_words("Tuh, tuh, tuh."), ["tuh", "tuh", "tuh"])


class FindingThePhoneme(unittest.TestCase):
    def test_a_fricative_ends_where_the_voice_starts(self):
        # 140 ms of hiss, then a 200 Hz vowel.
        word = noise(140) + tone(200, 300)
        f = measure(word, RATE)
        start, end = onset_span(f, "fricative")
        self.assertAlmostEqual((end - start) * FRAME_MS, 140, delta=25)

    def test_a_vowel_ends_where_the_next_consonant_closes(self):
        word = tone(200, 160) + silence(60) + noise(120)
        f = measure(word, RATE)
        start, end = onset_span(f, "vowel")
        self.assertAlmostEqual((end - start) * FRAME_MS, 160, delta=25)

    def test_a_stop_is_one_frame_because_the_burst_is_the_sound(self):
        word = silence(40) + noise(10, amplitude=12000) + tone(200, 200)
        f = measure(word, RATE)
        start, end = onset_span(f, "stop")
        self.assertEqual(end - start, 1)

    def test_an_implausible_cut_is_refused_rather_than_used(self):
        # Almost nothing before the voice starts: there is no /s/ here to hold
        # on to, and lengthening whatever was found would ship a clip that
        # measures perfectly and teaches the wrong sound.
        word = noise(10) + tone(200, 300)
        f = measure(word, RATE)
        with self.assertRaises(ValueError):
            onset_span(f, "fricative")


class HoldingASoundOn(unittest.TestCase):
    def test_it_reaches_the_length_asked_for(self):
        held = hold(tone(200, 120), RATE, 460, voiced=True)
        self.assertAlmostEqual(len(held) * 1000 / RATE, 460, delta=5)

    def test_pitch_is_found_for_a_voiced_sound(self):
        self.assertAlmostEqual(period(tone(200, 200), RATE), RATE // 200, delta=2)

    def test_noise_has_no_pitch_to_find(self):
        self.assertEqual(period(noise(200), RATE), 0)

    def test_a_held_voiced_sound_does_not_wobble(self):
        # The failure this guards: splicing copies of a periodic sound at an
        # arbitrary offset makes them cancel where they meet, and the run of
        # dips is heard as a buzz. Looping whole pitch periods prevents it.
        held = hold(tone(200, 120), RATE, 460, voiced=True)
        self.assertLess(envelope_ripple(held, RATE, skip_ms=40), 0.20)

    def test_splicing_out_of_phase_is_what_wobbles(self):
        # The artifact itself, produced on purpose. Cross-fading two copies of
        # a periodic sound half a period out of step makes them cancel where
        # they overlap: the waveform stays perfectly continuous and the level
        # drops, which is why only the envelope shows it.
        #
        # Asserted as a comparison rather than a threshold. The absolute
        # number depends on how long the overlap is against the 20 ms frames
        # the envelope is measured in; what is always true is that being out
        # of phase is worse than being in phase.
        one = tone(200, 120)
        overlap = 3 * (RATE // 200)

        def spliced(offset):
            out = list(one)
            for _ in range(6):
                out = _crossfade(out, one[offset:], overlap)
            return envelope_ripple(out, RATE, skip_ms=40)

        in_phase = spliced(0)
        out_of_phase = spliced(RATE // 400)  # half a period
        self.assertGreater(out_of_phase, in_phase * 3)
        self.assertLess(in_phase, 0.05)

    def test_holding_a_sound_on_adds_no_step_to_the_waveform(self):
        # The other artifact: a splice that lands mid-period is a step, and a
        # step is a click. Cross-fading is what prevents it.
        segment = tone(200, 120)
        held = hold(segment, RATE, 460, voiced=True)

        def worst_jump(v):
            return max(abs(b - a) for a, b in zip(v, v[1:]))

        self.assertLessEqual(worst_jump(held), worst_jump(segment) * 1.2)

    def test_a_held_hiss_stays_a_hiss(self):
        held = hold(noise(120), RATE, 460, voiced=False)
        self.assertAlmostEqual(len(held) * 1000 / RATE, 460, delta=5)
        f = measure(held, RATE)
        # Still noise: it crosses zero far more often than a vowel would.
        self.assertGreater(sum(f.zcr) / len(f.zcr), 0.18)


if __name__ == "__main__":
    unittest.main()
