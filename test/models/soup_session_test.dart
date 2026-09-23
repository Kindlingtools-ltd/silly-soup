import 'package:flutter_test/flutter_test.dart';
import 'package:silly_soup/models/models.dart';

import '../test_data.dart';

SoupSession session() => SoupSession(
  sound: soundS,
  pantry: [word('sun', 's'), word('sock', 's'), word('soup', 's')],
);

void main() {
  group('adding to the pot', () {
    test('an item moves from the shelf into the pot', () {
      final next = session().addToPot(word('sun', 's'));

      expect(next.pot.map((item) => item.word), ['sun']);
      expect(next.pantry.map((item) => item.word), ['sock', 'soup']);
    });

    test('the pot keeps the order the child chose', () {
      final next = session()
          .addToPot(word('soup', 's'))
          .addToPot(word('sun', 's'))
          .addToPot(word('sock', 's'));

      expect(next.pot.map((item) => item.word), ['soup', 'sun', 'sock']);
    });

    test('the same picture can never be in the pot twice', () {
      final next = session()
          .addToPot(word('sun', 's'))
          .addToPot(word('sun', 's'));

      expect(next.pot.map((item) => item.word), ['sun']);
    });

    test('an item that is not on the shelf is ignored', () {
      final start = session();

      expect(start.addToPot(word('banana', 'b')).pot, isEmpty);
    });

    test('the child can put everything in', () {
      var current = session();
      for (final item in [...current.pantry]) {
        current = current.addToPot(item);
      }

      expect(current.pot, hasLength(3));
      expect(current.isPantryEmpty, isTrue);
    });
  });

  group('taking back out', () {
    test('an item goes back on the shelf', () {
      final next = session()
          .addToPot(word('sun', 's'))
          .removeFromPot(word('sun', 's'));

      expect(next.pot, isEmpty);
      expect(next.pantry.map((item) => item.word), contains('sun'));
    });

    test('removing something that is not in the pot changes nothing', () {
      final start = session();

      expect(start.removeFromPot(word('sun', 's')).pantry, start.pantry);
    });
  });

  test('the session is immutable — the original is untouched', () {
    final start = session();
    start.addToPot(word('sun', 's'));

    expect(start.pot, isEmpty);
    expect(start.pantry, hasLength(3));
  });

  test('stages move without disturbing the pot', () {
    final next = session()
        .addToPot(word('sun', 's'))
        .withStage(SoupStage.tasting);

    expect(next.stage, SoupStage.tasting);
    expect(next.pot, hasLength(1));
  });
}
