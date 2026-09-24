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
