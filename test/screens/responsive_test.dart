import 'dart:convert';
import 'dart:io';

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
const _viewports = <String, Size>{
  'phone portrait': Size(375, 667),
  'tall phone portrait': Size(412, 915),
  'small phone portrait': Size(320, 568),
  'phone landscape': Size(667, 375),
  'short phone landscape': Size(844, 320),
  'tablet portrait': Size(768, 1024),
  'tablet landscape': Size(1024, 768),
};

/// The real content, read off disk.
///
/// `rootBundle` serves the first test in a file and then hangs for every one
/// after it, so everything the app loads at startup comes from the files it
/// ships instead — same content, no platform channel. Anything the app reads
/// and this does not serve hangs the whole file, so this list has to keep up
/// with [WordBankService].
final Map<String, String> _content = {
  for (final path in [
    WordBankService.bankAssetPath,
    WordBankService.scriptAssetPath,
    ClipCatalogue.manifestAssetPath,
  ])
    path: File(path).readAsStringSync(),
};

class _BankBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final content = _content[key];
    if (content != null) {
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(content)));
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

  for (final entry in const <String, Size>{
    'phone landscape': Size(667, 375),
    'phone portrait': Size(375, 667),
    'tablet landscape': Size(1024, 768),
  }.entries) {
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
