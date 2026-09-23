# Privacy

Silly Soup is used by three- to five-year-olds. UK GDPR and the ICO's
[Age Appropriate Design Code](https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/childrens-information/childrens-code-guidance-and-resources/)
are treated as hard requirements, not goals.

## What the app collects

Nothing.

There are no accounts, no sign-in, no profiles, no analytics, no crash
reporting, no advertising, no third-party SDKs, and no identifiers of any
kind. The app does not know who is using it and has nowhere to send that
information if it did.

## Network calls

The app makes **no network calls while it runs**, and every byte it does
fetch comes from its own origin. Specifically:

- Poppins is bundled and declared as a font family in `pubspec.yaml`, so the
  engine loads it from the app bundle rather than from `fonts.gstatic.com`.
- The Noto fallback fonts the engine uses for emoji are vendored under
  `web/fallback-fonts`, and `web/flutter_bootstrap.js` points
  `fontFallbackBaseUrl` at them.
- The CanvasKit/skwasm renderer is served from `/canvaskit` on this origin,
  via `canvasKitBaseUrl` in `web/flutter_bootstrap.js`.
- `web/index.html` loads no analytics tag, no tag manager, no font CDN and no
  third-party script. This is a deliberate difference from the other Kindling
  apps, which do carry an analytics tag.
- There are no external links, no in-app purchases and no ads.
- The web build is an installable PWA and works fully offline.

The only network activity is downloading the app itself.

### Why three of those bullets name a default we had to turn off

Flutter's web loader fetches its renderer from `www.gstatic.com` and its
fallback fonts from `fonts.gstatic.com` unless it is told otherwise, and it is
not obvious from the app's own source that it is doing so. Until those three
settings were added this app contacted Google on every cold start, which is
exactly what this page said it did not do.

The check that matters is not a code review. Load the app in a browser with
an empty cache, open the network panel, and confirm every request is to this
origin. Anything else is a bug, and a serious one.

## What is stored on the device

- Adult settings (which sounds are on, pantry size, volume, and so on), in
  `SharedPreferences` — on web, that is `localStorage`.
- From Stage 2, adult-authored sounds, words, pictures and recordings, in
  IndexedDB.

All of it is local. None of it is synced, backed up by the app, or transmitted.
Clearing site data or uninstalling the app removes it.

## Camera

The camera is used for one thing: the optional mirror in "Watch my mouth", so
a child can watch their own mouth while they make a sound.

- It is **off by default** and only an adult can turn it on, from behind the
  press-and-hold gate.
- It is a **live view only**. There is no capture button, no photo, no video,
  no file and no upload. Nothing leaves the preview.
- The camera controller is created with `enableAudio: false`, so the
  microphone is never opened by the mirror.
- The controller is disposed as soon as the screen is left.

## Microphone

The microphone is not used at all in Stage 1.

From Stage 2, an adult can record their own pure sounds, words and version of
the soup song. Those recordings:

- are made deliberately by an adult, from inside the adult area;
- are stored on the device in IndexedDB;
- are never transmitted;
- can be deleted by the adult at any time.

No recording happens in the background, and nothing is recorded during a
child's session.

## Children's data

Because nothing is collected, there is no children's personal data to protect.

The Stage 2 "Look, listen and note" observation panel is the one place an
adult can type anything about a child. It is off by default, stored on the
device only, and is designed around a group name or initials rather than a
full name.

## Questions

Open an issue on this repository.
