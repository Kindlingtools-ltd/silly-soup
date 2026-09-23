import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the settings that keep the app on its own origin.
///
/// Flutter's web loader fetches its renderer from `www.gstatic.com` and its
/// fallback fonts from `fonts.gstatic.com` *by default*. Nothing in the Dart
/// source says so, nothing warns about it, and the app works perfectly well
/// while doing it — so deleting one of these lines would be a silent
/// regression from "no third-party requests, works offline" back to
/// "contacts Google on every cold start". See PRIVACY.md.
void main() {
  final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
  final indexHtml = File('web/index.html').readAsStringSync();

  group('the web shell keeps every request on our own origin', () {
    test('the renderer is loaded from /canvaskit, not gstatic', () {
      expect(
        bootstrap,
        contains("canvasKitBaseUrl: 'canvaskit/'"),
        reason:
            'Without this the loader builds a www.gstatic.com URL from '
            'the engine revision and fetches ~1.2MB of renderer from Google.',
      );
    });

    test('font fallbacks are loaded from /fallback-fonts, not gstatic', () {
      expect(
        bootstrap,
        contains("fontFallbackBaseUrl: 'fallback-fonts/'"),
        reason:
            'Without this every emoji in the word bank is fetched from '
            'fonts.gstatic.com.',
      );
    });

    test('the analytics tag is the only off-origin host in the shell', () {
      // Hosts the browser is allowed to contact. Adding to this set is a
      // privacy decision, not a formatting one — PRIVACY.md has to change
      // with it, and so does what a school is told it can block.
      const allowed = {'www.googletagmanager.com'};

      for (final source in {
        'web/flutter_bootstrap.js': bootstrap,
        'web/index.html': indexHtml,
      }.entries) {
        final offOrigin = RegExp('https?://[^\'"\\s)]+')
            .allMatches(source.value)
            .map((match) => Uri.parse(match.group(0)!).host)
            // The page's own canonical, Open Graph and Twitter URLs are
            // metadata for crawlers, not requests the browser makes.
            .where((host) => host != 'silly-soup.kindlingtools.com')
            // Documentation links inside comments are not fetched either.
            .where((host) => host != 'ico.org.uk')
            .where((host) => !allowed.contains(host))
            .toSet()
            .toList();
        expect(
          offOrigin,
          isEmpty,
          reason:
              '${source.key} points at ${jsonEncode(offOrigin)}. The only '
              'host this app may contact is the analytics tag.',
        );
      }
    });
  });

  group('the page shows something while the engine downloads', () {
    test('index.html carries the boot splash', () {
      expect(indexHtml, contains('id="boot-splash"'));
      expect(
        indexHtml,
        contains('window.sillySoupBootSplashDone'),
        reason:
            'lib/services/boot_splash_web.dart calls this by name; '
            'renaming one without the other leaves the splash up forever.',
      );
    });

    test('the engine is preloaded, with crossorigin on the fetch preloads', () {
      expect(indexHtml, contains("link.rel = 'preload'"));
      expect(
        indexHtml,
        contains("link.crossOrigin = 'anonymous'"),
        reason:
            "An as='fetch' preload without crossorigin is mode no-cors "
            'and does not match the loader\'s fetch(), so the browser '
            'downloads main.dart.wasm twice.',
      );
    });
  });

  group('the vendored fallback fonts are actually present', () {
    test('every font the app can ask for is on disk and is a woff2', () {
      final fonts = Directory('web/fallback-fonts')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.woff2'))
          .toList();

      expect(
        fonts.length,
        greaterThanOrEqualTo(10),
        reason:
            'web/fallback-fonts/README.md lists what has to be here and '
            'how to re-derive it. A missing shard renders as a tofu box.',
      );

      for (final font in fonts) {
        expect(
          font.readAsBytesSync().take(4).toList(),
          // 'wOF2'
          [0x77, 0x4F, 0x46, 0x32],
          reason:
              '${font.path} is not a woff2 file. A failed download that '
              'saved an error page would look exactly like this.',
        );
      }
    });
  });
}
