import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/models/display_date.dart';

import '../helpers/fixtures.dart';

void main() {
  group('resolveDisplayDate', () {
    test('an explicit displayDate wins over photos and createdAt', () {
      final piece = makePiece(
        displayDate: DateTime(2023, 3, 3),
        createdAt: DateTime(2025, 1, 1),
      );
      final photos = [makePhoto(dateTaken: DateTime(2025, 6, 6))];

      expect(resolveDisplayDate(piece, photos), DateTime(2023, 3, 3));
    });

    test('falls back to the most recent photo regardless of list order', () {
      final piece = makePiece(createdAt: DateTime(2025, 1, 1));
      final photos = [
        makePhoto(id: 'a', dateTaken: DateTime(2024, 2, 2)),
        makePhoto(id: 'b', dateTaken: DateTime(2024, 9, 9)),
        makePhoto(id: 'c', dateTaken: DateTime(2024, 5, 5)),
      ];

      expect(resolveDisplayDate(piece, photos), DateTime(2024, 9, 9));
    });

    test('falls back to createdAt when there are no photos', () {
      final piece = makePiece(createdAt: DateTime(2025, 1, 1));

      expect(resolveDisplayDate(piece, const []), DateTime(2025, 1, 1));
    });

    test('a photo older than createdAt still dates the piece', () {
      final piece = makePiece(createdAt: DateTime(2025, 1, 1));
      final photos = [makePhoto(dateTaken: DateTime(2020, 1, 1))];

      expect(resolveDisplayDate(piece, photos), DateTime(2020, 1, 1));
    });
  });
}
