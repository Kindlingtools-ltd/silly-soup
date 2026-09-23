# Silly Soup

A phonics game for Early Years Foundation Stage children aged 3 to 5, recreating the **Silly Soup** activity from the DfE *Letters and Sounds* Phase One programme (Aspect 5: Alliteration, "Talking about sounds").

A chef says a sound, models a soup with three things that start with it, and then hands the pot over. The child chooses whatever they like from the shelf. The chef recites the growing list with the sound emphasised, and celebrates. **There is nothing to get wrong.**

> Live at <https://silly-soup.kindlingtools.com>. Built by [Kindling Tools](https://kindlingtools.com). Not affiliated with or endorsed by the DfE.

## Faithful to the original activity

| The activity says | What the app does |
|---|---|
| Everything in the pantry starts with the same sound | The core mode cannot put an item with another sound on the shelf — it is a tested guarantee, not a convention |
| An adult models first | The chef makes a soup of three items before the child's turn |
| Children choose freely, with no steering | Every item is accepted; nothing is suggested, ranked or refused |
| The adult recites the list with the sound emphasised | Continuants stretch (`sssun`, `sssock`), stops bounce (`b-b-banana`, `b-b-bug`) |
| The adult commentates and congratulates | Commentary after each item, praise after every third and at the end |
| No right or wrong answers | No score, no timer, no streak, no lives, no buzzer, no cross |

Letters are introduced in **Phase 2**, not Phase One, so the app is sounds and pictures only until an adult turns on "Show letters".

## Features

- **Silly Soup** — the core game, for the starter sounds `s a t p b` (plus `i n m d` ready to switch on)
- **Watch my mouth** — an animated close-up of how each sound is made, with an optional live camera mirror an adult can turn on
- **The Silly Soup Song** — original words to the public-domain tune of *Pop Goes the Weasel*, replaceable with an adult's own recording
- **Adult area** — behind a three-second press-and-hold: sounds and their order, pantry size, Phase 2 letters, drag vs tap, mirror, volume, reduced motion, whiteboard mode
- **Whiteboard mode** — extra-large and adult-paced, for group sessions
- **Works offline** — installable PWA with its own service worker, no network calls at runtime

## Requirements

- Flutter SDK 3.47.5 or later
- Dart SDK 3.13.4 or later

## Getting started

```bash
flutter pub get
flutter run -d chrome     # web
flutter run -d ios        # iOS simulator
flutter run -d android    # Android emulator
```

## Testing it on a tablet

The app is designed for a tablet lying flat on a table between an adult and a child, in landscape.

```bash
# Serve the release build on the local network
flutter build web --wasm --release
cd build/web && python3 -m http.server 8080
# then open http://<your-machine-ip>:8080 on the tablet
```

Worth checking on the device itself:

1. **Landscape** — the pot and the shelf sit side by side. In portrait the web build shows a "turn the tablet sideways" prompt.
2. **Dragging** — drag a picture from the shelf into the pot. The pot grows slightly as the item comes over it.
3. **Tapping** — tap a picture instead. It should go in just the same. (Switch to "Tap only" in the adult area to check the simpler path.)
4. **Tap targets** — nothing you need to hit is under 72&nbsp;px.
5. **The adult gate** — press and hold the cog in the corner for three seconds. A quick tap must do nothing.
6. **Mirror mode** — turn it on in the adult area, then open "Watch my mouth". The browser asks for camera permission; the view is live only and there is no capture button.
7. **Reduced motion** — turn on the device's reduce-motion setting, or the toggle in the adult area, and check the soup stops bobbing.
8. **Whiteboard mode** — everything scales up and the chef waits for you instead of moving on by itself.
9. **Offline** — load it once, turn off wi-fi, reload. It still runs. One online visit is enough: the page tells the service worker which files this browser actually downloaded, and those get cached.

> Camera access needs a secure context. On a tablet that means HTTPS or `localhost`; a plain `http://<ip>` page will not be offered the camera. Test mirror mode against <https://silly-soup.kindlingtools.com> rather than a local address.

## Running the checks

```bash
flutter test                                    # 116 tests
flutter analyze --fatal-infos --fatal-warnings  # what CI runs
dart format --output=none --set-exit-if-changed .
dart run tool/audio_checklist.dart              # what is left to record
```

## Audio

Audio is the most important part of this app. Clips are played from `assets/audio/phonemes` and `assets/audio/words`; anything not recorded yet falls back to the device voice (the Web Speech API on web, `en-GB`) and is logged — both in the adult area and by the checklist script:

```bash
dart run tool/audio_checklist.dart               # readable checklist
dart run tool/audio_checklist.dart --missing-only
dart run tool/audio_checklist.dart --csv > recording-list.csv
```

The checklist tells the person recording exactly what to say for each clip, including which sounds to stretch and which to bounce.

Clips can also be synthesised with an x.ai voice model, through the Agent IAP proxy:

```bash
dart run tool/generate_audio.dart --dry-run   # what would be generated
dart run tool/generate_audio.dart             # generate only what is missing
dart run tool/generate_audio.dart --force     # regenerate everything
```

Generated clips are committed, and the tool skips anything already on disk — 88 files is not something to rebuild on every run. The voice is British (`en-GB`), and each phoneme clip carries an instruction not to add a vowel to the end of the sound, which is the one mistake that would make the app teach the wrong thing.

**79 of the 88 clips are recorded and committed** — all 78 words and the song, generated with x.ai's `eve` voice at `en-GB`.

