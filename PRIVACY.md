# Privacy

Silly Soup is used by three- to five-year-olds. UK GDPR and the ICO's
[Age Appropriate Design Code](https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/childrens-information/childrens-code-guidance-and-resources/)
are treated as hard requirements, not goals.

## What the app collects

No personal data, and nothing about a child.

There are no accounts, no sign-in, no profiles, no crash reporting, no
advertising and no advertising identifiers. Nothing a child says, types, draws
or is filmed doing ever leaves the device, because the app never has any of it
to send.

The web build does carry **Google Analytics 4**, the same as the other
Kindling apps. What it measures is how the app itself is used — which sounds
are picked, how many things go into a pot, which settings a school changes —
so that time goes into the parts of the app that classrooms actually reach for.

### The events the app sends

| Event | What it records |
| --- | --- |
| `page_view` | Which of the four screens is open: `home`, `soup`, `watch_my_mouth`, `adult_area`. |
| `app_started`, `app_start_failed` | The app booted, and the settings it booted with: pantry size, letters on or off, whiteboard mode, drag or tap, mirror on or off. |
| `soup_started`, `soup_finished`, `soup_abandoned` | A soup was opened, run to the tasting, or left early. Carries the sound, how many things went in, and how long it took. |
| `chef_modelled`, `childs_turn_started` | The chef modelled a soup; the pot was handed over. |
| `ingredient_added`, `ingredient_removed` | Which pantry word went in or came out, and how full the pot was. Pantry words come from the app's own word bank. |
| `soup_stirred`, `sound_repeated`, `song_played`, `audio_stopped` | The stir, repeat, song and mute buttons were used. |
| `mouth_view_opened` | "Watch my mouth" was opened, and whether the mirror was on. |
| `adult_area_opened`, `setting_changed` | The adult gate was held open, and which setting moved. |

Every parameter is a sound id, a word from the built-in bank, a count, a
duration or a setting value. The full list lives in
`lib/services/analytics_service.dart`.

### What is never sent

- Anything from the camera or the microphone, including the mirror and any
  recording an adult saves as custom content.
- Any text an adult types: word names they add, sound labels, and anything
  in the Stage 2 "Look, listen and note" panel.
- Any name, initials, group name, or identifier of a child, an adult or a
  school.

### What Google receives

GA4 sets its own cookie and derives a client identifier from it, which is what
makes a returning tablet countable as a returning tablet rather than a new
one. It is a measure of a browser, not of a person, and the app never joins it
to anything. GA4 discards the IP address rather than storing it.

Advertising is denied at the tag, before it configures itself:
`ad_storage`, `ad_user_data` and `ad_personalization` are all set to `denied`,
Google Signals is off, and ad personalisation is off. Nothing measured here can
be used to build an advertising audience.

A school that would rather send nothing at all can block
`www.googletagmanager.com` on its network; the app is built to carry on
regardless, because it has to work with the wifi down anyway.

## Network calls

Once the app is running it makes exactly one kind of network call: the Google
Analytics tag described above. Everything else it fetches — including the
engine it runs on — comes from its own origin. Specifically:

- Poppins is bundled and declared as a font family in `pubspec.yaml`, so the
  engine loads it from the app bundle rather than from `fonts.gstatic.com`.
- The Noto fallback fonts the engine uses for emoji are vendored under
  `web/fallback-fonts`, and `web/flutter_bootstrap.js` points
  `fontFallbackBaseUrl` at them.
- The CanvasKit/skwasm renderer is served from `/canvaskit` on this origin,
  via `canvasKitBaseUrl` in `web/flutter_bootstrap.js`.
- `web/index.html` loads the Google tag and no other third-party script. There
  is no tag manager and no font CDN.
- There are no external links, no in-app purchases and no ads.
- The web build is an installable PWA and still works fully offline. The
  service worker only ever touches same-origin requests, so a blocked or
  unreachable tag cannot stop the app loading, and events raised while offline
  are simply dropped rather than queued up to send later.

### Why three of those bullets name a default we had to turn off

The analytics tag above is a decision: it is written down, it is configured,
and a school can block it. The calls those three bullets describe were not.

Flutter's web loader fetches its renderer from `www.gstatic.com` and its
fallback fonts from `fonts.gstatic.com` unless it is told otherwise, and it is
not obvious from the app's own source that it is doing so. Until those
settings were added this app also sent every nursery's IP address to Google
before the chef had said hello, in a way nobody had chosen and this page did
not mention.

The check that matters is not a code review. Load the app in a browser with an
empty cache, open the network panel, and confirm that the only off-origin name
in the list is `www.googletagmanager.com`. Anything else is a bug, and a
serious one. `test/web/no_third_party_test.dart` holds that line in CI.

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

No children's personal data is collected. The analytics above measure the app,
not the child using it: there is no identifier that points at a child, nothing
a child produced is sent, and nothing sent can be traced back to one.

The Stage 2 "Look, listen and note" observation panel is the one place an
adult can type anything about a child. It is off by default, stored on the
device only, and is designed around a group name or initials rather than a
full name.

## Questions

Open an issue on this repository.
