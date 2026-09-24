import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the parts of the web shell that decide what a phone sees before
/// Flutter is running.
///
/// The shell is plain HTML and CSS, so no widget test covers it, and the
/// window it is on screen for is the one this PR exists to fill. Both things
/// below were found by walking the app in a real browser at 33 phone and
/// tablet viewports; neither is visible in the Dart source.
void main() {
  final indexHtml = File('web/index.html').readAsStringSync();

  group('the boot splash is laid out for the device it is on', () {
    test('index.html carries a viewport meta tag', () {
      // Without one, a phone lays the page out at 980px and scales it down to
      // fit: the splash was drawn at 37% size on a 360px phone and 82% on an
      // 800px tablet. Only a screen 980px or wider escaped it, which is why
      // it looked right on an iPad. The engine writes this tag itself, but
      // only once it has booted — which is the whole of the wait the splash
      // is here to cover.
      expect(
        indexHtml,
        contains('<meta name="viewport"'),
        reason:
            'The boot splash is scaled down on every screen under 980px '
            'wide without it.',
      );
    });

    test('it is the same tag the engine writes, so nothing moves', () {
      // A different width or initial-scale would make the page jump at the
      // handover, which is worse than having no splash at all.
      expect(
        indexHtml,
        contains(
          '<meta name="viewport" '
          'content="width=device-width, initial-scale=1.0, maximum-scale=5.0">',
        ),
        reason:
            'Must match what the Flutter engine injects verbatim, or the '
            'splash jumps when the engine takes over.',
      );
    });

    test('pinch zoom is still allowed', () {
      // An adult with low vision has to be able to zoom. `maximum-scale=5`
      // is the engine's own value; `user-scalable=no` would not be.
      expect(indexHtml, isNot(contains('user-scalable=no')));
    });
  });

  group('the splash is set in the same type as the screen behind it', () {
    // The two strings the splash draws, and the only two the subset covers.
    const drawn = ['Silly Soup', 'Warming up the pot…'];

    test('the splash asks for Poppins, not whatever the system offers', () {
      final rule = _ruleFor(indexHtml, '.boot');
      expect(
        rule,
        contains("font-family: 'Poppins Boot'"),
        reason:
            'the splash was drawn in the system font and the home screen '
            'in Poppins, so the handover was a jump in typeface',
      );
      expect(
        rule,
        contains('sans-serif'),
        reason: 'keep a fallback stack behind it',
      );
    });

    test('it carries the font itself, inline', () {
      // A <link> would be a second round trip on the critical path and would
      // land after the first frame. See tool/boot_font/README.md.
      for (final weight in [500, 600]) {
        expect(
          indexHtml,
          contains('font-weight: $weight'),
          reason: 'no @font-face for weight $weight',
        );
      }
      expect(
        RegExp('src: url\\(data:font/woff2;base64,').allMatches(indexHtml),
        hasLength(2),
        reason: 'both splash weights should be inlined, not fetched',
      );
    });

    test('the inlined bytes are the files they were made from', () {
      for (final weight in [500, 600]) {
        final file = File('tool/boot_font/poppins-boot-$weight.woff2');
        expect(
          file.existsSync(),
          isTrue,
          reason: '${file.path} is the source of the inlined base64',
        );
        expect(
          indexHtml,
          contains(base64.encode(file.readAsBytesSync())),
          reason:
              'web/index.html no longer carries the bytes in '
              '${file.path} — regenerate both together, see '
              'tool/boot_font/README.md',
        );
      }
    });

    test('the splash draws nothing the subset cannot set', () {
      // The subset is 1.4KB a weight because it holds only these characters.
      // Change the wording and the missing glyphs fall back silently to the
      // system font, one word at a time.
      final covered = drawn.join().runes.toSet();

      for (final tag in ['h1', 'p']) {
        final text = RegExp(
          '<$tag>(.*?)</$tag>',
          dotAll: true,
        ).firstMatch(_splashMarkup(indexHtml))?.group(1)?.trim();
        final rendered = text == null ? null : _unescape(text);
        expect(text, isNotNull, reason: 'no <$tag> in the splash');
        expect(
          drawn,
          contains(rendered),
          reason:
              '"$rendered" is not one of the strings the font was subset '
              'for — regenerate it, see tool/boot_font/README.md',
        );
        expect(rendered!.runes.toSet().difference(covered), isEmpty);
      }
    });

    test('it uses the app\'s own sizes, weights and colours', () {
      // KindlingTypography: headlineLarge is w600 at the 34px the home screen
      // asks for; `secondary` is w500/18px. Anything else and the handover
      // moves the words.
      final h1 = _ruleFor(indexHtml, '.boot h1');
      expect(h1, contains('font-size: 34px'));
      expect(h1, contains('font-weight: 600'));
      expect(h1, contains('color: #111827')); // KindlingColours.textPrimary

      final p = _ruleFor(indexHtml, '.boot p');
      expect(p, contains('font-size: 18px'));
      expect(p, contains('font-weight: 500'));
      expect(p, contains('color: #4B5563')); // KindlingColours.textSecondary
    });
  });

  group('the install hint never takes a tap from the app', () {
    test('the hint is pointer-transparent', () {
      final banner = _ruleFor(indexHtml, '.install-banner');
      expect(
        banner,
        contains('pointer-events: none'),
        reason:
            'It is drawn over the top of the app, so every tap has to '
            'reach the app underneath.',
      );
    });

    test('the hint contains nothing tappable', () {
      // Its close button sat in the top-right corner, directly over the cog
      // that opens the grown-ups' area and over "stop the sound" in the
      // kitchen. Holding the cog while the hint was up dismissed the hint and
      // never started the three-second hold.
      final markup = RegExp(
        r'<div class="install-banner"[^>]*>(.*?)</div>',
        dotAll: true,
      ).firstMatch(indexHtml)?.group(1);
      expect(markup, isNotNull, reason: 'install banner markup not found');
      expect(
        markup,
        isNot(matches(RegExp('<(button|a|input)', caseSensitive: false))),
        reason:
            'The hint already goes away on the first touch anywhere and '
            'after eight seconds; anything tappable in it only steals taps '
            'from the control underneath.',
      );
    });
  });
}

/// The body of the first CSS rule for [selector] in [html].
String _ruleFor(String html, String selector) {
  final match = RegExp('${RegExp.escape(selector)}\\s*\\{([^}]*)\\}')
      .firstMatch(html);
  expect(match, isNotNull, reason: 'no CSS rule for $selector');
  return match!.group(1)!;
}

/// The markup inside the boot splash element.
String _splashMarkup(String html) {
  final match = RegExp(
    r'<div class="boot" id="boot-splash">(.*?)\n  </div>',
    dotAll: true,
  ).firstMatch(html);
  expect(match, isNotNull, reason: 'boot splash markup not found');
  return match!.group(1)!;
}

/// The few HTML entities the splash uses, as the browser would draw them.
String _unescape(String html) => html
    .replaceAll('&hellip;', '\u2026')
    .replaceAll('&amp;', '&')
    .replaceAll('&nbsp;', '\u00a0');
