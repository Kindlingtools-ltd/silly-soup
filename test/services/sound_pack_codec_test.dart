import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/models/models.dart';
import 'package:silly_soup/services/services.dart';

import '../test_data.dart';

void main() {
  group('export', () {
    test('writes readable JSON a teacher could open', () {
      final encoded = SoundPackCodec.encode(testBank, name: 'Class 1 pack');
      final decoded = json.decode(encoded) as Map<String, dynamic>;

      expect(decoded['schemaVersion'], SoundBank.currentSchemaVersion);
      expect(decoded['name'], 'Class 1 pack');
      expect(decoded['exportedAt'], isA<String>());
      expect(encoded, contains('\n  '), reason: 'indented, not one long line');
    });
  });

  group('import', () {
    test('a pack this app wrote imports again', () {
      final result = SoundPackCodec.decode(SoundPackCodec.encode(testBank));

      expect(result.isValid, isTrue);
      expect(
        result.bank!.words.map((item) => item.id),
        testBank.words.map((item) => item.id),
      );
    });

    test('a file that is not JSON is refused', () {
      final result = SoundPackCodec.decode('this is not a sound pack');

      expect(result.isValid, isFalse);
      expect(result.bank, isNull);
      expect(result.validation.errors, isNotEmpty);
    });

    test('an invalid pack is refused and nothing is handed over', () {
      final result = SoundPackCodec.decode(
        json.encode({
          'schemaVersion': 1,
          'sounds': [
            {'id': 's', 'pureSound': 'sss'},
          ],
          'words': [
            {'word': 'sun', 'phoneme': 's', 'image': ''},
          ],
        }),
      );

      expect(result.isValid, isFalse);
      expect(result.bank, isNull);
    });

    test('a pack with only warnings still imports', () {
      final result = SoundPackCodec.decode(
        json.encode({
          'schemaVersion': 1,
          'sounds': [
            {'id': 's', 'pureSound': 'sss'},
          ],
          'words': [
            {'word': 'sun', 'phoneme': 's', 'image': 'emoji:☀️'},
          ],
        }),
      );

      expect(result.isValid, isTrue);
      expect(result.validation.hasWarnings, isTrue);
      expect(result.bank!.wordsFor('s'), hasLength(1));
    });

    test('a pack from a newer app version is refused', () {
      final result = SoundPackCodec.decode(
        json.encode({
          'schemaVersion': SoundBank.currentSchemaVersion + 1,
          'sounds': <Object>[],
          'words': <Object>[],
        }),
      );

      expect(result.isValid, isFalse);
    });
  });
}
