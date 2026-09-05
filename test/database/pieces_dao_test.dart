import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertPiece(
    String id, {
    String? title,
    String? stage,
    String? clayType,
    String? glazes,
    String? tags,
    String? notes,
    String? coverPhotoId,
    bool isArchived = false,
    DateTime? createdAt,
  }) {
    final now = createdAt ?? DateTime(2025, 1, 1);
    return db.piecesDao.insertPiece(
      PiecesCompanion(
        id: Value(id),
        title: Value(title),
        stage: Value(stage),
        clayType: Value(clayType),
        glazes: Value(glazes),
        tags: Value(tags),
        notes: Value(notes),
        coverPhotoId: Value(coverPhotoId),
        isArchived: Value(isArchived),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> insertPhoto(String id, String pieceId) {
    return db.photosDao.insertPhoto(
      PhotosCompanion.insert(
        id: id,
        pieceId: pieceId,
        localPath: '/tmp/$id.jpg',
        dateTaken: DateTime(2025, 1, 1),
        createdAt: DateTime(2025, 1, 1),
      ),
    );
  }

  group('PiecesDao.watchAllPieces', () {
    test(
      'excludes archived pieces by default and orders newest first',
      () async {
        await insertPiece('old', title: 'Old', createdAt: DateTime(2024, 1, 1));
        await insertPiece('new', title: 'New', createdAt: DateTime(2025, 6, 1));
        await insertPiece('archived', title: 'Archived', isArchived: true);

        final rows = await db.piecesDao.watchAllPieces().first;

        expect(rows.map((r) => r.piece.id), ['new', 'old']);
      },
    );

    test('archivedOnly returns only archived pieces', () async {
      await insertPiece('active', title: 'Active');
      await insertPiece('archived', title: 'Archived', isArchived: true);

      final rows = await db.piecesDao.watchAllPieces(archivedOnly: true).first;

      expect(rows.map((r) => r.piece.id), ['archived']);
    });

    test(
      'joins the cover photo when set and leaves it null otherwise',
      () async {
        await insertPiece('with-cover', coverPhotoId: 'ph1');
        await insertPiece('no-cover');
        await insertPhoto('ph1', 'with-cover');

        final rows = await db.piecesDao.watchAllPieces().first;
        final byId = {for (final r in rows) r.piece.id: r};

        expect(byId['with-cover']!.coverPhoto?.id, 'ph1');
        expect(byId['no-cover']!.coverPhoto, isNull);
      },
    );

    test('search matches title, stage, clay, glazes, tags and notes', () async {
      await insertPiece('t', title: 'Blue Bowl');
      await insertPiece('s', stage: 'glazed');
      await insertPiece('c', clayType: 'Stoneware');
      await insertPiece('g', glazes: 'Celadon, Tenmoku');
      await insertPiece('tag', tags: 'gift');
      await insertPiece('n', notes: 'thrown on the wheel');
      await insertPiece('none', title: 'Mug');

      Future<Set<String>> search(String q) async {
        final rows = await db.piecesDao.watchAllPieces(searchQuery: q).first;
        return rows.map((r) => r.piece.id).toSet();
      }

      expect(await search('Bowl'), {'t'});
      expect(await search('glazed'), {'s'});
      expect(await search('Stoneware'), {'c'});
      expect(await search('Tenmoku'), {'g'});
      expect(await search('gift'), {'tag'});
      expect(await search('wheel'), {'n'});
      expect(await search('zzz'), isEmpty);
    });

    test('search is a substring match and is not case sensitive', () async {
      await insertPiece('p', title: 'Celadon Vase');

      final rows = await db.piecesDao
          .watchAllPieces(searchQuery: 'ladon v')
          .first;

      expect(rows.map((r) => r.piece.id), ['p']);
    });

    test('empty search query returns everything', () async {
      await insertPiece('a');
      await insertPiece('b');

      final rows = await db.piecesDao.watchAllPieces(searchQuery: '').first;

      expect(rows, hasLength(2));
    });

    test('search still respects the archived filter', () async {
      await insertPiece('active', title: 'Bowl');
      await insertPiece('archived', title: 'Bowl', isArchived: true);

      final active = await db.piecesDao
          .watchAllPieces(searchQuery: 'Bowl')
          .first;
      final archived = await db.piecesDao
          .watchAllPieces(searchQuery: 'Bowl', archivedOnly: true)
          .first;

      expect(active.map((r) => r.piece.id), ['active']);
      expect(archived.map((r) => r.piece.id), ['archived']);
    });

    test('emits again when a piece changes', () async {
      await insertPiece('p', title: 'Before');
      final stream = db.piecesDao.watchAllPieces();
      final first = await stream.first;
      expect(first.single.piece.title, 'Before');

      final second = stream.skip(1).first;
      await db.piecesDao.updatePiece(
        PiecesCompanion(id: const Value('p'), title: const Value('After')),
      );

      expect((await second).single.piece.title, 'After');
    });
  });

  group('PiecesDao writes', () {
    test(
      'updatePiece only touches the fields present in the companion',
      () async {
        await insertPiece('p', title: 'Title', notes: 'Notes');

        await db.piecesDao.updatePiece(
          PiecesCompanion(id: const Value('p'), title: const Value('New')),
        );

        final piece = await db.piecesDao.getPieceById('p');
        expect(piece!.title, 'New');
        expect(piece.notes, 'Notes');
      },
    );

    test('deletePiece removes the row and getPieceById returns null', () async {
      await insertPiece('p');

      await db.piecesDao.deletePiece('p');

      expect(await db.piecesDao.getPieceById('p'), isNull);
    });

    test('countPieces counts archived and active pieces alike', () async {
      expect(await db.piecesDao.countPieces(), 0);
      await insertPiece('a');
      await insertPiece('b', isArchived: true);

      expect(await db.piecesDao.countPieces(), 2);
    });

    test('getUntitledPieceTitles returns only auto-generated titles', () async {
      await insertPiece('u1', title: 'Untitled Piece 1');
      await insertPiece('u3', title: 'Untitled Piece 3');
      await insertPiece('named', title: 'Bowl');
      await insertPiece('nil', title: null);

      final titles = await db.piecesDao.getUntitledPieceTitles();

      expect(titles, unorderedEquals(['Untitled Piece 1', 'Untitled Piece 3']));
    });
  });
}
