# Vendored font fallbacks

Poppins covers the app's text and nothing else. When the engine meets a glyph
no loaded font has — every emoji in the word bank, for a start — it goes
looking for a Noto font that does have it.

Left at its default it fetches those from `https://fonts.gstatic.com/s/`.
That is a third-party request from a device used by three- to five-year-olds,
which PRIVACY.md rules out, and it is also not cacheable by `sw.js` (a worker
cannot read an opaque cross-origin response), so the emoji were re-downloaded
on every cold start and never worked offline.

`web/flutter_bootstrap.js` therefore sets `fontFallbackBaseUrl: 'fallback-fonts/'`
and the files the app can ask for live here, in the exact directory layout the
engine builds its URLs with. The paths are content-pinned — the hash and the
`vNN` are part of the name — so `_headers` serves them `immutable`.

## What is here, and why these files

| Font | Why |
|---|---|
| `notocoloremoji/v32/….2.woff2` … `….9.woff2` | Every emoji in `assets/data/sound_bank.json`. Google shards this font into 12 pieces by codepoint; the word bank lands in eight of them. |
| `notosanssymbols2/v24/….woff2` | The text-presentation forms of the dingbat-range items — ⚓ ⛰ ⛺ ✈ ⭐. |
| `roboto/v32/….woff2` | The engine's last-resort Latin fallback, for any text that has not been given a family. |

Shards 0, 1, 10 and 11 are deliberately absent: nothing in the word bank needs
them, and shard 0 alone is 709KB.

## The failure mode, and how to re-derive the list

If a word is added whose emoji falls outside these shards, **it renders as a
tofu box** — the engine asks for a shard that is not here. It does not fall
back to Google, and that is the intended trade.

The list cannot be worked out by reading the font files; the codepoint-to-shard
map lives inside the engine. Re-derive it by observation:

1. Temporarily delete the `fontFallbackBaseUrl` line from
   `web/flutter_bootstrap.js`, so the engine goes back to `fonts.gstatic.com`.
2. Temporarily point `MaterialApp.home` at a widget that renders every emoji in
   the word bank at once — the engine only asks for a shard it actually needs,
   so anything less than all of them under-reports.
3. `flutter build web --wasm --release`, serve `build/web`, open it, and record
   every `fonts.gstatic.com` URL the page requests.
4. Download each one to the matching path under this directory, and put the
   two temporary edits back.

Run it again after any change to the word bank's pictures.
