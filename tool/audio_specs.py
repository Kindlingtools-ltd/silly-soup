"""Every clip the app plays, and the British pronunciation it is built from.

One list, derived from the sound bank and the chef's script, so that "what
audio does this app need" has exactly one answer — the audio tool, the
checklist and the tests all read it from here.
"""

from __future__ import annotations

import json

from audio_pipeline import Spec

STRESS_MARKS = "ˈˌ"
# Two extra length marks turn a sound into a held one: /s/ -> /sːː/. Three
# reads as a drawl, one is barely a stretch at all.
STRETCH = "ː" * 2
# Held sounds split two ways, and the split decides how a take is checked.
# A voiced one — a nasal or a vowel — is a steady hum, so its loudness should
# barely move across the clip, and a letter name ("em" for /m/) shows up as a
# loud vowel followed by a quiet consonant. A voiceless fricative is noise:
# its loudness jumps about frame to frame however good the take is, so
# flatness says nothing, and what matters instead is that there is no voicing
# in it at all — any vowel in "sss" is the letter name "ess" creeping in.
VOICELESS_FRICATIVES = {"s", "f", "h", "sh", "th", "ch"}

# The Letters and Sounds instruction for a stop is to bounce it: "b-b-b" on
# its own, and "b-b-banana" in front of a word. Kept in step with
# RecitalService.emphasise, which writes the same thing on screen.
BOUNCES = 3
BOUNCES_BEFORE_WORD = 2


def bare(ipa: str) -> str:
    return ipa.strip("/")


def stretched(ipa: str) -> str:
    """Hold a sound on: /s/ -> /sːː/, and /æ/ -> /æːː/."""
    return f"/{bare(ipa)}{STRETCH}/"


def emphasise(word_ipa: str, sound_ipa: str, is_continuant: bool) -> str:
    """The word with its first sound stretched: "sssun" as IPA.

    Only for continuants. A stop cannot be held on — that is the whole reason
    Phase One bounces them instead — so those are handled in `clip_specs` by
    repeating the sound in front of the word.
    """
    assert is_continuant
    body = bare(word_ipa)
    stress = ""
    while body and body[0] in STRESS_MARKS:
        stress, body = stress + body[0], body[1:]
    base = bare(sound_ipa)
    assert body.startswith(base), f"{word_ipa} does not start with {sound_ipa}"
    return f"/{stress}{base}{STRETCH}{body[len(base):]}/"


def article(is_vowel: bool) -> str:
    return "an" if is_vowel else "a"


def clip_specs(bank: dict, script: dict) -> list[Spec]:
    sounds = {s["id"]: s for s in bank["sounds"]}
    specs: list[Spec] = []

    for sound in bank["sounds"]:
        ipa = sound["pronunciation"]
        held = sound["articulation"] == "continuant"
        if held:
            hissed = sound["id"] in VOICELESS_FRICATIVES
            specs.append(
                Spec(
                    path=f"assets/audio/{sound['audio']}",
                    kind="phoneme",
                    text=sound["pureSound"],
                    replace={sound["pureSound"]: stretched(ipa)},
                    min_speech=0.30,
                    max_speech=1.70,
                    want_segments=1,
                    min_flatness=None if hissed else 0.35,
                    max_vowel=0.08 if hissed else None,
                    speed=1.0,
                )
            )
        else:
            token = sound["pureSound"]
            specs.append(
                Spec(
                    path=f"assets/audio/{sound['audio']}",
                    kind="phoneme",
                    text=" ".join([token] * BOUNCES),
                    replace={token: ipa},
                    min_speech=0.45,
                    max_speech=2.40,
                    want_segments=BOUNCES,
                    speed=1.0,
                )
            )

    for word in bank["words"]:
        sound = sounds[word["phoneme"]]
        held = sound["articulation"] == "continuant"
        word_ipa = word["pronunciation"]
        the = article(sound["isVowel"])

        specs.append(
            Spec(
                path=f"assets/audio/{word['audio']}",
                kind="word",
                text=word["word"],
                replace={word["word"]: word_ipa},
                # "pig" really is only about a sixth of a second long, so
                # this floor is low. A take that was actually swallowed is
                # caught by the loudness and burst checks instead.
                min_speech=0.14,
                max_speech=1.60,
            )
        )

        # The chef's recital form: "a sssun", "a b-b-banana". The article
        # travels with the word so that a list of them reads as English.
        if held:
            text = f"{the} {word['word']}"
            replace = {word["word"]: emphasise(word_ipa, sound["pronunciation"], True)}
        else:
            token = sound["pureSound"]
            text = f"{the} {' '.join([token] * BOUNCES_BEFORE_WORD)} {word['word']}"
            replace = {token: sound["pronunciation"], word["word"]: word_ipa}
        specs.append(
            Spec(
                path=f"assets/audio/emphasis/{word['word']}.mp3",
                kind="emphasis",
                text=text,
                replace=replace,
                min_speech=0.30,
                max_speech=3.20,
            )
        )

    for key, line in script["phrases"].items():
        specs.append(
            Spec(
                path=f"assets/audio/phrases/{key}.mp3",
                kind="phrase",
                text=line,
                min_speech=0.25,
                max_speech=3.60,
            )
        )

    for index, line in enumerate(script["praise"]):
        specs.append(
            Spec(
                path=f"assets/audio/praise/{index}.mp3",
                kind="praise",
                text=line,
                min_speech=0.60,
                max_speech=3.60,
            )
        )

    for sound in bank["sounds"]:
        if not sound.get("action"):
            continue
        specs.append(
            Spec(
                path=f"assets/audio/actions/{sound['id']}.mp3",
                kind="action",
                text=sound["action"],
                min_speech=0.70,
                max_speech=4.00,
            )
        )

    specs.append(
        Spec(
            path="assets/audio/song/silly_soup_song.mp3",
            kind="song",
            text=" ".join(
                [
                    "Stir the pot and stir it round,",
                    "Silly soup is bubbling.",
                    "In go all the sounds we found —",
                    "Whoosh! goes the soup!",
                ]
            ),
            min_speech=4.00,
            max_speech=14.00,
        )
    )
    return specs


def load(root: str = ".") -> list[Spec]:
    with open(f"{root}/assets/data/sound_bank.json", encoding="utf-8") as f:
        bank = json.load(f)
    with open(f"{root}/assets/data/chef_script.json", encoding="utf-8") as f:
        script = json.load(f)
    return clip_specs(bank, script)
