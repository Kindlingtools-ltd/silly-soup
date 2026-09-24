#!/usr/bin/env python3
"""Record every clip Silly Soup plays, in British English, and check each one.

    python3 tool/generate_audio.py --dry-run     # what is missing
    python3 tool/generate_audio.py               # record what is missing
    python3 tool/generate_audio.py --force       # record everything again
    python3 tool/generate_audio.py --only phonemes --takes 6
    python3 tool/generate_audio.py --audit       # re-measure what is on disk

Clips are committed, so this is once per clip and not once per build. Nothing
is regenerated that already exists unless you ask for it: the voice is not
deterministic, so re-running would quietly swap good takes for untested ones.

British English is not a flag. x.ai takes twenty BCP-47 language codes and
`en-GB` is not one of them — it accepts the string and ignores it. The accent
comes from the `pronunciation` fields in assets/data/sound_bank.json, which
are Received Pronunciation written in IPA and passed to the API's `replace`
map. See docs/AUDIO.md for the measurements behind that decision.

Credentials: none here. The AGENT_IAM_TOKEN in the environment is only worth
anything at the Agent IAP proxy, which attaches the real x.ai key on the way
out.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from audio_pipeline import (  # noqa: E402
    Analysis,
    Spec,
    TtsError,
    Voice,
    analyse,
    encode_mp3,
    read_mp3,
    samples,
    score,
    synthesise,
    trim_and_level,
)
from audio_specs import load as load_specs  # noqa: E402

from audio_pipeline import LEAD_PAD_MS, SAMPLE_RATE, TRAIL_PAD_MS  # noqa: E402

MANIFEST = "assets/data/audio_manifest.json"
# Four takes catches most of the bad ones without quadrupling the bill; the
# pure sounds are worth more attempts because they are the thing being taught.
DEFAULT_TAKES = 4
PHONEME_TAKES = 8


def proxy() -> tuple[str, str]:
    # The host variable is spelled AGANT_IAM_HOST in the runtime this is built
    # in. Accept both rather than fail on a typo nobody here can fix.
    host = os.environ.get("AGENT_IAM_HOST") or os.environ.get("AGANT_IAM_HOST")
    token = os.environ.get("AGENT_IAM_TOKEN")
    if not host or not token:
        sys.exit(
            "AGENT_IAM_HOST and AGENT_IAM_TOKEN must be set. This tool only "
            "reaches x.ai through the Agent IAP proxy and holds no API key."
        )
    return host, token


def best_take(
    spec: Spec, voice: Voice, host: str, token: str, takes: int
) -> tuple[list[int], int, Analysis, list[str]]:
    """Record `spec` several times and return the best usable take.

    Raises TtsError with every rejection listed if none of them is usable —
    a clip that cannot be recorded well is left absent on purpose, so the app
    falls back to the device voice and the checklist keeps asking for it.
    """
    rejected: list[str] = []
    winner: tuple[float, list[int], int, Analysis] | None = None
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
        if winner is None or distance < winner[0]:
            winner = (distance, values, rate, measured)
    if winner is None:
        raise TtsError("; ".join(rejected) or "no takes")
    return winner[1], winner[2], winner[3], rejected


def write(spec: Spec, values: list[int], rate: int, measured: Analysis) -> int:
    trimmed = trim_and_level(values, rate, measured)
    Path(spec.path).parent.mkdir(parents=True, exist_ok=True)
    Path(spec.path).write_bytes(encode_mp3(trimmed, rate))
    return round(len(trimmed) * 1000 / rate)


def audit(specs: list[Spec]) -> int:
    """Check every clip that shipped, without calling the API.

    Reads each file as an MP3 rather than trusting its name and its first two
    bytes, then holds its length against the same bounds the recording had to
    pass. A clip that was fine when it was made and has since been truncated,
    or replaced by a web page, fails here.
    """
    missing: list[str] = []
    broken: list[str] = []
    odd: list[str] = []
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
        # Trimming leaves a little padding on each end, so allow for it.
        slack = (LEAD_PAD_MS + TRAIL_PAD_MS) / 1000 + 0.05
        if not spec.min_speech <= info.seconds <= spec.max_speech + slack:
            odd.append(
                f"{spec.path}: {info.seconds:.2f}s, expected "
                f"{spec.min_speech:.2f}-{spec.max_speech:.2f}s"
            )
        by_kind.setdefault(spec.kind, []).append(
            (path.stat().st_size, info.seconds)
        )

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


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--audit", action="store_true")
    parser.add_argument(
        "--only", help="record one group: phonemes, words, emphasis, phrases, ..."
    )
    parser.add_argument("--takes", type=int, default=0)
    parser.add_argument("--voice", default=Voice.voice_id)
    parser.add_argument("--speed", type=float, default=Voice.speed)
    parser.add_argument("--jobs", type=int, default=6)
    args = parser.parse_args(argv)

    if not Path("assets/data/sound_bank.json").exists():
        sys.exit("Run this from the project root.")

    everything = load_specs()
    specs = everything
    if args.only:
        wanted = args.only.rstrip("s")
        specs = [s for s in specs if s.kind.rstrip("s") == wanted]
        if not specs:
            sys.exit(f"--only {args.only}: no clips of that kind")

    if args.audit:
        return audit(specs)

    # The manifest always describes the whole app, never just the group being
    # recorded — it is what the app reads to know which clips exist.

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
    voice = Voice(voice_id=args.voice, speed=args.speed)
    failures: list[tuple[Spec, str]] = []
    written = 0

    def record(spec: Spec):
        takes = args.takes or (
            PHONEME_TAKES if spec.kind == "phoneme" else DEFAULT_TAKES
        )
        return spec, best_take(spec, voice, host, token, takes)

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {pool.submit(record, s): s for s in todo}
        for future in concurrent.futures.as_completed(futures):
            spec = futures[future]
            try:
                _, (values, rate, measured, rejected) = future.result()
            except TtsError as error:
                failures.append((spec, str(error)))
                print(f"  ✗ {spec.path}: {error}")
                continue
            ms = write(spec, values, rate, measured)
            written += 1
            note = f"  ({len(rejected)} take(s) rejected)" if rejected else ""
            print(f"  ✓ {spec.path}  {ms} ms{note}")

    update_manifest(everything, args)
    print(f"\n{written} recorded, {len(failures)} could not be.")
    for spec, why in failures:
        print(f"  {spec.path}: {why}")
    return 1 if failures else 0


def update_manifest(specs: list[Spec], args) -> None:
    """The list of clips that actually exist, for the app and the tests.

    The app needs this before it starts a sentence, not during one: on the web
    a missing asset comes back as the single-page host's index.html rather
    than a 404, so "is this clip here?" cannot be answered by trying to play
    it. Knowing up front is what lets the chef pick clips for a whole line or
    speak the whole line, instead of breaking down half way through.
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
                "speed": args.speed,
                "clips": clips,
            },
            indent=2,
        )
        + "\n"
    )
    print(f"{MANIFEST}: {len(clips)} clips")


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
