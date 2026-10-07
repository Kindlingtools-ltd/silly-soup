# The splash's Poppins

Two subsets of the Poppins already in `assets/google_fonts/`, cut down to the
characters the boot splash draws and inlined into `web/index.html` as base64.

They are here rather than in `web/` on purpose: nothing fetches them at
runtime, so shipping them would be dead weight in a build whose whole point is
to arrive quickly. This directory is the source the inlined bytes were made
from, and a test checks the two still agree.

## Why the splash needs its own copy

The app's Poppins lives in the Flutter asset bundle, which does not exist
until the engine has booted — which is the entire wait the splash is there to
cover. So the splash was drawn in whatever the system offers and the home
screen then appeared in Poppins: a jump in typeface, size and colour at the
handover.

A `<link>` to a copy would be a second round trip on the critical path. At
60 ms RTT it lands *after* the first frame, so the splash paints in the system
font and reflows into Poppins — the jump again, just smaller. Inline, the font
is there the moment the style sheet is parsed.

That is only affordable because the subset is 1.4 KB a weight instead of
157 KB: the splash draws exactly two strings, ever.

## Regenerating

Needed after any edit to the splash's text, and after replacing Poppins.
`test/web/shell_layout_test.dart` fails if the text drifts outside what was
subset, and names this file when it does.

```bash
python3 -m venv .venv && .venv/bin/pip install fonttools brotli

TEXT='Silly SoupWarming up the pot…'
for pair in Poppins-SemiBold:600 Poppins-Medium:500; do
  .venv/bin/pyftsubset "assets/google_fonts/${pair%%:*}.ttf" \
    --text="$TEXT" --flavor=woff2 --layout-features='' \
    --no-hinting --desubroutinize \
    --output-file="tool/boot_font/poppins-boot-${pair##*:}.woff2"
done
```

Then replace the two `base64,` payloads in the `@font-face` blocks at the top
of `web/index.html`'s style sheet with:

```bash
base64 -w0 tool/boot_font/poppins-boot-500.woff2
base64 -w0 tool/boot_font/poppins-boot-600.woff2
```

Weight 600 is the `h1`, weight 500 the line under it — the same two weights
`KindlingTypography` uses for `headlineLarge` and `secondary`, so the splash
and the home screen behind it are set identically.

Poppins is SIL Open Font License 1.1; the licence travels with the originals
in `assets/google_fonts/OFL.txt` and covers these subsets.
