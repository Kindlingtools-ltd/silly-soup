import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/services/services.dart';

/// The list of recordings this build has.
///
/// The app asks it whether a whole line is recorded before playing any of it,
/// so getting this wrong means the chef stops mid-sentence.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('answering for a line', () {
    final library = ClipLibrary.withClips(const {
      'assets/audio/lines/in_goes.mp3',
      'assets/audio/list/sun.mp3',
    });

    test('knows what it has', () {
      expect(library.has('assets/audio/list/sun.mp3'), isTrue);
      expect(library.has('assets/audio/list/sock.mp3'), isFalse);
      expect(library.length, 2);
    });

    test('a line is only complete when every clip is there', () {
      expect(
        library.hasAll(const [
          'assets/audio/lines/in_goes.mp3',
          'assets/audio/list/sun.mp3',
        ]),
        isTrue,
      );
      expect(
        library.hasAll(const [
          'assets/audio/lines/in_goes.mp3',
          'assets/audio/list/sock.mp3',
        ]),
        isFalse,
      );
    });

    test('an empty library has nothing, and says so rather than throwing', () {
      const empty = ClipLibrary.empty();

      expect(empty.length, 0);
      expect(empty.has('assets/audio/list/sun.mp3'), isFalse);
      expect(empty.hasAll(const ['assets/audio/list/sun.mp3']), isFalse);
    });
  });

  group('reading the manifest', () {
    test('paths in the manifest are relative to the audio root', () async {
      final bundle = _FakeBundle({
        ClipLibrary.manifestAsset: json.encode({
          'voice': 'eve',
          'clips': ['phonemes/s.mp3', 'list/sun.mp3'],
        }),
      });

      final library = await ClipLibrary.load(bundle: bundle);

      expect(library.has('assets/audio/phonemes/s.mp3'), isTrue);
      expect(library.has('assets/audio/list/sun.mp3'), isTrue);
      expect(library.length, 2);
    });

    test('a missing manifest means speech, not a crash', () async {
      // This is how the app behaves in a checkout where the clips have not
      // been built: every line falls back to the device voice.
      final library = await ClipLibrary.load(bundle: _FakeBundle(const {}));

      expect(library.length, 0);
    });

    test('an unreadable manifest means speech, not a crash', () async {
      final bundle = _FakeBundle({ClipLibrary.manifestAsset: 'not json'});

      final library = await ClipLibrary.load(bundle: bundle);

      expect(library.length, 0);
    });
  });
}

class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this._assets);

  final Map<String, String> _assets;

  @override
  Future<ByteData> load(String key) async {
    final contents = _assets[key];
    if (contents == null) throw FlutterError('no asset $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(contents)));
  }
}
