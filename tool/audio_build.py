"""Build the clips that cannot be asked for: the pure sounds, and the words
with their first sound stretched or bounced.

The engine will not say a phoneme. Every route was tried and read back:

    asked for            came back as
    sss                  "S S S."
    b                    "B."
    b b b                "Buh buh buh."
    IPA /sːː/            a hiss, but see below
    IPA /sːːʌn/          "Son."      (length marks ignored)
    speed: 0.7           ignored

So nothing here asks. It says an ordinary word, checks by transcript that the
word came out right, then cuts the sound out of it — which is what an adult
does when they model /s/ by saying "sssun" and holding on to the front of it.

Every clip is read back before it is kept. That is the check the pass before
this one did not have: a clip can be a textbook unbroken stretch of friction
and still be the voice saying "S S S", and no acoustic measurement can tell.
"""

from __future__ import annotations

from dataclasses import dataclass

from audio_dsp import (
    envelope_ripple,
    hold,
    measure,
    onset_span,
    stretch_onset,
)
from audio_pipeline import (
    ADDED_VOWEL_ENDINGS,
    LETTER_NAMES,
    Spec,
    TtsError,
    Voice,
    analyse,
    samples,
    sounds_like,
    spoken_words,
    synthesise,
    to_wav,
    transcribe,
    trim_and_level,
)

# How long a held sound lasts. Long enough for a child to hear it and join in,
# short enough that they do not have to wait for the chef to stop.
HOLD_MS = 460
# How much of the release of a stop to keep. Any more than this and the voice
# that follows the burst becomes a vowel, and /b/ becomes "buh".
STOP_TAIL_MS = 32
# Bounces, and the gap between them: "b-b-b".
STOP_BOUNCES = 3
STOP_GAP_MS = 130
# The stretched sound inside a word — "sssun". Shorter than a sound on its
# own: it is part of a word here, not the point of the sentence.
STRETCH_MS = 330
# Above this the loudness of a held sound wobbles audibly. A cross-fade stops
# it clicking but not fluttering; see audio_dsp.envelope_ripple.
MAX_RIPPLE_VOICED = 0.20
MAX_RIPPLE_NOISE = 0.45

VOICED = {"vowel", "nasal"}


class Rejected(Exception):
    """This take is not usable. The caller records another one."""


@dataclass
class Heard:
    text: str
    words: list[dict]


def listen(values: list[int], rate: int, host: str, token: str) -> Heard:
    result = transcribe(to_wav(values, rate), host, token)
    return Heard(text=result.get("text", ""), words=result.get("words", []))


def _locate(heard: Heard, expected: str, rate: int, total: int) -> tuple[int, int]:
    """Where [expected] sits in the audio, from the transcriber's own timings.

    Finding the word this way rather than by looking for a gap is what makes
    the article reliable to skip: "a sun" and "an apple" put the word in
    different places, and a pause is not always where a word begins.
    """
    target = expected.lower()
    for word in reversed(heard.words):
        spelled = spoken_words(word.get("text", ""))
        if spelled and sounds_like(spelled[0], target):
            start = int(word["start"] * rate)
            end = min(total, int(word["end"] * rate))
            if end > start:
                return start, end
    raise Rejected(f"could not find {expected!r} in {heard.text!r}")


