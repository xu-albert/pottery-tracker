import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uid = 'test-user';

void main() {
  late AppDatabase db;
  late FakeFirebaseFirestore firestore;
  late MockFirebaseStorage storage;
  late SyncService syncService;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    firestore = FakeFirebaseFirestore();
    storage = MockFirebaseStorage();
    syncService = SyncService(db, firestore, storage);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await db.close();
  });

  // ── Helpers ────────────────────────────────────

  Future<Piece> insertPiece({
    required String id,
    String? title,
    String? stage,
    String? clayType,
    String? notes,
  }) async {
    final now = DateTime.now();
    await db.piecesDao.insertPiece(
      PiecesCompanion(
        id: Value(id),
        title: Value(title),
        stage: Value(stage),
        clayType: Value(clayType),
        notes: Value(notes),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return (await db.piecesDao.getPieceById(id))!;
  }

  Future<Photo> insertPhoto({
    required String id,
    required String pieceId,
    String? cloudUrl,
    int sortOrder = 0,
  }) async {
    final now = DateTime.now();
    await db.photosDao.insertPhoto(
      PhotosCompanion(
        id: Value(id),
        pieceId: Value(pieceId),
        localPath: Value('/tmp/photos/$pieceId/$id.jpg'),
        cloudUrl: Value(cloudUrl),
        dateTaken: Value(now),
        createdAt: Value(now),
        sortOrder: Value(sortOrder),
      ),
    );
    return (await db.photosDao.getPhotoById(id))!;
  }

  Future<ClayOption> insertClay({
    required String id,
    required String name,
    int sortOrder = 0,
  }) async {
    await db
        .into(db.clayOptions)
        .insert(
          ClayOptionsCompanion.insert(
            id: id,
            name: name,
            sortOrder: Value(sortOrder),
            createdAt: DateTime.now(),
          ),
        );
    final all = await db.materialsDao.getAllClays();
    return all.firstWhere((c) => c.id == id);
  }

  Future<GlazeOption> insertGlaze({
    required String id,
    required String name,
    int sortOrder = 0,
  }) async {
    await db
        .into(db.glazeOptions)
        .insert(
          GlazeOptionsCompanion.insert(
            id: id,
            name: name,
            sortOrder: Value(sortOrder),
            createdAt: DateTime.now(),
          ),
        );
    final all = await db.materialsDao.getAllGlazes();
    return all.firstWhere((g) => g.id == id);
  }

  Future<TagOption> insertTag({
    required String id,
    required String name,
    String? color,
    int sortOrder = 0,
  }) async {
    await db
        .into(db.tagOptions)
        .insert(
          TagOptionsCompanion.insert(
            id: id,
            name: name,
            color: Value(color),
            sortOrder: Value(sortOrder),
            createdAt: DateTime.now(),
          ),
        );
    final all = await db.materialsDao.getAllTags();
    return all.firstWhere((t) => t.id == id);
  }

  CollectionReference col(String name) =>
      firestore.doc('users/$_uid').collection(name);

  // ── Push tests ─────────────────────────────────

  group('pushPiece', () {
    test('writes piece data to Firestore', () async {
      await insertPiece(
        id: 'p1',
        title: 'My Bowl',
        stage: 'bisqued',
        clayType: 'Stoneware',
        notes: 'First attempt',
      );

      await syncService.pushPiece(_uid, 'p1');

      final doc = await col('pieces').doc('p1').get();
      final data = doc.data() as Map<String, dynamic>;
      expect(data['title'], 'My Bowl');
      expect(data['stage'], 'bisqued');
      expect(data['clayType'], 'Stoneware');
      expect(data['notes'], 'First attempt');
      expect(data['isArchived'], false);
      expect(data['createdAt'], isA<Timestamp>());
      expect(data['updatedAt'], isA<Timestamp>());
    });

    test('no-ops when piece does not exist locally', () async {
      await syncService.pushPiece(_uid, 'nonexistent');
      final doc = await col('pieces').doc('nonexistent').get();
      expect(doc.exists, false);
    });
  });

  group('pushPhoto', () {
    test('writes photo metadata to Firestore', () async {
      await insertPiece(id: 'p1');
      await insertPhoto(id: 'ph1', pieceId: 'p1', sortOrder: 2);

      await syncService.pushPhoto(_uid, 'ph1');

      final doc = await col('photos').doc('ph1').get();
      final data = doc.data() as Map<String, dynamic>;
      expect(data['pieceId'], 'p1');
      expect(data['sortOrder'], 2);
      expect(data['dateTaken'], isA<Timestamp>());
    });
  });

  group('pushClay', () {
    test('writes clay data to Firestore', () async {
      await insertClay(id: 'c1', name: 'Porcelain', sortOrder: 3);

      await syncService.pushClay(_uid, 'c1');

      final doc = await col('clays').doc('c1').get();
      final data = doc.data() as Map<String, dynamic>;
      expect(data['name'], 'Porcelain');
      expect(data['sortOrder'], 3);
    });

    test('no-ops when clay does not exist locally', () async {
      await syncService.pushClay(_uid, 'nonexistent');
      final doc = await col('clays').doc('nonexistent').get();
      expect(doc.exists, false);
    });
  });

  group('pushGlaze', () {
    test('writes glaze data to Firestore', () async {
      await insertGlaze(id: 'g1', name: 'Celadon');

      await syncService.pushGlaze(_uid, 'g1');

      final doc = await col('glazes').doc('g1').get();
      final data = doc.data() as Map<String, dynamic>;
      expect(data['name'], 'Celadon');
    });
  });

  group('pushTag', () {
    test('writes tag data to Firestore including color', () async {
      await insertTag(id: 't1', name: 'Gift', color: '#FF0000');

      await syncService.pushTag(_uid, 't1');

      final doc = await col('tags').doc('t1').get();
      final data = doc.data() as Map<String, dynamic>;
      expect(data['name'], 'Gift');
      expect(data['color'], '#FF0000');
    });
  });

  group('pushPieceGlazes', () {
    test('replaces remote junction rows with current local glazes', () async {
      await insertPiece(id: 'p1');
      await insertGlaze(id: 'g1', name: 'Celadon');
      await insertGlaze(id: 'g2', name: 'Tenmoku');
      await db.materialsDao.setGlazesForPiece('p1', ['g1', 'g2']);

      // Seed an old remote row that should be deleted
      await col('pieceGlazes').doc('old-row').set({
        'pieceId': 'p1',
        'glazeOptionId': 'g-old',
        'sortOrder': 0,
      });

      await syncService.pushPieceGlazes(_uid, 'p1');

      final snap = await col(
        'pieceGlazes',
      ).where('pieceId', isEqualTo: 'p1').get();
      expect(snap.docs.length, 2);

      final glazeIds = snap.docs
          .map((d) => (d.data() as Map)['glazeOptionId'])
          .toSet();
      expect(glazeIds, {'g1', 'g2'});

      // Old row should be gone
      final oldDoc = await col('pieceGlazes').doc('old-row').get();
      expect(oldDoc.exists, false);
    });
  });

  group('pushPieceTags', () {
    test('replaces remote junction rows with current local tags', () async {
      await insertPiece(id: 'p1');
      await insertTag(id: 't1', name: 'Gift');
      await insertTag(id: 't2', name: 'Sale');
      await db.materialsDao.setTagsForPiece('p1', ['t1', 't2']);

      await syncService.pushPieceTags(_uid, 'p1');

      final snap = await col(
        'pieceTags',
      ).where('pieceId', isEqualTo: 'p1').get();
      expect(snap.docs.length, 2);

      final tagIds = snap.docs
          .map((d) => (d.data() as Map)['tagOptionId'])
          .toSet();
      expect(tagIds, {'t1', 't2'});
    });
  });

  group('pushDeletion', () {
    test('sets deletedAt and updatedAt on the remote doc', () async {
      // Create a doc first
      await col('photos').doc('ph1').set({'pieceId': 'p1'});

      await syncService.pushDeletion(_uid, 'photos', 'ph1');

      final doc = await col('photos').doc('ph1').get();
      final data = doc.data() as Map<String, dynamic>;
      expect(data['deletedAt'], isNotNull);
      expect(data['updatedAt'], isNotNull);
      // Original data preserved (merge: true)
      expect(data['pieceId'], 'p1');
    });
  });

  group('pushPieceDeletion', () {
    test('marks piece and its photos as deleted, removes junctions', () async {
      // Set up remote data
      await col(
        'pieces',
      ).doc('p1').set({'title': 'Bowl', 'updatedAt': Timestamp.now()});
      await col(
        'photos',
      ).doc('ph1').set({'pieceId': 'p1', 'updatedAt': Timestamp.now()});
      await col(
        'photos',
      ).doc('ph2').set({'pieceId': 'p1', 'updatedAt': Timestamp.now()});
      await col(
        'pieceGlazes',
      ).doc('pg1').set({'pieceId': 'p1', 'glazeOptionId': 'g1'});
      await col(
        'pieceTags',
      ).doc('pt1').set({'pieceId': 'p1', 'tagOptionId': 't1'});

      await syncService.pushPieceDeletion(_uid, 'p1');

      // Piece should have deletedAt
      final pieceDoc = await col('pieces').doc('p1').get();
      expect((pieceDoc.data() as Map)['deletedAt'], isNotNull);

      // Photos should have deletedAt
      final photo1 = await col('photos').doc('ph1').get();
      expect((photo1.data() as Map)['deletedAt'], isNotNull);

      // Junction rows should be deleted entirely
      final glazeSnap = await col(
        'pieceGlazes',
      ).where('pieceId', isEqualTo: 'p1').get();
      expect(glazeSnap.docs, isEmpty);

      final tagSnap = await col(
        'pieceTags',
      ).where('pieceId', isEqualTo: 'p1').get();
      expect(tagSnap.docs, isEmpty);
    });
  });

  // ── Pull tests ─────────────────────────────────

  group('pullAll', () {
    test('inserts remote pieces into local DB', () async {
      final now = DateTime(2025, 6, 1);
      await col('pieces').doc('p1').set({
        'title': 'Remote Bowl',
        'stage': 'glazed',
        'clayType': 'Stoneware',
        'notes': null,
        'coverPhotoId': null,
        'isArchived': false,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });

      await syncService.pullAll(_uid);

      final piece = await db.piecesDao.getPieceById('p1');
      expect(piece, isNotNull);
      expect(piece!.title, 'Remote Bowl');
      expect(piece.stage, 'glazed');
      expect(piece.clayType, 'Stoneware');
    });

    test('inserts remote clays, glazes, and tags into local DB', () async {
      final now = Timestamp.fromDate(DateTime(2025, 1, 1));
      await col('clays').doc('c1').set({
        'name': 'Porcelain',
        'sortOrder': 0,
        'createdAt': now,
        'updatedAt': now,
      });
      await col('glazes').doc('g1').set({
        'name': 'Celadon',
        'sortOrder': 1,
        'createdAt': now,
        'updatedAt': now,
      });
      await col('tags').doc('t1').set({
        'name': 'Gift',
        'color': '#FF0000',
        'sortOrder': 2,
        'createdAt': now,
        'updatedAt': now,
      });

      await syncService.pullAll(_uid);

      final clays = await db.materialsDao.getAllClays();
      expect(clays.length, 1);
      expect(clays.first.name, 'Porcelain');

      final glazes = await db.materialsDao.getAllGlazes();
      expect(glazes.length, 1);
      expect(glazes.first.name, 'Celadon');

      final tags = await db.materialsDao.getAllTags();
      expect(tags.length, 1);
      expect(tags.first.name, 'Gift');
      expect(tags.first.color, '#FF0000');
    });

    test('updates existing piece when remote is newer', () async {
      // Insert local piece with old timestamp
      final oldTime = DateTime(2025, 1, 1);
      await db.piecesDao.insertPiece(
        PiecesCompanion(
          id: const Value('p1'),
          title: const Value('Old Title'),
          createdAt: Value(oldTime),
          updatedAt: Value(oldTime),
        ),
      );

      // Remote has newer timestamp
      final newTime = DateTime(2025, 6, 1);
      await col('pieces').doc('p1').set({
        'title': 'Updated Title',
        'stage': null,
        'clayType': null,
        'notes': null,
        'coverPhotoId': null,
        'isArchived': false,
        'createdAt': Timestamp.fromDate(oldTime),
        'updatedAt': Timestamp.fromDate(newTime),
      });

      await syncService.pullAll(_uid);

      final piece = await db.piecesDao.getPieceById('p1');
      expect(piece!.title, 'Updated Title');
    });

    test('skips update when local piece is newer', () async {
      final newTime = DateTime(2025, 6, 1);
      await db.piecesDao.insertPiece(
        PiecesCompanion(
          id: const Value('p1'),
          title: const Value('Local Title'),
          createdAt: Value(newTime),
          updatedAt: Value(newTime),
        ),
      );

      // Remote has older timestamp
      final oldTime = DateTime(2025, 1, 1);
      await col('pieces').doc('p1').set({
        'title': 'Old Remote Title',
        'stage': null,
        'clayType': null,
        'notes': null,
        'coverPhotoId': null,
        'isArchived': false,
        'createdAt': Timestamp.fromDate(oldTime),
        'updatedAt': Timestamp.fromDate(oldTime),
      });

      await syncService.pullAll(_uid);

      final piece = await db.piecesDao.getPieceById('p1');
      expect(piece!.title, 'Local Title');
    });

    test('handles remotely deleted docs by removing from local DB', () async {
      // Insert local piece
      await insertPiece(id: 'p1', title: 'To Delete');

      // Remote has deletedAt set
      await col('pieces').doc('p1').set({
        'title': 'To Delete',
        'deletedAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
        'createdAt': Timestamp.now(),
      });

      await syncService.pullAll(_uid);

      final piece = await db.piecesDao.getPieceById('p1');
      expect(piece, isNull);
    });

    test('merges remote piece glazes into local junction table', () async {
      // Set up local piece and glazes
      await insertPiece(id: 'p1');
      await insertGlaze(id: 'g1', name: 'Celadon');
      await insertGlaze(id: 'g2', name: 'Tenmoku');

      // Remote junction rows
      await col(
        'pieceGlazes',
      ).doc('j1').set({'pieceId': 'p1', 'glazeOptionId': 'g2', 'sortOrder': 0});
      await col(
        'pieceGlazes',
      ).doc('j2').set({'pieceId': 'p1', 'glazeOptionId': 'g1', 'sortOrder': 1});

      await syncService.pullAll(_uid);

      final glazes = await db.materialsDao.getGlazesForPiece('p1');
      // Should be sorted by sortOrder: g2 first, then g1
      expect(glazes.map((g) => g.id).toList(), ['g2', 'g1']);
    });

    test('saves lastPulledAt after successful pull', () async {
      await syncService.pullAll(_uid);

      final lastPulled = await syncService.getLastPulledAt(_uid);
      expect(lastPulled, isNotNull);
      expect(
        lastPulled!.difference(DateTime.now()).inSeconds.abs(),
        lessThan(5),
      );
    });
  });

  group('pullChangedSince', () {
    test('only pulls docs with updatedAt after the given timestamp', () async {
      final cutoff = DateTime(2025, 3, 1);
      final before = DateTime(2025, 2, 1);
      final after = DateTime(2025, 4, 1);

      // Old doc (should NOT be pulled)
      await col('pieces').doc('old').set({
        'title': 'Old',
        'stage': null,
        'clayType': null,
        'notes': null,
        'coverPhotoId': null,
        'isArchived': false,
        'createdAt': Timestamp.fromDate(before),
        'updatedAt': Timestamp.fromDate(before),
      });

      // New doc (should be pulled)
      await col('pieces').doc('new').set({
        'title': 'New',
        'stage': null,
        'clayType': null,
        'notes': null,
        'coverPhotoId': null,
        'isArchived': false,
        'createdAt': Timestamp.fromDate(after),
        'updatedAt': Timestamp.fromDate(after),
      });

      await syncService.pullChangedSince(_uid, cutoff);

      expect(await db.piecesDao.getPieceById('old'), isNull);
      expect(await db.piecesDao.getPieceById('new'), isNotNull);
      expect((await db.piecesDao.getPieceById('new'))!.title, 'New');
    });

    test('handles remote deletions in incremental pull', () async {
      await insertPiece(id: 'p1');

      final after = DateTime(2025, 4, 1);
      await col('pieces').doc('p1').set({
        'deletedAt': Timestamp.fromDate(after),
        'updatedAt': Timestamp.fromDate(after),
      });

      await syncService.pullChangedSince(_uid, DateTime(2025, 3, 1));

      expect(await db.piecesDao.getPieceById('p1'), isNull);
    });
  });

  // ── getLastPulledAt ────────────────────────────

  group('getLastPulledAt', () {
    test('returns null when no timestamp stored', () async {
      final result = await syncService.getLastPulledAt(_uid);
      expect(result, isNull);
    });

    test('returns stored timestamp after pullAll', () async {
      await syncService.pullAll(_uid);

      final result = await syncService.getLastPulledAt(_uid);
      expect(result, isNotNull);
    });

    test('is per-user', () async {
      await syncService.pullAll(_uid);

      final other = await syncService.getLastPulledAt('other-user');
      expect(other, isNull);
    });
  });

  // ── pushAllLocal ───────────────────────────────

  group('pushAllLocal', () {
    test(
      'pushes all local pieces, materials, and junctions to Firestore',
      () async {
        await insertPiece(id: 'p1', title: 'Bowl');
        await insertPiece(id: 'p2', title: 'Mug');
        await insertClay(id: 'c1', name: 'Stoneware');
        await insertGlaze(id: 'g1', name: 'Celadon');
        await insertTag(id: 't1', name: 'Gift');

        await db.materialsDao.setGlazesForPiece('p1', ['g1']);
        await db.materialsDao.setTagsForPiece('p2', ['t1']);

        await syncService.pushAllLocal(_uid);

        // Check pieces in Firestore
        final piecesSnap = await col('pieces').get();
        expect(piecesSnap.docs.length, 2);

        // Check materials
        final claysSnap = await col('clays').get();
        expect(claysSnap.docs.length, 1);
        expect((claysSnap.docs.first.data() as Map)['name'], 'Stoneware');

        final glazesSnap = await col('glazes').get();
        expect(glazesSnap.docs.length, 1);

        final tagsSnap = await col('tags').get();
        expect(tagsSnap.docs.length, 1);

        // Check junctions
        final pieceGlazesSnap = await col(
          'pieceGlazes',
        ).where('pieceId', isEqualTo: 'p1').get();
        expect(pieceGlazesSnap.docs.length, 1);

        final pieceTagsSnap = await col(
          'pieceTags',
        ).where('pieceId', isEqualTo: 'p2').get();
        expect(pieceTagsSnap.docs.length, 1);
      },
    );
  });

  // ── deleteAllData ──────────────────────────────

  group('deleteAllData', () {
    test('removes all Firestore docs and local DB rows', () async {
      // Seed local data
      await insertPiece(id: 'p1');
      await insertPhoto(id: 'ph1', pieceId: 'p1');
      await insertClay(id: 'c1', name: 'Stoneware');

      // Seed remote data
      await col('pieces').doc('p1').set({'title': 'Bowl'});
      await col('photos').doc('ph1').set({'pieceId': 'p1'});
      await col('clays').doc('c1').set({'name': 'Stoneware'});

      await syncService.deleteAllData(_uid);

      // Firestore should be empty
      expect((await col('pieces').get()).docs, isEmpty);
      expect((await col('photos').get()).docs, isEmpty);
      expect((await col('clays').get()).docs, isEmpty);

      // Local DB should be empty
      final pieces = await db.select(db.pieces).get();
      expect(pieces, isEmpty);
      final photos = await db.select(db.photos).get();
      expect(photos, isEmpty);
      final clays = await db.materialsDao.getAllClays();
      expect(clays, isEmpty);
    });
  });
}
