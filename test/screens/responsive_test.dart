import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:silly_soup/providers/providers.dart';
import 'package:silly_soup/screens/screens.dart';
import 'package:silly_soup/services/services.dart';
import 'package:silly_soup/utils/utils.dart';
import 'package:silly_soup/widgets/widgets.dart';

/// The screens this app actually gets held up to.
///
/// The app was built for a tablet in landscape and locked to it, so a phone
/// got a layout that ran off both edges — the pantry shelf, the one thing a
/// child has to reach, ended up below the bottom of the screen. Every size
/// here is a device someone will genuinely open this on.
///
/// Deliberately not an iOS list. A nursery's tablets are as likely to be a
/// Fire HD or a Galaxy Tab as an iPad, and the narrowest screen the app has
/// to survive — 320 logical pixels — is a budget Android in portrait, not an
/// iPhone. Sizes are CSS/logical pixels, which is what the layout sees; the
/// device pixel ratio does not change any of the decisions below.
const _portraits = <String, Size>{
  // Android phones
  'budget Android phone': Size(360, 640),
  'Galaxy S phone': Size(360, 780),
  'Pixel 5': Size(393, 851),
  'Pixel 8 / Galaxy A54': Size(412, 915),
  // iPhones
  'iPhone SE (1st gen)': Size(320, 568),
  'iPhone SE / 8': Size(375, 667),
  'iPhone 14': Size(390, 844),
  'iPhone 15 Pro Max': Size(430, 932),
  // Android, Fire and iPad tablets
  'Fire HD 8': Size(600, 960),
  'Galaxy Tab A8': Size(800, 1280),
  'iPad mini': Size(768, 1024),
  'iPad 10.2': Size(810, 1080),
  'iPad Air': Size(834, 1194),
  'iPad Pro 12.9': Size(1024, 1366),
};

/// Every portrait size above, plus its landscape twin, plus the two shapes
/// that only exist one way round.
final _viewports = <String, Size>{
  for (final entry in _portraits.entries) ...{
    '${entry.key} portrait': entry.value,
    '${entry.key} landscape': entry.value.flipped,
  },
  // A phone in landscape with the browser's own chrome on top: the shortest
  // window the app is ever given.
  'short phone landscape': const Size(844, 320),
  // A classroom laptop or an interactive whiteboard.
  'classroom Chromebook': const Size(1366, 768),
};

/// The real sound bank, read off disk.
///
/// `rootBundle` serves the first test in a file and then hangs for every one
/// after it, so the bank comes from the file the app ships instead — same
/// content, no platform channel.
final String _bankJson = File('assets/data/sound_bank.json').readAsStringSync();

class _BankBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == WordBankService.bankAssetPath) {
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(_bankJson)));
    }
    throw FlutterError('No test asset for $key');
  }
}

Future<AppProvider> _app() async {
  SharedPreferences.setMockInitialValues({});
  final app = AppProvider(
    audio: AudioService(sink: RecordingAudioSink()),
    wordBank: WordBankService(bundle: _BankBundle()),
  );
  await app.initialise();
  return app;
}

Widget _host(AppProvider app, Widget child) => ChangeNotifierProvider.value(
  value: app,
  child: MaterialApp(theme: AppTheme.lightTheme, home: child),
);

/// Renders [build] at [size] and returns every overflow the frame reported.
///
/// `takeException` only ever surfaces the first, and a squeezed layout
/// usually produces several.
Future<List<String>> _overflowsAt(
  WidgetTester tester,
  Size size,
  Future<Widget> Function() build,
) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    if (message.contains('overflowed')) {
      overflows.add(message.split('\n').first);
    } else {
      previous?.call(details);
    }
  };
  addTearDown(() => FlutterError.onError = previous);

  await tester.pumpWidget(await build());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  // Unmount, then let the chef's timers run out, so nothing carries into
  // the next test.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 30));
  return overflows;
}