def _boundary_after_article(values: list[int], rate: int) -> int:
    """Where the word starts, when the transcriber ran it into the article.

    "a bear" is non-rhotic in Received Pronunciation, so it comes back as one
    word, "Abea", and there is no second timing to read. The article is a
    single short vowel, so the quietest moment in the window where the next
    consonant must begin is the join. Only a fallback — the finished clip is
    still checked by reading it back, which is what decides whether this
    guessed right.
    """
    f = measure(values, rate)
    lo = max(1, 50 // 5)
    hi = min(len(f.rms), 260 // 5)
    if hi <= lo:
        raise Rejected("too short to find the article boundary")
    quietest = min(range(lo, hi), key=lambda i: f.rms[i])
    return f.at(quietest)


def _expect_words(heard: Heard, expected: list[str]) -> None:
    got = spoken_words(heard.text)
    if len(got) == len(expected) and all(
        sounds_like(g, e) for g, e in zip(got, expected)
    ):
        return
    # The transcriber sometimes runs the article into the word: a stretched
    # /n/ makes "a nnnet" come back as the name "Annette". That is how it
    # chose to spell the same sounds, so compare the phrase as one word. Only
    # when it wrote *fewer* words than were asked for, though — more words
    # than expected is the "a tea tea tomato" failure, whose consonants
    # happen to line up too.
    if len(got) < len(expected) and sounds_like("".join(got), "".join(expected)):
        return
    raise Rejected(f"reads back as {heard.text!r}, expected {' '.join(expected)!r}")


def _check_ripple(values: list[int], rate: int, manner: str, skip_ms: int) -> float:
    ripple = envelope_ripple(values, rate, skip_ms=skip_ms)
    limit = MAX_RIPPLE_VOICED if manner in VOICED else MAX_RIPPLE_NOISE
    if ripple > limit:
        raise Rejected(f"held sound wobbles (ripple {ripple:.2f} > {limit:.2f})")
    return ripple


def _bounce(word: list[int], rate: int, start: int, f) -> list[int]:
    """A stop, bounced: the release burst on its own, three times over.

    The burst is the sound. It is never held on — holding a stop is exactly
    what produces "buh", and "buh" is the one thing this app must not teach.
    """
    # The burst is the first frame that jumps clear of the closure in front.
    burst = start
    for i in range(len(f.rms)):
        if f.rms[i] > f.peak * 0.18:
            burst = f.at(i)
            break
    tail = int(rate * STOP_TAIL_MS / 1000)
    piece = word[burst : burst + tail]
    if len(piece) < tail // 2:
        raise Rejected("no release burst to take")
    # Taper it, or each bounce ends on a step.
    fade = max(1, len(piece) // 3)
    piece = [
        int(s * (1 if i < len(piece) - fade else (len(piece) - i) / fade))
        for i, s in enumerate(piece)
    ]
    gap = [0] * int(rate * STOP_GAP_MS / 1000)
    out: list[int] = []
    for i in range(STOP_BOUNCES):
        if i:
            out += gap
        out += piece
    return out


def _guard_pure_sound(heard: Heard, sound_id: str) -> None:
    """A pure sound must not read back as a letter name or as "buh".

    Silence from the transcriber is the *right* answer here: an isolated
    consonant is not a word, so there is nothing for it to write down. What
    matters is that it did not find one.
    """
    words = spoken_words(heard.text)
    for word in words:
        if word in LETTER_NAMES:
            raise Rejected(f"reads back as the letter name {word!r}")
        if word.endswith(ADDED_VOWEL_ENDINGS) and len(word) <= 4:
            raise Rejected(f"reads back as {word!r} — the added vowel")
    if len(words) > 2:
        raise Rejected(f"reads back as words: {heard.text!r}")


def build_pure_sound(
    sound: dict, carrier_ipa: str, voice: Voice, host: str, token: str
) -> tuple[list[int], int, str]:
    """The sound on its own, cut out of its carrier word."""
    carrier = sound["carrierWord"]
    manner = sound["manner"]
    wav = synthesise(
        Spec(path="", kind="carrier", text=carrier, replace={carrier: carrier_ipa}),
        voice,
        host,
        token,
    )
    values, rate = samples(wav)
    heard = listen(values, rate, host, token)
    _expect_words(heard, [carrier])

    f = measure(values, rate)
    try:
        a, b = onset_span(f, manner)
    except ValueError as error:
        raise Rejected(str(error)) from None
    s0, s1 = f.at(a), min(len(values), f.at(b))

    if manner == "stop":
        clip = _bounce(values, rate, s0, f)
        note = f"three bursts from {carrier!r}"
    else:
        clip = hold(values[s0:s1], rate, HOLD_MS, voiced=manner in VOICED)
        _check_ripple(clip, rate, manner, skip_ms=40)
        note = f"held {HOLD_MS} ms, cut from {carrier!r}"

    back = listen(clip, rate, host, token)
    _guard_pure_sound(back, sound["id"])
    return clip, rate, f"{note}; reads back as {back.text or '(no words — good)'!r}"


# How far to stretch the first sound, in order of preference. A long stretch
# models the sound best, but stretching too far changes the word — a long
# enough /m/ turns "milk" into "muck" — so when the read-back says the word
# has changed, the next attempt stretches it less rather than giving up.
STRETCH_LADDER_MS = (330, 250, 190)


def _same_words(after: Heard, before: Heard) -> None:
    """The edit must not have changed what the transcriber hears.

    This is the check that matters, and it is stronger than comparing against
    the spelling. Stretching a sound really can turn one word into another —
    a long enough /n/ makes "a nest" into "a nurse" — and this catches it
    whatever the transcriber chooses to call either of them.

    It also sidesteps a problem the spelling check cannot solve. Received
    Pronunciation is non-rhotic, so "a bear" is /ə beə/, and the transcriber
    spells that "Abia" or "Abaya" — not because anything is wrong with the
    recording but because it is not an English spelling of a word it knows.
    Holding the edit against the unedited take asks the only question worth
    asking: is it still the same word it was before?
    """
    got, was = spoken_words(after.text), spoken_words(before.text)
    ok = len(got) == len(was) and all(sounds_like(g, w) for g, w in zip(got, was))
    if not ok:
        raise Rejected(
            f"the edit changed it: was {before.text!r}, now {after.text!r}"
        )


def build_word_and_emphasis(
    word: dict,
    sound: dict,
    voice: Voice,
    host: str,
    token: str,
    stretch_ms: int = STRETCH_MS,
) -> tuple[list[int], list[int], int, str]:
    """The plain word, and the word with its first sound stretched or bounced.

    Two takes, each checked in the way that can actually be checked. The word
    on its own is held against its spelling. The stretched version is held
    against the take it was made from, because what must be true of it is that
    the editing did not change the word.
    """
    ipa = {word["word"]: word["pronunciation"]}

    plain_wav = synthesise(
        Spec(path="", kind="word", text=word["word"], replace=ipa), voice, host, token
    )
    plain, rate = samples(plain_wav)
    _expect_words(listen(plain, rate, host, token), [word["word"]])

    article = "an" if sound.get("isVowel") else "a"
    phrase_wav = synthesise(
        Spec(
            path="", kind="phrase", text=f"{article} {word['word']}", replace=ipa
        ),
        voice,
        host,
        token,
    )
    values, rate = samples(phrase_wav)
    before = listen(values, rate, host, token)
    if not spoken_words(before.text):
        raise Rejected("the take reads back as nothing at all")

    try:
        w0, _ = _locate(before, word["word"], rate, len(values))
    except Rejected:
        w0 = _boundary_after_article(values, rate)

    manner = sound["manner"]
    f = measure(values[w0:], rate)
    if manner == "stop":
        # "b-b-banana": the word's own release burst, twice in front of it.
        bursts = _bounce(values[w0:], rate, 0, f)
        one = len(bursts) // STOP_BOUNCES
        gap = int(rate * STOP_GAP_MS / 1000)
        emphasis = values[:w0] + bursts[: (one + gap) * 2] + values[w0:]
        note = "two bounces in front of the word"
    else:
        try:
            a, b = onset_span(f, manner)
        except ValueError as error:
            raise Rejected(str(error)) from None
        span = (w0 + f.at(a), min(len(values), w0 + f.at(b)))
        emphasis = stretch_onset(
            values, rate, span, stretch_ms, voiced=manner in VOICED
        )
        note = f"first sound held to {stretch_ms} ms"

    _same_words(listen(emphasis, rate, host, token), before)
    return plain, emphasis, rate, f"{note}; still reads back as {before.text!r}"