The nine pure-sound clips are **not** shipped, and the generator skips them unless you pass `--include-phonemes`. The voice reads a bare consonant as its letter name: asking it for `t, t, t` returned a clip byte-identical to one that says `tee, tee, tee`. Teaching "tee" as the sound /t/ is the one mistake this app cannot make, so those nine need a human voice. Until they exist the adult area lists them as missing and the device voice fills in.

> Accent is not settled by the request — x.ai exposes no voices list and its docs do not name accents — so "British" is a judgement made by listening to the output.

## Project structure

```
lib/
├── main.dart                 # App entry point
├── models/                   # Sounds, words, settings, session, validation
├── services/                 # Game rules, recital, audio, storage, sound packs
├── providers/                # State management (Provider)
├── screens/                  # Home, Soup, Watch my mouth, Adult area
├── widgets/                  # Pot, shelf, chef, mouth, sound card, gate
├── utils/                    # App theme on top of the Kindling theme
└── kindling_theme/           # Shared Kindling Tools theming system

assets/
├── data/sound_bank.json      # The word bank
├── audio/{phonemes,words,song}/
├── images/                   # Drop-in replacements for the emoji placeholders
└── google_fonts/             # Poppins, bundled so nothing is fetched at runtime

tool/audio_checklist.dart     # What still needs recording
```

## The word bank

`assets/data/sound_bank.json` is the whole of the content, and it is the same shape as an exported sound pack — so a teacher can read it, edit it, and move it between devices.

Words carry the fields the brief asked for:

| Field | Meaning |
|---|---|
| `word` | The word, lower case |
| `phoneme` | The **sound** it starts with, not the letter — `cat` and `kite` would both be `k` |
| `image` | `emoji:🍌`, `asset:items/banana.svg` or `custom:<id>` |
| `audio` | Clip path relative to `assets/audio/` |
| `hasCluster` | True for `spoon`, `star`, `train` — fine to listen to, not expected to be produced |
| `difficulty` | 1 (shortest and most familiar) to 3 |
| `notes` | Anything an adult should read first: picture caveats, accent warnings |
| `initialGrapheme` | Optional. The letters that spell the initial sound, for digraphs like `sh` |

Sounds carry `articulation` (`continuant` or `stop`), which is what decides whether the chef stretches or bounces, `pureSound` (never with an added "uh"), `mouthShape`, `mouthTip` and `action`.

## Phonics content rules

- Organised by **sound**, not letter.
- Pure sounds only: `sss`, not "suh". A `stop` sound is never stretched — that is enforced by `RecitalService` and covered by tests.
- Words are familiar nouns a four-year-old can recognise from a picture.
- No silent letters, no misleading spellings.
- Cluster words are allowed for listening and **flagged** in the data.
- Sounds that are easy to confuse (`m`/`n`, `b`/`p`, `d`/`t`) carry a note telling the adult not to pair them early.
- `/i/` ships with four words and is **off by default**: there are not six strong picturable nouns that start with it. The app's own validator warns about this, and the adult area shows the warning.

## Roadmap

- **Stage 1 (this release)** — the core Silly Soup game, "Watch my mouth", the song, and the adult area.
- **Stage 2** — adult-authored sounds and words (record a sound, add a word with a photo or emoji, record the word), hide/reorder/edit, live preview, IndexedDB storage, and sound pack export/import. The data model, merge behaviour and pack validation are already in place and tested; what is missing is the UI and the IndexedDB-backed store behind `CustomContentStore`. The "Look, listen and note" observation panel lands here too.
- **Stage 3** — the extension modes: odd-one-out soup, "What's in the soup?", and rhyming soup. These are **not** part of the original activity and are labelled as extensions in the adult area.

## Offline and the service worker

Flutter's own service worker is now a no-op that unregisters itself, so the app ships its own — `web/sw.js`, registered from `web/flutter_bootstrap.js`:

- the page is **network-first**, so a new deploy is picked up as soon as there is a network, and falls back to the cached shell when there is not;
- everything else is **cache-first**, because the cache name carries the build id and cannot serve a stale asset against a fresh `index.html`;
- after the app boots, the page posts the list of resources it actually loaded to the worker, which caches them. Guessing that list at build time is not possible — which of the 48&nbsp;MB of renderer variants a browser picks depends on the browser.

CI stamps the commit SHA into `sw.js` after the build. Without that step the cache name never changes and a deploy can pair a new `index.html` with an old `main.dart.wasm`.

Verified in Chromium: load, go offline, reload, app still boots.

## Deployment

**Live at <https://silly-soup.kindlingtools.com>.**

Pushes to `master` build the WASM web bundle and deploy it to the Cloudflare **Pages** project `silly-soup`, which is what `silly-soup.kindlingtools.com` is a custom domain on — the same arrangement as `ks1-phonics` and `ks1-mtc`.

A Cloudflare Pages project and a Cloudflare Worker are separate resources even when they share a name. If the domain is ever moved onto a Worker, this has to move with it, or deploys will keep publishing to an address nothing points at. `web/_redirects` keeps deep links working, since Pages would otherwise 404 on any path that is not a real file.

The deploy step reads two repository secrets, `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`; if either is missing it skips with a warning rather than failing the build.

## Privacy

No accounts, no analytics, no tracking, no network calls at runtime. Everything stays on the device. See [PRIVACY.md](PRIVACY.md).

## Licence

MIT — see [LICENSE](LICENSE), the same licence as the other Kindling apps. Poppins is bundled under the SIL Open Font Licence — see `assets/google_fonts/OFL.txt`.
