#!/usr/bin/env python3
"""Record every clip Silly Soup plays, and read each one back before keeping it.

    python3 tool/generate_audio.py --dry-run      # what is missing
    python3 tool/generate_audio.py                # record what is missing
    python3 tool/generate_audio.py --force        # record everything again
    python3 tool/generate_audio.py --only phonemes
    python3 tool/generate_audio.py --audit        # check what is committed
    python3 tool/generate_audio.py --listen       # transcribe what is committed

Clips are committed, so this is once per clip and not once per build. Nothing
is re-recorded that already exists unless you ask: the engine is not
deterministic, so re-running would quietly swap verified takes for untested
ones.

Two things this does that the pass before it did not, and that are the whole
difference between audio that teaches phonics and audio that does not:

**It never asks the engine for a phoneme.** It cannot say one. `sss` comes
back as "S S S", `b` as "B", `b b b` as "Buh buh buh", and IPA length marks
and the `speed` parameter are accepted and silently ignored. So the pure
sounds are cut out of ordinary words instead — see tool/audio_build.py.

**It reads every clip back.** Acoustic measurements say whether a clip is well
formed, not whether it says the right thing: a recording can be a textbook
unbroken stretch of friction and still be the voice spelling out "S S S". Only
a transcript catches that.

Credentials: none here. AGENT_IAM_TOKEN is worth nothing except at the Agent
IAP proxy, which attaches the real x.ai key on the way out. `--audit` needs
neither and is what CI runs.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from audio_build import (  # noqa: E402
    STRETCH_LADDER_MS,
    Rejected,
    build_pure_sound,
    build_word_and_emphasis,
    listen,
)
from audio_pipeline import (  # noqa: E402
    LEAD_PAD_MS,
    SAMPLE_RATE,
    TRAIL_PAD_MS,
    Spec,
    TtsError,
    Voice,
    analyse,
    encode_mp3,
    read_mp3,
    samples,
    score,
    sounds_like,
    spoken_words,
    synthesise,
    to_wav,
    transcribe,
    trim_and_level,
)
from audio_specs import load as load_specs  # noqa: E402

MANIFEST = "assets/data/audio_manifest.json"
DEFAULT_TAKES = 4
# The sounds and the stretched words are the app's reason for existing, and
# they are the ones a bad take ruins, so they get more attempts.
CUT_TAKES = 6
# Kinds built by cutting a spoken word apart rather than by asking for them.
CUT_KINDS = {"phoneme", "word", "emphasis"}


def proxy() -> tuple[str, str]:
    # Spelled AGANT_IAM_HOST in the runtime this was built in. Accept both
    # rather than fail on a typo nobody here can fix.
    host = os.environ.get("AGENT_IAM_HOST") or os.environ.get("AGANT_IAM_HOST")
    token = os.environ.get("AGENT_IAM_TOKEN")
    if not host or not token:
        sys.exit(
            "AGENT_IAM_HOST and AGENT_IAM_TOKEN must be set. This tool only "
            "reaches x.ai through the Agent IAP proxy and holds no API key."
        )
    return host, token


def write_clip(path: str, values: list[int], rate: int) -> int:
    measured = analyse(values, rate)
    trimmed = trim_and_level(values, rate, measured)
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_bytes(encode_mp3(trimmed, rate))
    return round(len(trimmed) * 1000 / rate)


def spoken_clip(spec: Spec, voice: Voice, host: str, token: str, takes: int):
    """A clip the engine can simply say: a phrase, a praise line, the song.

    Still read back — the transcript is allowed to differ by a word, because
    the transcriber mishears the odd one ("silly soup" as "silly suit"), but
    not by more than that.
    """
    rejected = []
    best = None
    for attempt in range(takes):
        try:
            wav = synthesise(spec, voice, host, token)
        except TtsError as error:
            rejected.append(f"take {attempt + 1}: {error}")
            continue
        values, rate = samples(wav)
        measured = analyse(values, rate)
        usable, why, distance = score(spec, measured)
        if not usable:
            rejected.append(f"take {attempt + 1}: {why}")
            continue
        heard = listen(values, rate, host, token)
        wrong = _word_mismatch(heard.text, spec.text)
        if wrong > max(1, len(spoken_words(spec.text)) // 6):
            rejected.append(f"take {attempt + 1}: reads back as {heard.text!r}")
            continue
        if best is None or distance < best[0]:
            best = (distance, values, rate, heard.text)
    if best is None:
        raise Rejected("; ".join(rejected) or "no takes")
    return best[1], best[2], f"reads back as {best[3]!r}", rejected


def _word_mismatch(heard: str, expected: str) -> int:
    got, want = spoken_words(heard), spoken_words(expected)
    if not want:
        return 0
    wrong = abs(len(got) - len(want))
    for g, w in zip(got, want):
        if not sounds_like(g, w):
            wrong += 1
    return wrong


def build_cut_clips(bank: dict, specs: list[Spec], host: str, token: str, voice, force):
    """The clips that are cut out of a spoken word: sounds, words, emphasis."""
    sounds = {s["id"]: s for s in bank["sounds"]}
    ipa = {w["word"]: w["pronunciation"] for w in bank["words"]}
    wanted = {s.path for s in specs}
    results: list[tuple[str, str]] = []
    failures: list[tuple[str, str]] = []

    def needed(path: str) -> bool:
        return path in wanted and (force or not Path(path).exists())

    def do_sound(sound: dict):
        path = f"assets/audio/{sound['audio']}"
        if not needed(path):
            return
        notes = []
        for attempt in range(CUT_TAKES):
            try:
                clip, rate, note = build_pure_sound(
                    sound, ipa[sound["carrierWord"]], voice, host, token
                )
                ms = write_clip(path, clip, rate)
                results.append((path, f"{ms} ms — {note}"))
                return
            except (Rejected, TtsError) as error:
                notes.append(f"take {attempt + 1}: {error}")
                time.sleep(0.2)
        failures.append((path, "; ".join(notes)))

    def do_word(word: dict):
        sound = sounds[word["phoneme"]]
        plain_path = f"assets/audio/{word['audio']}"
        emph_path = f"assets/audio/emphasis/{word['word']}.mp3"
        if not (needed(plain_path) or needed(emph_path)):
            return
        notes = []
        for attempt in range(CUT_TAKES):
            stretch = STRETCH_LADDER_MS[min(attempt // 2, len(STRETCH_LADDER_MS) - 1)]
            try:
                plain, emph, rate, note = build_word_and_emphasis(
                    word, sound, voice, host, token, stretch_ms=stretch
                )
                if needed(plain_path):
                    write_clip(plain_path, plain, rate)
                ms = write_clip(emph_path, emph, rate)
                results.append((emph_path, f"{ms} ms — {note}"))
                return
            except (Rejected, TtsError) as error:
                notes.append(f"take {attempt + 1} ({stretch} ms): {error}")
                time.sleep(0.2)
        failures.append((emph_path, "; ".join(notes)))

    jobs = [lambda s=s: do_sound(s) for s in bank["sounds"]]
    jobs += [lambda w=w: do_word(w) for w in bank["words"]]
    # Modest concurrency: the gateway holds bursts for human approval.
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for _ in pool.map(lambda job: job(), jobs):
            pass
    return results, failures


def audit(specs: list[Spec]) -> int:
    """Check every clip that shipped, without calling the API."""
    missing, broken, odd = [], [], []
    by_kind: dict[str, list[tuple[int, float]]] = {}
    for spec in specs:
        path = Path(spec.path)
        if not path.exists():
            missing.append(spec.path)
            continue
        try:
            info = read_mp3(path.read_bytes())
        except TtsError as error:
            broken.append(f"{spec.path}: {error}")
            continue
        if info.channels != 1 or info.sample_rate != SAMPLE_RATE:
            broken.append(
                f"{spec.path}: {info.sample_rate} Hz, {info.channels} channel(s)"
            )
            continue
        slack = (LEAD_PAD_MS + TRAIL_PAD_MS) / 1000 + 0.05
        if not spec.min_speech <= info.seconds <= spec.max_speech + slack:
            odd.append(
                f"{spec.path}: {info.seconds:.2f}s, expected "
                f"{spec.min_speech:.2f}-{spec.max_speech:.2f}s"
            )
        by_kind.setdefault(spec.kind, []).append((path.stat().st_size, info.seconds))

    checked = sum(len(v) for v in by_kind.values())
    total = sum(size for v in by_kind.values() for size, _ in v)
    print(f"{checked}/{len(specs)} clips play, {total / 1024:.0f} KiB total")
    for kind in sorted(by_kind):
        sizes = [s for s, _ in by_kind[kind]]
        lengths = sorted(d for _, d in by_kind[kind])
        print(
            f"  {kind:9} {len(sizes):3} clips  {sum(sizes) / 1024:6.0f} KiB  "
            f"{lengths[0]:.2f}-{lengths[-1]:.2f}s  "
            f"median {lengths[len(lengths) // 2]:.2f}s"
        )
    for line in missing:
        print(f"  MISSING  {line}")
    for line in broken:
        print(f"  BROKEN   {line}")
    for line in odd:
        print(f"  LENGTH   {line}")
    return 1 if (missing or broken or odd) else 0


def listen_to_everything(specs: list[Spec], host: str, token: str) -> int:
    """Transcribe every committed clip and show what it actually says.

    This is the report to read before believing any of the rest of it.
    """
    def one(spec: Spec):
        path = Path(spec.path)
        if not path.exists():
            return spec, "MISSING", 0
        try:
            result = transcribe(path.read_bytes(), host, token, filename=path.name)
            return spec, result.get("text", ""), 0
        except TtsError as error:
            return spec, f"!! {error}", 1

    worrying = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for spec, text, bad in pool.map(one, specs):
            flag = " "
            if spec.kind == "phoneme":
                words = spoken_words(text)
                from audio_pipeline import ADDED_VOWEL_ENDINGS, LETTER_NAMES

                if any(
                    w in LETTER_NAMES
                    or (w.endswith(ADDED_VOWEL_ENDINGS) and len(w) <= 4)
                    for w in words
                ):
                    flag, bad = "!", 1
            print(f" {flag} {spec.kind:9} {spec.path[13:]:38} {text!r}")
            worrying += bad
    print(f"\n{worrying} clip(s) read back as something they should not.")
    return 1 if worrying else 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--audit", action="store_true")
    parser.add_argument("--listen", action="store_true")
    parser.add_argument("--only", help="phonemes, words, emphasis, phrases, ...")
    parser.add_argument("--takes", type=int, default=0)
    parser.add_argument("--voice", default=Voice.voice_id)
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args(argv)

    if not Path("assets/data/sound_bank.json").exists():
        sys.exit("Run this from the project root.")
    with open("assets/data/sound_bank.json", encoding="utf-8") as f:
        bank = json.load(f)

    everything = load_specs()
    specs = everything
    if args.only:
        wanted = args.only.rstrip("s")
        specs = [s for s in specs if s.kind.rstrip("s") == wanted]
        if not specs:
            sys.exit(f"--only {args.only}: no clips of that kind")

    if args.audit:
        return audit(specs)
    if args.listen:
        host, token = proxy()
        return listen_to_everything(specs, host, token)

    todo = specs if args.force else [s for s in specs if not Path(s.path).exists()]
    print(
        f"{len(specs)} clips, {len(specs) - len(todo)} already recorded, "
        f"{len(todo)} to record."
    )
    if args.dry_run:
        for s in todo:
            print(f"  would record {s.path}  <- {s.text!r} {s.replace or ''}")
        return 0
    if not todo:
        update_manifest(everything, args)
        return 0

    host, token = proxy()
    voice = Voice(voice_id=args.voice)
    failures: list[tuple[str, str]] = []
    written = 0

    cut = [s for s in todo if s.kind in CUT_KINDS]
    if cut:
        print(f"\nCutting {len(cut)} clip(s) out of spoken words:")
        results, bad = build_cut_clips(bank, cut, host, token, voice, args.force)
        for path, note in sorted(results):
            print(f"  ✓ {path}  {note}")
        written += len(results)
        failures += bad
        for path, why in bad:
            print(f"  ✗ {path}: {why}")

    said = [s for s in todo if s.kind not in CUT_KINDS]
    if said:
        print(f"\nRecording {len(said)} spoken clip(s):")

        def record(spec: Spec):
            return spec, spoken_clip(
                spec, voice, host, token, args.takes or DEFAULT_TAKES
            )

        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures = {pool.submit(record, s): s for s in said}
            for future in concurrent.futures.as_completed(futures):
                spec = futures[future]
                try:
                    _, (values, rate, note, rejected) = future.result()
                except (Rejected, TtsError) as error:
                    failures.append((spec.path, str(error)))
                    print(f"  ✗ {spec.path}: {error}")
                    continue
                ms = write_clip(spec.path, values, rate)
                written += 1
                extra = f"  ({len(rejected)} rejected)" if rejected else ""
                print(f"  ✓ {spec.path}  {ms} ms — {note}{extra}")

    update_manifest(everything, args)
    print(f"\n{written} recorded, {len(failures)} could not be.")
    for path, why in failures:
        print(f"  {path}: {why}")
    return 1 if failures else 0


def update_manifest(specs: list[Spec], args) -> None:
    """The clips that actually exist, for the app and the tests.

    The app needs this before it starts a sentence, not during one: on the web
    a missing asset comes back as the single-page host's index.html rather
    than a 404, so "is this clip here?" cannot be answered by trying to play
    it. Knowing up front is what lets the chef choose clips for a whole line
    or speak the whole line, rather than breaking down half way through.
    """
    clips = {}
    for spec in sorted(specs, key=lambda s: s.path):
        path = Path(spec.path)
        if not path.exists():
            continue
        clips[spec.path[len("assets/audio/") :]] = {
            "kind": spec.kind,
            "bytes": path.stat().st_size,
            "ms": round(read_mp3(path.read_bytes()).seconds * 1000),
        }
    Path(MANIFEST).write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "voice": args.voice,
                "language": Voice.language,
                "clips": clips,
            },
            indent=2,
        )
        + "\n"
    )
    print(f"{MANIFEST}: {len(clips)} clips")


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
