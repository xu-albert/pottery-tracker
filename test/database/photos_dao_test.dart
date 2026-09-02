import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    for (final id in ['p1', 'p2']) {
      await db.piecesDao.insertPiece(
        PiecesCompanion.insert(
          id: id,
          createdAt: DateTime(2025, 1, 1),
          updatedAt: DateTime(2025, 1, 1),
        ),
      );
    }
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertPhoto(
    String id, {
    String pieceId = 'p1',
    int sortOrder = 0,
    DateTime? dateTaken,
  }) {
    return db.photosDao.insertPhoto(
      PhotosCompanion.insert(
        id: id,
        pieceId: pieceId,
        localPath: '/tmp/$id.jpg',
        dateTaken: dateTaken ?? DateTime(2025, 1, 1),
        createdAt: DateTime(2025, 1, 1),
        sortOrder: Value(sortOrder),
      ),
    );
  }

  group('PhotosDao ordering', () {
    test('getPhotosForPiece returns highest sortOrder first', () async {
      await insertPhoto('a', sortOrder: 0);
      await insertPhoto('b', sortOrder: 2);
      await insertPhoto('c', sortOrder: 1);
      await insertPhoto('other', pieceId: 'p2', sortOrder: 9);

      final photos = await db.photosDao.getPhotosForPiece('p1');

      expect(photos.map((p) => p.id), ['b', 'c', 'a']);
    });

    test(
      'watchPhotosForPiece uses the same order as getPhotosForPiece',
      () async {
        await insertPhoto('a', sortOrder: 0);
        await insertPhoto('b', sortOrder: 1);

        final watched = await db.photosDao.watchPhotosForPiece('p1').first;

        expect(watched.map((p) => p.id), ['b', 'a']);
      },
    );
  });

  group('PhotosDao.getNextSortOrder', () {
    test('is 0 for a piece with no photos', () async {
      expect(await db.photosDao.getNextSortOrder('p1'), 0);
    });

    test('is one more than the current maximum for that piece only', () async {
      await insertPhoto('a', sortOrder: 4);
      await insertPhoto('b', sortOrder: 1);
      await insertPhoto('other', pieceId: 'p2', sortOrder: 20);

      expect(await db.photosDao.getNextSortOrder('p1'), 5);
      expect(await db.photosDao.getNextSortOrder('p2'), 21);
    });
  });

  group('PhotosDao writes', () {
    test('updateSortOrders applies every entry in one batch', () async {
      await insertPhoto('a', sortOrder: 0);
      await insertPhoto('b', sortOrder: 1);
      await insertPhoto('c', sortOrder: 2);

      await db.photosDao.updateSortOrders([
        (id: 'a', sortOrder: 2),
        (id: 'c', sortOrder: 0),
      ]);

      final photos = await db.photosDao.getPhotosForPiece('p1');
      expect(photos.map((p) => p.id), ['a', 'b', 'c']);
    });

    test(
      'updatePhoto only touches the fields present in the companion',
      () async {
        await insertPhoto('a', sortOrder: 3, dateTaken: DateTime(2025, 1, 1));

        await db.photosDao.updatePhoto(
          PhotosCompanion(
            id: const Value('a'),
            dateTaken: Value(DateTime(2024, 5, 5)),
          ),
        );

        final photo = await db.photosDao.getPhotoById('a');
        expect(photo!.dateTaken, DateTime(2024, 5, 5));
        expect(photo.sortOrder, 3);
        expect(photo.localPath, '/tmp/a.jpg');
      },
    );

    test('deletePhoto removes only that photo', () async {
      await insertPhoto('a');
      await insertPhoto('b');

      await db.photosDao.deletePhoto('a');

      expect(await db.photosDao.getPhotoById('a'), isNull);
      expect(await db.photosDao.getPhotoById('b'), isNotNull);
    });

    test('deletePhotosForPiece leaves other pieces untouched', () async {
      await insertPhoto('a');
      await insertPhoto('b');
      await insertPhoto('other', pieceId: 'p2');

      await db.photosDao.deletePhotosForPiece('p1');

      expect(await db.photosDao.getPhotosForPiece('p1'), isEmpty);
      expect(await db.photosDao.getPhotosForPiece('p2'), hasLength(1));
    });
  });
}