void main() {
  for (final entry in _viewports.entries) {
    final name = entry.key;
    final size = entry.value;

    testWidgets('the sound picker fits a $name', (tester) async {
      final overflows = await _overflowsAt(tester, size, () async {
        final app = await _app();
        return _host(app, const HomeScreen());
      });

      expect(overflows, isEmpty);
    });

    testWidgets('the kitchen fits a $name', (tester) async {
      final overflows = await _overflowsAt(tester, size, () async {
        final app = await _app();
        return _host(app, SoupScreen(sound: app.availableSounds.first));
      });

      expect(overflows, isEmpty);
    });

    testWidgets('the grown-ups\' area fits a $name', (tester) async {
      final overflows = await _overflowsAt(tester, size, () async {
        final app = await _app();
        return _host(app, const AdultScreen());
      });

      expect(overflows, isEmpty);
    });

    testWidgets('watch my mouth fits a $name', (tester) async {
      final overflows = await _overflowsAt(tester, size, () async {
        final app = await _app();
        return _host(app, MouthScreen(sound: app.availableSounds.first));
      });

      expect(overflows, isEmpty);
    });
  }

  for (final entry in _viewports.entries) {
    testWidgets('every sound is on screen on a ${entry.key}', (tester) async {
      // The picker scrolls, so a sound below the fold is not an overflow and
      // no test above notices it. But a three-year-old is not going to
      // discover a sound by swiping a screen that gives no sign there is
      // anything under it — the same way the pantry used to hide.
      final size = entry.value;
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final app = await _app();
      await tester.pumpWidget(_host(app, const HomeScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The picker is inside a scroll view, so "on screen" means inside what
      // that view actually shows, not merely inside the window.
      final visible = tester
          .getRect(find.byType(SingleChildScrollView))
          .intersect(Offset.zero & size);

      final cards = find.byType(SoundCard);
      expect(cards, findsWidgets);
      for (final card in cards.evaluate()) {
        final rect = tester.getRect(find.byWidget(card.widget));
        expect(
          rect.top >= visible.top - 0.01 &&
              rect.bottom <= visible.bottom + 0.01 &&
              rect.left >= visible.left - 0.01 &&
              rect.right <= visible.right + 0.01,
          isTrue,
          reason:
              'a sound card at $rect is outside the $visible the picker '
              'shows on a ${size.width.toInt()}x${size.height.toInt()} '
              'screen, so a child would have to scroll to find it',
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
    });
  }

  for (final entry in _viewports.entries) {
    testWidgets('a child can reach the pantry on a ${entry.key}', (
      tester,
    ) async {
      // The bug this is here for: the shelf was stacked under the pot inside
      // a scroll view, so on a phone a child saw a pot and no ingredients at
      // all — and nothing on screen said to scroll.
      final size = entry.value;
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final app = await _app();
      await tester.pumpWidget(
        _host(app, SoupScreen(sound: app.availableSounds.first)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final screen = Offset.zero & size;
      final reachable = find
          .byType(IngredientCard)
          .evaluate()
          .map((card) => tester.getRect(find.byWidget(card.widget)))
          .where(
            (rect) =>
                rect.top >= screen.top &&
                rect.bottom <= screen.bottom &&
                rect.left >= screen.left &&
                rect.right <= screen.right,
          )
          .length;

      expect(
        reachable,
        greaterThanOrEqualTo(3),
        reason:
            'a whole row of ingredients should be on screen without '
            'scrolling',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
    });
  }

  for (final entry in _viewports.entries) {
    testWidgets("the grown-ups' sound list stays readable on a ${entry.key}", (
      tester,
    ) async {
      // A layout can be legal and still be unusable. Each row of this list
      // carries the sound, a word count, an optional note, two reorder
      // arrows and a switch; on a 360px phone the text was left about twenty
      // pixels and wrapped one character to a line, so a nine-sound list was
      // a screen and a half of letter towers. Nothing overflowed, so the
      // overflow tests above all passed.
      final size = entry.value;
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final app = await _app();
      await tester.pumpWidget(_host(app, const AdultScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final rows = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_SoundRow',
      );
      expect(rows, findsWidgets);

      for (final row in rows.evaluate()) {
        final finder = find.byWidget(row.widget);
        // Six lines of a long note is the most any of these should need.
        expect(
          tester.getSize(finder).height,
          lessThanOrEqualTo(300),
          reason: 'a sound row has grown into a column of wrapped text',
        );
        for (final text
            in find
                .descendant(of: finder, matching: find.byType(Text))
                .evaluate()) {
          final label = (text.widget as Text).data ?? '';
          if (label.length < 8) continue; // the sound itself is short
          final box = tester.renderObject<RenderBox>(
            find.byWidget(text.widget),
          );
          // What one unwrapped line would take. A short label should be given
          // all of it; a long one should get at least a readable slice,
          // rather than two words to a line.
          final wanted = math.min(
            box.getMaxIntrinsicWidth(double.infinity),
            150.0,
          );
          expect(
            box.size.width,
            greaterThanOrEqualTo(wanted),
            reason: '"$label" has been squeezed too narrow to read',
          );
        }
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 30));
    });
  }

  testWidgets('every ingredient stays a full-size tap target', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 568 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final app = await _app();
    await tester.pumpWidget(
      _host(app, SoupScreen(sound: app.availableSounds.first)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    for (final card in find.byType(IngredientCard).evaluate()) {
      final size = tester.getSize(find.byWidget(card.widget));
      expect(size.width, greaterThanOrEqualTo(SoupMetrics.minTapTarget));
      expect(size.height, greaterThanOrEqualTo(SoupMetrics.minTapTarget));
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
  });
}
