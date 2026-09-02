import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/models/piece_stage.dart';
import 'package:pottery_tracker/services/image_service.dart';
import 'package:pottery_tracker/services/piece_writer.dart';
import 'package:pottery_tracker/services/sync_queue.dart';
import 'package:pottery_tracker/services/sync_trigger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mock_providers.dart';

void main() {
  late AppDatabase db;
  late SyncQueue queue;
  late MockImageService images;
  late PieceWriter writer;
  final now = DateTime(2025, 3, 4, 5, 6);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    queue = SyncQueue();
    images = MockImageService();
    when(() => images.deletePhotos(any())).thenAnswer((_) async {});
    when(() => images.deletePhotoFiles(any(), any())).thenAnswer((_) async {});
    writer = PieceWriter(
      piecesDao: db.piecesDao,
      photosDao: db.photosDao,
      imageService: images,
      syncTrigger: SyncTrigger(queue),
      now: () => now,
    );
  });

  tearDown(() async {
    await db.close();
  });

  ImageResult image(String id, {DateTime? taken}) => ImageResult(
    photoId: id,
    localPath: '/photos/p/$id.jpg',
    thumbnailPath: '/photos/p/${id}_thumb.jpg',
    dateTaken: taken ?? DateTime(2024, 1, 1),
  );

  Future<void> insertPiece(
    String id, {
    String? title,
    String? coverPhotoId,
    String? stage,
    String? clayType,
    String? notes,
  }) {
    return db.piecesDao.insertPiece(
      PiecesCompanion(
        id: Value(id),
        title: Value(title),
        coverPhotoId: Value(coverPhotoId),
        stage: Value(stage),
        clayType: Value(clayType),
        notes: Value(notes),
        createdAt: Value(DateTime(2020)),
        updatedAt: Value(DateTime(2020)),
      ),
    );
  }

  Future<void> insertPhoto(String id, String pieceId, {int sortOrder = 0}) {
    return db.photosDao.insertPhoto(
      PhotosCompanion.insert(
        id: id,
        pieceId: pieceId,
        localPath: '/photos/$pieceId/$id.jpg',
        dateTaken: DateTime(2024, 1, 1),
        createdAt: DateTime(2024, 1, 1),
        sortOrder: Value(sortOrder),
      ),
    );
  }

  Future<List<(SyncOperation, String)>> queued() async {
    final all = await queue.getAll();
    return all.map((e) => (e.operation, e.entityId)).toList();
  }

  group('createPiece', () {
    test(
      'inserts the piece, its photos in order, and queues every one',
      () async {
        await insertPiece('existing', title: 'Untitled Piece 1');

        final title = await writer.createPiece(
          pieceId: 'p',
          photos: [image('a'), image('b'), image('c')],
        );

        expect(title, 'Untitled Piece 2');
        final piece = await db.piecesDao.getPieceById('p');
        expect(piece!.title, 'Untitled Piece 2');
        expect(piece.coverPhotoId, 'c');
        expect(piece.createdAt, now);
        expect(piece.updatedAt, now);

        final photos = await db.photosDao.getPhotosForPiece('p');
        expect(photos.map((p) => p.id), ['c', 'b', 'a']);
        expect(photos.map((p) => p.sortOrder), [2, 1, 0]);
        expect(photos.every((p) => p.createdAt == now), isTrue);
        expect(photos.last.localPath, '/photos/p/a.jpg');
        expect(photos.last.thumbnailPath, '/photos/p/a_thumb.jpg');

        expect(await queued(), [
          (SyncOperation.pushPiece, 'p'),
          (SyncOperation.pushPhoto, 'a'),
          (SyncOperation.pushPhotoFile, 'a'),
          (SyncOperation.pushPhoto, 'b'),
          (SyncOperation.pushPhotoFile, 'b'),
          (SyncOperation.pushPhoto, 'c'),
          (SyncOperation.pushPhotoFile, 'c'),
        ]);
      },
    );
  });

  group('addPhoto', () {
    test(
      'stores the processed image and queues the row and the file',
      () async {
        await insertPiece('p');

        await writer.addPhoto(
          pieceId: 'p',
          photo: image('a', taken: DateTime(2023, 7, 7)),
          sortOrder: 4,
        );

        final photo = await db.photosDao.getPhotoById('a');
        expect(photo!.pieceId, 'p');
        expect(photo.sortOrder, 4);
        expect(photo.dateTaken, DateTime(2023, 7, 7));
        expect(photo.createdAt, now);
        expect(await queued(), [
          (SyncOperation.pushPhoto, 'a'),
          (SyncOperation.pushPhotoFile, 'a'),
        ]);
      },
    );
  });

  group('setCoverPhoto', () {
    test('updates the cover and bumps updatedAt', () async {
      await insertPiece('p', coverPhotoId: 'old');

      await writer.setCoverPhoto('p', 'new');

      final piece = await db.piecesDao.getPieceById('p');
      expect(piece!.coverPhotoId, 'new');
      expect(piece.updatedAt, now);
      expect(await queued(), [(SyncOperation.pushPiece, 'p')]);
    });

    test('null clears the cover', () async {
      await insertPiece('p', coverPhotoId: 'old');

      await writer.setCoverPhoto('p', null);

      expect((await db.piecesDao.getPieceById('p'))!.coverPhotoId, isNull);
    });
  });

  group('deletePhoto', () {
    test('removes the row and files and queues the deletion', () async {
      await insertPiece('p', coverPhotoId: 'keep');
      await insertPhoto('keep', 'p', sortOrder: 1);
      await insertPhoto('gone', 'p', sortOrder: 0);

      await writer.deletePhoto(
        pieceId: 'p',
        photoId: 'gone',
        coverPhotoId: 'keep',
      );

      expect(await db.photosDao.getPhotoById('gone'), isNull);
      verify(() => images.deletePhotoFiles('p', 'gone')).called(1);
      expect((await db.piecesDao.getPieceById('p'))!.coverPhotoId, 'keep');
      expect(await queued(), [(SyncOperation.deletePhoto, 'gone')]);
    });

    test('reassigns the cover to the top-sorted remaining photo', () async {
      await insertPiece('p', coverPhotoId: 'cover');
      await insertPhoto('cover', 'p', sortOrder: 2);
      await insertPhoto('mid', 'p', sortOrder: 1);
      await insertPhoto('low', 'p', sortOrder: 0);

      await writer.deletePhoto(
        pieceId: 'p',
        photoId: 'cover',
        coverPhotoId: 'cover',
      );

      final piece = await db.piecesDao.getPieceById('p');
      expect(piece!.coverPhotoId, 'mid');
      expect(piece.updatedAt, now);
      expect(await queued(), [
        (SyncOperation.deletePhoto, 'cover'),
        (SyncOperation.pushPiece, 'p'),
      ]);
    });

    test('clears the cover when the last photo goes', () async {
      await insertPiece('p', coverPhotoId: 'only');
      await insertPhoto('only', 'p');

      await writer.deletePhoto(
        pieceId: 'p',
        photoId: 'only',
        coverPhotoId: 'only',
      );

      expect((await db.piecesDao.getPieceById('p'))!.coverPhotoId, isNull);
    });

    test('without a cover id it never touches the piece', () async {
      await insertPiece('p', coverPhotoId: 'a');
      await insertPhoto('a', 'p');

      await writer.deletePhoto(pieceId: 'p', photoId: 'a');

      final piece = await db.piecesDao.getPieceById('p');
      expect(piece!.coverPhotoId, 'a');
      expect(piece.updatedAt, DateTime(2020));
      expect(await queued(), [(SyncOperation.deletePhoto, 'a')]);
    });
  });

  group('reorderPhotos', () {
    test('first in the list gets the highest sort order', () async {
      await insertPiece('p');
      await insertPhoto('a', 'p', sortOrder: 2);
      await insertPhoto('b', 'p', sortOrder: 1);
      await insertPhoto('c', 'p', sortOrder: 0);

      await writer.reorderPhotos(['c', 'a', 'b']);

      final photos = await db.photosDao.getPhotosForPiece('p');
      expect(photos.map((p) => p.id), ['c', 'a', 'b']);
      expect(photos.map((p) => p.sortOrder), [2, 1, 0]);
      expect(await queued(), [
        (SyncOperation.pushPhoto, 'c'),
        (SyncOperation.pushPhoto, 'a'),
        (SyncOperation.pushPhoto, 'b'),
      ]);
    });

    test('an empty list is a no-op', () async {
      await writer.reorderPhotos(const []);

      expect(await queued(), isEmpty);
    });
  });

  group('deletePiece', () {
    test('removes the piece, its photos and files, and queues each', () async {
      await insertPiece('p');
      await insertPhoto('a', 'p', sortOrder: 1);
      await insertPhoto('b', 'p', sortOrder: 0);
      await insertPiece('other');
      await insertPhoto('x', 'other');

      await writer.deletePiece('p');

      expect(await db.piecesDao.getPieceById('p'), isNull);
      expect(await db.photosDao.getPhotosForPiece('p'), isEmpty);
      expect(await db.photosDao.getPhotosForPiece('other'), hasLength(1));
      verify(() => images.deletePhotos('p')).called(1);
      expect(await queued(), [
        (SyncOperation.deletePhoto, 'a'),
        (SyncOperation.deletePhoto, 'b'),
        (SyncOperation.deletePiece, 'p'),
      ]);
    });
  });

  group('setArchived', () {
    test('flips the flag and bumps updatedAt', () async {
      await insertPiece('p');

      await writer.setArchived('p', true);
      var piece = await db.piecesDao.getPieceById('p');
      expect(piece!.isArchived, isTrue);
      expect(piece.updatedAt, now);

      await writer.setArchived('p', false);
      piece = await db.piecesDao.getPieceById('p');
      expect(piece!.isArchived, isFalse);

      expect(await queued(), [(SyncOperation.pushPiece, 'p')]);
    });
  });

  group('updateFields', () {
    test('writes the given fields and leaves the rest alone', () async {
      await insertPiece('p', title: 'Old', clayType: 'Stoneware', notes: 'n');

      await writer.updateFields('p', title: 'New', stage: PieceStage.bisqued);

      final piece = await db.piecesDao.getPieceById('p');
      expect(piece!.title, 'New');
      expect(piece.stage, 'bisqued');
      expect(piece.clayType, 'Stoneware');
      expect(piece.notes, 'n');
      expect(piece.updatedAt, now);
      expect(await queued(), [(SyncOperation.pushPiece, 'p')]);
    });

    test('empty strings are stored as null', () async {
      await insertPiece('p', title: 'Old', clayType: 'Stoneware', notes: 'n');

      await writer.updateFields('p', title: '', clayType: '', notes: '');

      final piece = await db.piecesDao.getPieceById('p');
      expect(piece!.title, isNull);
      expect(piece.clayType, isNull);
      expect(piece.notes, isNull);
    });

    test('clearStage nulls the stage even if a stage is passed', () async {
      await insertPiece('p', stage: 'glazed');

      await writer.updateFields(
        'p',
        stage: PieceStage.greenware,
        clearStage: true,
      );

      expect((await db.piecesDao.getPieceById('p'))!.stage, isNull);
    });
  });

  group('dates', () {
    test('setDisplayDate stores the date and queues the piece', () async {
      await insertPiece('p');

      await writer.setDisplayDate('p', DateTime(2022, 2, 2));

      final piece = await db.piecesDao.getPieceById('p');
      expect(piece!.displayDate, DateTime(2022, 2, 2));
      expect(piece.updatedAt, now);
      expect(await queued(), [(SyncOperation.pushPiece, 'p')]);
    });

    test('setPhotoDate queues the photo row but not its file', () async {
      await insertPiece('p');
      await insertPhoto('a', 'p');

      await writer.setPhotoDate('a', DateTime(2022, 2, 2));

      expect(
        (await db.photosDao.getPhotoById('a'))!.dateTaken,
        DateTime(2022, 2, 2),
      );
      expect(await queued(), [(SyncOperation.pushPhoto, 'a')]);
    });
  });
}
