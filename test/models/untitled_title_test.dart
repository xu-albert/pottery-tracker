import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/models/untitled_title.dart';

void main() {
  group('isUntitledTitle', () {
    test('matches generated titles only', () {
      expect(isUntitledTitle('Untitled Piece 1'), isTrue);
      expect(isUntitledTitle('Untitled Piece 42'), isTrue);
      expect(isUntitledTitle('Untitled Piece'), isFalse);
      expect(isUntitledTitle('Untitled Piece 1 bowl'), isFalse);
      expect(isUntitledTitle('untitled piece 1'), isFalse);
      expect(isUntitledTitle('Bowl'), isFalse);
      expect(isUntitledTitle(''), isFalse);
    });
  });

  group('nextUntitledTitle', () {
    test('starts at 1 when nothing is in use', () {
      expect(nextUntitledTitle(const []), 'Untitled Piece 1');
    });

    test('fills the lowest gap rather than appending', () {
      expect(
        nextUntitledTitle(['Untitled Piece 1', 'Untitled Piece 3']),
        'Untitled Piece 2',
      );
    });

    test('continues past a contiguous run', () {
      expect(
        nextUntitledTitle(['Untitled Piece 2', 'Untitled Piece 1']),
        'Untitled Piece 3',
      );
    });

    test('ignores titles that are not generated', () {
      expect(
        nextUntitledTitle(['Bowl', 'Untitled Piece', 'Untitled Piece x']),
        'Untitled Piece 1',
      );
    });
  });
}
