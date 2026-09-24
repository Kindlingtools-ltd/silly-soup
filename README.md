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
- **Works offline** — installable PWA with its own service worker; the only runtime network call is the analytics tag, and the app carries on without it

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

`flutter pub get` signs off with *"2 packages have newer versions incompatible
with dependency constraints"*. That is expected and nothing is wrong: the two it
means, `material_color_utilities` and `test_api`, are pinned to an exact version
by the Flutter SDK itself, not by us — see the note at the top of `pubspec.yaml`.
Every dependency this app declares is at its latest published version.

## Testing it on a tablet or a phone

The app is at its best on a tablet lying flat on a table between an adult and
a child, in landscape — but it lays itself out for whatever screen it is
given, phone in either orientation included.

```bash
# Serve the release build on the local network
flutter build web --wasm --release
cd build/web && python3 -m http.server 8080
# then open http://<your-machine-ip>:8080 on the tablet
```

Worth checking on the device itself:

1. **Both orientations** — in landscape the pot and the shelf sit side by side; in portrait the pot sits above the shelf. The pantry is on screen either way, with a whole row of ingredients reachable without scrolling.
2. **Dragging** — drag a picture from the shelf into the pot. The pot grows slightly as the item comes over it.
3. **Tapping** — tap a picture instead. It should go in just the same. (Switch to "Tap only" in the adult area to check the simpler path.)
4. **Tap targets** — nothing you need to hit is under 72&nbsp;px.
5. **The adult gate** — press and hold the cog in the corner for three seconds. A quick tap must do nothing.
6. **Mirror mode** — turn it on in the adult area, then open "Watch my mouth". The browser asks for camera permission; the view is live only and there is no capture button.
7. **Reduced motion** — turn on the device's reduce-motion setting, or the toggle in the adult area, and check the soup stops bobbing.
8. **Whiteboard mode** — everything scales up and the chef waits for you instead of moving on by itself.
9. **Offline** — load it once, turn off wi-fi, reload. It still runs. One online visit is enough: the page tells the service worker which files this browser actually downloaded, and those get cached.
10. **Sound on a phone** — the chef should speak from the first tap. Mobile browsers refuse to make a sound before the page has been touched, so the first touch anywhere is spent silently unlocking the voice.

> Camera access needs a secure context. On a tablet that means HTTPS or `localhost`; a plain `http://<ip>` page will not be offered the camera. Test mirror mode against <https://silly-soup.kindlingtools.com> rather than a local address.

## Running the checks

```bash
flutter test                                    # 239 tests
flutter analyze --fatal-infos --fatal-warnings  # what CI runs
dart format --output=none --set-exit-if-changed .
uv run tool/build_audio.py --audit --deep       # measure every recording
```

## Audio

Audio is the most important part of this app, and all of it is recorded:
267 clips under `assets/audio`, in a British voice, covering the whole of what
the chef says. The device's own text-to-speech is now only a fallback for a
clip that is missing, and every fallback is logged — in the adult area and by
the audit.

```bash
uv run tool/build_audio.py --plan          # what would be built, and what it says
uv run tool/build_audio.py                 # build whatever is missing
uv run tool/build_audio.py --force         # rebuild everything
uv run tool/build_audio.py --audit --deep  # measure every clip and read it back
```

The one thing to know before changing anything here: **the engine is never
asked to pronounce phonics notation.** Asking it for `sss` gets "S S S" and
asking it for `b-b-banana` gets "buh buh banana", which is the single mistake
a phonics app cannot make. It is asked for ordinary words, and the pure sounds
and the stretched "sssun" are cut and held in the waveform afterwards.

**[`docs/audio.md`](docs/audio.md) has the rest** — how the voice was chosen
(measured, across all 28 the API offers, rather than taken on trust), how each
class of sound is shaped, and what the audit checks.

The voice used for the fallback is behind `SpeechEngine`, with two
implementations. iOS, Android and desktop use `flutter_tts`; the web talks to
the Web Speech API directly (`lib/services/speech_engine_web.dart`) for two
reasons found while fixing the audio on mobile:

* `flutter_tts` on the web reuses a single utterance and, when speech
  *fails*, drops the future it handed the caller instead of completing it. A
  device with no usable voice left the chef frozen mid-sentence until a
  timeout fired, twice, after which the app gave up on the voice and played
  the whole game in silence.
* A mobile browser will not speak until the page has been touched, and
  refuses silently. The engine needs a `unlock()` it can spend inside a real
  tap — `main.dart` calls it on the first pointer down, above every screen.

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
├── audio/manifest.json       # Which clips this build has
├── audio/{phonemes,words,commentary,list,actions,lines,song}/
├── images/                   # Drop-in replacements for the emoji placeholders
└── google_fonts/             # Poppins, bundled so nothing is fetched at runtime

tool/build_audio.py           # Builds and audits every recording
tool/audio_dsp.py             # Holding, bouncing and measuring a waveform
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

No accounts, and nothing collected about a child. Everything a child does stays on the device.

The web build carries Google Analytics 4 (`G-DEQ5M9ZK36`), like the other Kindling apps, measuring how the app is used rather than who is using it: screens opened, sounds picked, pantry words added, soups finished or left, settings changed. Nothing from the camera or microphone is sent, no text an adult types is sent, and advertising is denied at the tag — `ad_storage`, `ad_user_data` and `ad_personalization` are all `denied`, with Google Signals off.

The tag fires no page views of its own (`send_page_view: false`): the app is one page whose URL never changes, so screen views come from a `NavigatorObserver` instead — see `lib/services/analytics_route_observer.dart`. Analytics is web-only; the conditional import is keyed on `dart.library.js_interop` rather than `dart.library.html`, because the app is built with `--wasm` and `dart.library.html` is false there.

Every event, and everything deliberately left out, is listed in [PRIVACY.md](PRIVACY.md).

## Licence

MIT — see [LICENSE](LICENSE), the same licence as the other Kindling apps. Poppins is bundled under the SIL Open Font Licence — see `assets/google_fonts/OFL.txt`.
