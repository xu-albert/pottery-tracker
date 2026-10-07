import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart'
    show ListResult, Reference;
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/database/transfer_key_backup.dart';
import 'package:pottery_tracker/services/sync_queue.dart';
import 'package:pottery_tracker/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_secure_storage.dart';

const _uid = 'test-user';
const _keyName = 'db_encryption_key';
const _markerName = 'db_encryption_key_storage_version';
const _oldKey = 'oldDeviceKey0123456789abcdefghij';

void main() {
  late AppDatabase db;
  late FakeFirebaseFirestore firestore;
  late MockFirebaseStorage storage;
  late SyncService syncService;
  late Directory docsDir;
  late Directory cacheDir;

  setUp(() {
    // `deleteLocalData` deletes the photo files as well as the rows, and now
    // reports a failure there instead of swallowing it — so these need real
    // directories to delete rather than a plugin that is not there.
    TestWidgetsFlutterBinding.ensureInitialized();
    docsDir = Directory.systemTemp.createTempSync('sync_service_docs_');
    cacheDir = Directory.systemTemp.createTempSync('sync_service_cache_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => switch (call.method) {
            'getApplicationDocumentsDirectory' => docsDir.path,
            'getTemporaryDirectory' => cacheDir.path,
            _ => null,
          },
        );
    db = AppDatabase.forTesting(NativeDatabase.memory());
    firestore = FakeFirebaseFirestore();
    storage = MockFirebaseStorage();
    syncService = SyncService(db, firestore, storage);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance = FakeSecureStoragePlatform();
  });

  tearDown(() async {
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    for (final dir in [docsDir, cacheDir]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  // ── Helpers ────────────────────────────────────

  Future<Piece> insertPiece({
    required String id,
    String? title,
    String? stage,
    String? clayType,
    String? notes,
    DateTime? displayDate,
  }) async {
    final now = DateTime.now();
    await db.piecesDao.insertPiece(
      PiecesCompanion(
        id: Value(id),
        title: Value(title),
        stage: Value(stage),
        clayType: Value(clayType),
        notes: Value(notes),
        displayDate: Value(displayDate),
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

    test('pushes displayDate when set', () async {
      final displayDate = DateTime(2025, 3, 15, 10, 30);
      await insertPiece(id: 'p2', title: 'Vase', displayDate: displayDate);

      await syncService.pushPiece(_uid, 'p2');

      final doc = await col('pieces').doc('p2').get();
      final data = doc.data() as Map<String, dynamic>;
      expect(data['displayDate'], isA<Timestamp>());
      expect((data['displayDate'] as Timestamp).toDate(), displayDate);
    });

    test('pushes null displayDate when not set', () async {
      await insertPiece(id: 'p3', title: 'Cup');

      await syncService.pushPiece(_uid, 'p3');

      final doc = await col('pieces').doc('p3').get();
      final data = doc.data() as Map<String, dynamic>;
      expect(data['displayDate'], isNull);
    });

    test('no-ops when piece does not exist locally', () async {
      await syncService.pushPiece(_uid, 'nonexistent');
      final doc = await col('pieces').doc('nonexistent').get();
      expect(doc.exists, false);
    });

    test('a field-scoped push writes only those fields', () async {
      await insertPiece(id: 'p1', title: 'Stale title', clayType: 'B-Mix');
      await col('pieces').doc('p1').set({
        'title': 'Edited elsewhere',
        'clayType': 'Stoneware',
        'isArchived': false,
        'createdAt': Timestamp.fromDate(DateTime(2025)),
        'updatedAt': Timestamp.fromDate(DateTime(2025)),
      });

      await syncService.pushPiece(_uid, 'p1', fields: ['clayType']);

      final data =
          (await col('pieces').doc('p1').get()).data() as Map<String, dynamic>;
      expect(data['title'], 'Edited elsewhere');
      expect(data['clayType'], 'B-Mix');
      expect(
        (data['updatedAt'] as Timestamp).toDate().isAfter(DateTime(2025)),
        isTrue,
        reason: 'the pushed field must reach devices that already pulled it',
      );
    });

    test('a field-scoped push of a piece the cloud does not hold yet uploads '
        'it whole', () async {
      await insertPiece(id: 'p1', title: 'Made offline', clayType: 'B-Mix');

      await syncService.pushPiece(_uid, 'p1', fields: ['clayType']);

      final data =
          (await col('pieces').doc('p1').get()).data() as Map<String, dynamic>;
      expect(data['title'], 'Made offline');
      expect(data['clayType'], 'B-Mix');
      expect(data['createdAt'], isA<Timestamp>());
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

  group('uploadPhotoFile', () {
    test(
      'uploads at the photo path storage.rules admits, as image/jpeg',
      () async {
        final file = File('${docsDir.path}/ph1.jpg')..writeAsBytesSync([1, 2]);
        final now = DateTime(2025);
        await db.photosDao.insertPhoto(
          PhotosCompanion(
            id: const Value('ph1'),
            pieceId: const Value('p1'),
            localPath: Value(file.path),
            dateTaken: Value(now),
            createdAt: Value(now),
          ),
        );
        await col('photos').doc('ph1').set({'pieceId': 'p1'});

        await syncService.uploadPhotoFile(_uid, 'ph1');

        const path = 'users/$_uid/photos/p1/ph1.jpg';
        expect(storage.storedFilesMap.keys, [path]);
        expect(SyncService.photoStoragePath(_uid, 'p1', 'ph1'), path);
        expect(
          storage.storedSettableMetadataMap[path]!['contentType'],
          'image/jpeg',
        );
        final data = (await col('photos').doc('ph1').get()).data() as Map;
        expect(data['cloudUrl'], isNotNull);
      },
    );
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
      final firstIds = snap.docs.map((doc) => doc.id).toSet();

      final glazeIds = snap.docs
          .map((d) => (d.data() as Map)['glazeOptionId'])
          .toSet();
      expect(glazeIds, {'g1', 'g2'});

      // Old row should be gone
      final oldDoc = await col('pieceGlazes').doc('old-row').get();
      expect(oldDoc.exists, false);

      await syncService.pushPieceGlazes(_uid, 'p1');
      final repeated = await col(
        'pieceGlazes',
      ).where('pieceId', isEqualTo: 'p1').get();
      expect(repeated.docs.map((doc) => doc.id).toSet(), firstIds);
      expect(repeated.docs.length, 2);
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
      final firstIds = snap.docs.map((doc) => doc.id).toSet();

      final tagIds = snap.docs
          .map((d) => (d.data() as Map)['tagOptionId'])
          .toSet();
      expect(tagIds, {'t1', 't2'});

      await syncService.pushPieceTags(_uid, 'p1');
      final repeated = await col(
        'pieceTags',
      ).where('pieceId', isEqualTo: 'p1').get();
      expect(repeated.docs.map((doc) => doc.id).toSet(), firstIds);
      expect(repeated.docs.length, 2);
    });
  });

  group('fullUploadEntries', () {
    test(
      'describes the full snapshot as ordinary durable operations',
      () async {
        await insertPiece(id: 'p1', title: 'Bowl');
        await insertPhoto(
          id: 'ph1',
          pieceId: 'p1',
          cloudUrl: 'https://example.test/photo.jpg',
        );
        await insertClay(id: 'c1', name: 'Stoneware');
        await insertGlaze(id: 'g1', name: 'Celadon');
        await insertTag(id: 't1', name: 'Gift');
        await db.materialsDao.setGlazesForPiece('p1', ['g1']);
        await db.materialsDao.setTagsForPiece('p1', ['t1']);

        final entries = await syncService.fullUploadEntries(_uid);

        expect(
          entries,
          containsAll(<SyncQueueEntry>[
            const SyncQueueEntry(
              operation: SyncOperation.pushPiece,
              entityId: 'p1',
            ),
            const SyncQueueEntry(
              operation: SyncOperation.pushPhoto,
              entityId: 'ph1',
            ),
            const SyncQueueEntry(
              operation: SyncOperation.pushClay,
              entityId: 'c1',
            ),
            const SyncQueueEntry(
              operation: SyncOperation.pushGlaze,
              entityId: 'g1',
            ),
            const SyncQueueEntry(
              operation: SyncOperation.pushTag,
              entityId: 't1',
            ),
            const SyncQueueEntry(
              operation: SyncOperation.pushPieceGlazes,
              entityId: 'p1',
            ),
            const SyncQueueEntry(
              operation: SyncOperation.pushPieceTags,
              entityId: 'p1',
            ),
          ]),
        );
        expect(
          entries.where(
            (entry) => entry.operation == SyncOperation.pushPhotoFile,
          ),
          isEmpty,
        );
      },
    );
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

  group('cloud photo deletion reaches Cloud Storage', () {
    const object = 'users/$_uid/photos/p1/ph1.jpg';
    late _ScriptedStorage scripted;
    late SyncService service;

    setUp(() {
      scripted = _ScriptedStorage();
      scripted.storedDataMap[object] = Uint8List.fromList([1]);
      service = SyncService(db, firestore, scripted);
    });

    test('a single photo deletion deletes its object and tombstones its '
        'metadata', () async {
      await col('photos').doc('ph1').set({'pieceId': 'p1'});

      await service.pushPhotoDeletion(_uid, 'ph1', pieceId: 'p1');

      expect(scripted.storedDataMap, isNot(contains(object)));
      final data = (await col('photos').doc('ph1').get()).data() as Map;
      expect(data['deletedAt'], isNotNull);
    });

    test('an entry queued before deletions named the piece finds the object '
        'through the metadata', () async {
      await col('photos').doc('ph1').set({'pieceId': 'p1'});

      await service.pushPhotoDeletion(_uid, 'ph1');

      expect(scripted.storedDataMap, isNot(contains(object)));
    });

    test('an object that is already gone counts as deleted, so a retry '
        'converges', () async {
      scripted.deleteFailures[object] = FirebaseException(
        plugin: 'firebase_storage',
        code: 'object-not-found',
      );

      await service.pushPhotoDeletion(_uid, 'ph1', pieceId: 'p1');

      final data = (await col('photos').doc('ph1').get()).data() as Map;
      expect(data['deletedAt'], isNotNull);
    });

    test(
      'any other Storage failure propagates, keeping the entry queued',
      () async {
        scripted.deleteFailures[object] = FirebaseException(
          plugin: 'firebase_storage',
          code: 'unavailable',
        );

        await expectLater(
          service.pushPhotoDeletion(_uid, 'ph1', pieceId: 'p1'),
          throwsA(
            isA<FirebaseException>().having(
              (e) => e.code,
              'code',
              'unavailable',
            ),
          ),
        );
        expect(scripted.storedDataMap, contains(object));
      },
    );

    test('a piece deletion no longer swallows a Storage failure', () async {
      await col('pieces').doc('p1').set({'title': 'Bowl'});
      await col('photos').doc('ph1').set({'pieceId': 'p1'});
      scripted.deleteFailures[object] = FirebaseException(
        plugin: 'firebase_storage',
        code: 'unavailable',
      );

      await expectLater(
        service.pushPieceDeletion(_uid, 'p1'),
        throwsA(isA<FirebaseException>()),
      );
    });

    test('a piece deletion deletes each photo object', () async {
      await col('pieces').doc('p1').set({'title': 'Bowl'});
      await col('photos').doc('ph1').set({'pieceId': 'p1'});

      await service.pushPieceDeletion(_uid, 'p1');

      expect(scripted.storedDataMap, isNot(contains(object)));
    });

    test('account deletion removes every object at any depth', () async {
      scripted.storedDataMap['users/$_uid/stray.bin'] = Uint8List(1);
      scripted.storedDataMap['users/$_uid/a/b/c/d.jpg'] = Uint8List(1);
      scripted.storedDataMap['users/other/photos/p/x.jpg'] = Uint8List(1);

      await service.deleteCloudData(_uid);

      expect(scripted.storedDataMap.keys, ['users/other/photos/p/x.jpg']);
    });

    test('account deletion fails when Storage cleanup fails, rather than '
        'reporting the photos deleted', () async {
      scripted.listFailure = FirebaseException(
        plugin: 'firebase_storage',
        code: 'unavailable',
      );

      await expectLater(
        service.deleteCloudData(_uid),
        throwsA(isA<FirebaseException>()),
      );
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

    test('pulls displayDate from remote piece', () async {
      final displayDate = DateTime(2025, 5, 20, 14, 0);
      final now = DateTime(2025, 6, 1);
      await col('pieces').doc('p-dd').set({
        'title': 'Bowl with date',
        'stage': null,
        'clayType': null,
        'notes': null,
        'coverPhotoId': null,
        'isArchived': false,
        'displayDate': Timestamp.fromDate(displayDate),
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });

      await syncService.pullAll(_uid);

      final piece = await db.piecesDao.getPieceById('p-dd');
      expect(piece, isNotNull);
      expect(piece!.displayDate, displayDate);
    });

    test('pulls piece with null displayDate', () async {
      final now = DateTime(2025, 6, 1);
      await col('pieces').doc('p-nd').set({
        'title': 'No display date',
        'stage': null,
        'clayType': null,
        'notes': null,
        'coverPhotoId': null,
        'isArchived': false,
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });

      await syncService.pullAll(_uid);

      final piece = await db.piecesDao.getPieceById('p-nd');
      expect(piece, isNotNull);
      expect(piece!.displayDate, isNull);
    });

    test('updates displayDate when remote is newer', () async {
      final oldTime = DateTime(2025, 1, 1);
      await db.piecesDao.insertPiece(
        PiecesCompanion(
          id: const Value('p-upd'),
          title: const Value('Old'),
          createdAt: Value(oldTime),
          updatedAt: Value(oldTime),
        ),
      );

      final newTime = DateTime(2025, 6, 1);
      final displayDate = DateTime(2025, 4, 10);
      await col('pieces').doc('p-upd').set({
        'title': 'Updated',
        'stage': null,
        'clayType': null,
        'notes': null,
        'coverPhotoId': null,
        'isArchived': false,
        'displayDate': Timestamp.fromDate(displayDate),
        'createdAt': Timestamp.fromDate(oldTime),
        'updatedAt': Timestamp.fromDate(newTime),
      });

      await syncService.pullAll(_uid);

      final piece = await db.piecesDao.getPieceById('p-upd');
      expect(piece!.displayDate, displayDate);
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

    test('replaces a piece with nothing queued even when its local stamp is '
        'later than the cloud copy\'s', () async {
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
      expect(piece!.title, 'Old Remote Title');
    });

    test('downloads no photos; the incremental pull after it does', () async {
      final downloads = _DownloadCountingStorage();
      final service = SyncService(db, firestore, downloads);
      await insertPiece(id: 'p1');
      await col('photos').doc('ph1').set({
        'pieceId': 'p1',
        'cloudUrl': 'https://example.test/ph1.jpg',
        'dateTaken': Timestamp.fromDate(DateTime(2025)),
        'createdAt': Timestamp.fromDate(DateTime(2025)),
        'sortOrder': 0,
        'updatedAt': Timestamp.fromDate(DateTime(2025)),
      });

      await service.pullAll(_uid);
      expect(await db.photosDao.getPhotoById('ph1'), isNotNull);
      expect(
        downloads.lookups,
        isEmpty,
        reason: 'the snapshot staged after a full pull must not wait on these',
      );

      await service.pullChangedSince(_uid);
      expect(downloads.lookups, ['https://example.test/ph1.jpg']);
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

    test('a full pull leaves lastPulledAt unset; the incremental pull after '
        'it saves it', () async {
      await syncService.pullAll(_uid);
      expect(
        await syncService.getLastPulledAt(_uid),
        isNull,
        reason: 'the snapshot a full pull trims is not queued yet',
      );

      await syncService.pullChangedSince(_uid);

      final lastPulled = await syncService.getLastPulledAt(_uid);
      expect(lastPulled, isNotNull);
      expect(
        lastPulled!.difference(DateTime.now()).inSeconds.abs(),
        lessThan(5),
      );
    });
  });

  group('pullChangedSince', () {
    Future<void> remotePiece(String id, DateTime updatedAt) =>
        col('pieces').doc(id).set({
          'title': id,
          'isArchived': false,
          'createdAt': Timestamp.fromDate(updatedAt),
          'updatedAt': Timestamp.fromDate(updatedAt),
        });

    test(
      'only pulls docs with updatedAt after the collection\'s watermark',
      () async {
        await remotePiece('seen', DateTime(2025, 3, 1));
        await syncService.pullAll(_uid);

        // Stamped behind the watermark the pull saved, and ahead of it.
        await remotePiece('old', DateTime(2025, 2, 1));
        await remotePiece('new', DateTime(2025, 4, 1));
        await syncService.pullChangedSince(_uid);

        expect(await db.piecesDao.getPieceById('old'), isNull);
        expect((await db.piecesDao.getPieceById('new'))!.title, 'new');
      },
    );

    test('handles remote deletions in incremental pull', () async {
      await insertPiece(id: 'p1');

      final after = DateTime(2025, 4, 1);
      await col('pieces').doc('p1').set({
        'deletedAt': Timestamp.fromDate(after),
        'updatedAt': Timestamp.fromDate(after),
      });

      await syncService.pullChangedSince(_uid);

      expect(await db.piecesDao.getPieceById('p1'), isNull);
    });
  });

  // ── getLastPulledAt ────────────────────────────

  group('deleteLocalData rotates the database key', () {
    late FakeSecureStoragePlatform platform;
    late _RekeyLog rekeys;
    late AppDatabase keyed;
    late SyncService service;

    setUp(() async {
      platform = FakeSecureStoragePlatform();
      FlutterSecureStoragePlatform.instance = platform;
      platform.values[_keyName] = _oldKey;
      platform.values[_markerName] = '2';
      rekeys = _RekeyLog();
      keyed = AppDatabase.forTesting(
        NativeDatabase.memory().interceptWith(rekeys),
      );
      service = SyncService(keyed, firestore, storage);
      await keyed.piecesDao.insertPiece(
        PiecesCompanion.insert(
          id: 'p1',
          title: const Value('Bowl'),
          stage: const Value('greenware'),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    });

    tearDown(() => keyed.close());

    test(
      'rekeys the open database to a fresh key and stores that key',
      () async {
        await service.deleteLocalData();

        final stored = platform.values[_keyName];
        expect(stored, isNot(_oldKey));
        expect(stored, matches(RegExp(r'^[A-Za-z0-9]{32}$')));
        expect(platform.values[_markerName], '2');
        expect(rekeys.keys, [stored]);
        expect(await keyed.piecesDao.countPieces(), 0);
      },
    );

    test('a key-back that works still leaves the old key on the file, and '
        'says so rather than passing for a rotation', () async {
      platform.rejectWrite = (key, value) =>
          key == _keyName && value != _oldKey;

      await expectLater(
        service.deleteLocalData(),
        throwsA(isA<LocalDeviceNotSecuredException>()),
        reason:
            'the designed fallback leaves exactly the state a refused rekey '
            "does, so the leaving user's passphrase still opens whatever the "
            'next person makes here',
      );

      expect(platform.values[_keyName], _oldKey);
      expect(rekeys.keys, hasLength(2));
      expect(rekeys.keys.first, isNot(_oldKey));
      expect(rekeys.keys.last, _oldKey);
      expect(await keyed.piecesDao.countPieces(), 0);
    });

    test(
      'when no key can be stored at all, the file is keyed back and the '
      'erase is reported as failed rather than left with the keys disagreeing',
      () async {
        platform.writeFailure = PlatformException(code: 'full');
        final photosDir = Directory('${docsDir.path}/photos')
          ..createSync(recursive: true);
        File('${photosDir.path}/piece-a.jpg').writeAsBytesSync([1, 2, 3]);
        final transferBackup = TransferKeyBackup.fileFor(docsDir)
          ..writeAsBytesSync([4, 5, 6]);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(SyncService.localDataOwnerKey, _uid);
        await prefs.setInt('${SyncService.lastPulledAtPrefix}$_uid', 1);

        await expectLater(
          service.deleteLocalData(),
          throwsA(isA<LocalDeviceNotSecuredException>()),
          reason:
              'its own type, so no caller can report a complete wipe as '
              '"nothing was deleted"',
        );

        expect(platform.values[_keyName], _oldKey);
        expect(rekeys.keys.last, _oldKey);

        // The report comes last. A key store that cannot be written must not
        // strand the photographs the confirmation promised to delete, nor the
        // ownership stamp that decides whether the next account is refused —
        // the retry would hit the same broken key store and skip them again.
        expect(photosDir.existsSync(), isFalse);
        expect(transferBackup.existsSync(), isFalse);
        expect(await service.getLastPulledAt(_uid), isNull);
        expect(prefs.getString(SyncService.localDataOwnerKey), isNull);
      },
    );

    test(
      'a rekey the database refuses is reported, not passed off as rotated',
      () async {
        rekeys.failure = Exception('the database refused the rekey');

        await expectLater(
          service.deleteLocalData(),
          throwsA(isA<LocalDeviceNotSecuredException>()),
          reason:
              'the file is still on the old key and the store still holds '
              'it — the state a failed key-back leaves, and the same report',
        );

        expect(platform.values[_keyName], _oldKey);
        expect(await keyed.piecesDao.countPieces(), 0);
      },
    );

    test(
      'a rotation and a transfer delete that both fail report both causes',
      () async {
        rekeys.failure = Exception('the database refused the rekey');
        TransferKeyBackup.fileFor(docsDir).writeAsBytesSync([1, 2, 3]);
        Process.runSync('chmod', ['500', docsDir.path]);
        addTearDown(() => Process.runSync('chmod', ['700', docsDir.path]));
        var deletionIsBlocked = false;
        try {
          TransferKeyBackup.fileFor(docsDir).deleteSync();
        } catch (_) {
          deletionIsBlocked = true;
        }
        if (!deletionIsBlocked) {
          markTestSkipped('the filesystem here does not enforce the mode bits');
          return;
        }

        Object? thrown;
        try {
          await service.deleteLocalData();
        } catch (e) {
          thrown = e;
        }

        expect(thrown, isA<LocalDeviceNotSecuredException>());
        final notSecured = thrown! as LocalDeviceNotSecuredException;
        expect(
          notSecured.causes,
          hasLength(2),
          reason:
              'reporting one of the two would drop the other from the error '
              'the caller records',
        );
        expect(
          notSecured.toString(),
          contains('the database refused the rekey'),
        );
      },
    );

    test('with no stored key there is nothing to rotate', () async {
      platform.values.clear();

      await service.deleteLocalData();

      expect(rekeys.keys, isEmpty);
      expect(platform.values, isEmpty);
    });
  });

  group('getLastPulledAt', () {
    test('returns null when no timestamp stored', () async {
      final result = await syncService.getLastPulledAt(_uid);
      expect(result, isNull);
    });

    test('returns stored timestamp after an incremental pull', () async {
      await syncService.pullChangedSince(_uid);

      final result = await syncService.getLastPulledAt(_uid);
      expect(result, isNotNull);
    });

    test('is per-user', () async {
      await syncService.pullChangedSince(_uid);

      final other = await syncService.getLastPulledAt('other-user');
      expect(other, isNull);
    });
  });

  // ── deleteLocalData ────────────────────────────

  group('deleteLocalData', () {
    test('leaves no junction tombstones behind', () async {
      await insertPiece(id: 'p1');
      await insertGlaze(id: 'g1', name: 'Celadon');
      await db.materialsDao.setGlazesForPiece('p1', ['g1']);
      // Removing the glaze writes a tombstone row that the sync pushes later.
      await db.materialsDao.setGlazesForPiece('p1', []);
      expect(await db.select(db.deletedJunctions).get(), isNotEmpty);

      await syncService.deleteLocalData();

      expect(await db.select(db.deletedJunctions).get(), isEmpty);
      expect(await db.select(db.pieceGlazes).get(), isEmpty);
    });

    test('clears every pull watermark, not just the current uid', () async {
      await syncService.pullChangedSince(_uid);
      await syncService.pullChangedSince('other-user');
      expect(await syncService.getLastPulledAt(_uid), isNotNull);

      await syncService.deleteLocalData();

      // A surviving watermark would send the returning account down the
      // incremental branch, which never re-downloads what was deleted here.
      expect(await syncService.getLastPulledAt(_uid), isNull);
      expect(await syncService.getLastPulledAt('other-user'), isNull);
    });
  });

  group('deleteLocalData reports a transfer backup it could not delete', () {
    test(
      'even with the file rekeyed, because that copy is what Settings '
      'reads to claim a passphrase is set — and the stamp still goes',
      () async {
        final platform = FakeSecureStoragePlatform();
        FlutterSecureStoragePlatform.instance = platform;
        platform.values[_keyName] = _oldKey;
        platform.values[_markerName] = '2';
        await insertPiece(id: 'piece-a', title: 'Mug');
        TransferKeyBackup.fileFor(docsDir).writeAsBytesSync([1, 2, 3]);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(SyncService.localDataOwnerKey, _uid);

        // Take away the parent's write permission so the backup cannot be
        // unlinked. Root ignores the mode bits, so check the setup bites.
        Process.runSync('chmod', ['500', docsDir.path]);
        addTearDown(() => Process.runSync('chmod', ['700', docsDir.path]));
        var deletionIsBlocked = false;
        try {
          TransferKeyBackup.fileFor(docsDir).deleteSync();
        } catch (_) {
          deletionIsBlocked = true;
        }
        if (!deletionIsBlocked) {
          markTestSkipped('the filesystem here does not enforce the mode bits');
          return;
        }

        await expectLater(
          syncService.deleteLocalData(),
          throwsA(isA<LocalDeviceNotSecuredException>()),
          reason:
              'the next person would be shown a transfer passphrase they never '
              'chose, over a file only the erase ever removes',
        );

        expect(
          platform.values[_keyName],
          isNot(_oldKey),
          reason: 'the rotation itself worked; only the file outlived it',
        );
        // Raised last, so the clears after it ran: an ownership stamp left on
        // an emptied device refuses the next account for nothing.
        expect(await db.select(db.pieces).get(), isEmpty);
        expect(prefs.getString(SyncService.localDataOwnerKey), isNull);
        expect(prefs.getBool(SyncService.deviceContestedKey), isNull);
      },
    );
  });

  group('deleteLocalData reports a photo wipe it could not finish', () {
    test(
      'an undeletable photo directory fails the wipe instead of passing',
      () async {
        final photosDir = Directory('${docsDir.path}/photos')
          ..createSync(recursive: true);
        File('${photosDir.path}/piece-a.jpg').writeAsBytesSync([1, 2, 3]);

        // Take away the parent's write permission so the directory cannot be
        // unlinked. Root ignores the mode bits, so the test verifies the setup
        // actually bites before asserting anything about it.
        Process.runSync('chmod', ['500', docsDir.path]);
        addTearDown(() => Process.runSync('chmod', ['700', docsDir.path]));
        var deletionIsBlocked = false;
        try {
          photosDir.deleteSync(recursive: true);
        } catch (_) {
          deletionIsBlocked = true;
        }
        if (!deletionIsBlocked) {
          markTestSkipped('the filesystem here does not enforce the mode bits');
          return;
        }

        await expectLater(
          syncService.deleteLocalData(),
          throwsA(isA<LocalPhotoWipeException>()),
          reason:
              'the confirmation the user answered promises every photo on this '
              'device is deleted, so an erase that left them behind must not '
              'come back as done',
        );
        expect(
          photosDir.existsSync(),
          isTrue,
          reason: 'and the photos really are still here, which is the point',
        );
      },
    );

    test(
      'the rest of the wipe still runs before the failure surfaces',
      () async {
        await insertPiece(id: 'piece-a', title: 'Mug');
        final photosDir = Directory('${docsDir.path}/photos')
          ..createSync(recursive: true);
        File('${photosDir.path}/piece-a.jpg').writeAsBytesSync([1, 2, 3]);

        Process.runSync('chmod', ['500', docsDir.path]);
        addTearDown(() => Process.runSync('chmod', ['700', docsDir.path]));
        var deletionIsBlocked = false;
        try {
          photosDir.deleteSync(recursive: true);
        } catch (_) {
          deletionIsBlocked = true;
        }
        if (!deletionIsBlocked) {
          markTestSkipped('the filesystem here does not enforce the mode bits');
          return;
        }

        await expectLater(
          syncService.deleteLocalData(),
          throwsA(isA<LocalPhotoWipeException>()),
        );

        // The wipe is best-effort; only the reporting is not. Giving up at the
        // photos would strand the rows and the ownership stamp, and the stamp is
        // what decides whether the next account is refused.
        expect(await db.select(db.pieces).get(), isEmpty);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(SyncService.localDataOwnerKey), isNull);
        expect(prefs.getBool(SyncService.deviceContestedKey), isNull);
      },
    );
  });
}

/// Records every photo download the sync starts, by the URL it resolves.
class _DownloadCountingStorage extends MockFirebaseStorage {
  final lookups = <String>[];

  @override
  Reference refFromURL(String url) {
    lookups.add(url);
    return super.refFromURL(url);
  }
}

/// Records every `PRAGMA rekey` the database receives, in order — the seam
/// where SQLCipher would re-encrypt the file; plain sqlite3 ignores it.
class _RekeyLog extends QueryInterceptor {
  final List<String> keys = [];

  /// When set, every `PRAGMA rekey` fails the way a database refusing one
  /// would — the case plain sqlite3 cannot produce, because it ignores the
  /// pragma outright.
  Object? failure;

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    final match = RegExp(r"^PRAGMA rekey = '(.*)'$").firstMatch(statement);
    if (match != null) {
      keys.add(match.group(1)!);
      final failure = this.failure;
      if (failure != null) return Future<void>.error(failure);
    }
    return super.runCustom(executor, statement, args);
  }
}

/// Storage whose deletes and listings can be made to fail by path, the way
/// the real service fails: `object-not-found` for an object already gone,
/// anything else for a transient fault.
class _ScriptedStorage extends MockFirebaseStorage {
  final deleteFailures = <String, FirebaseException>{};
  FirebaseException? listFailure;

  @override
  Reference ref([String? path]) => _ScriptedReference(this, super.ref(path));
}

class _ScriptedReference implements Reference {
  final _ScriptedStorage _storage;
  final Reference _inner;

  _ScriptedReference(this._storage, this._inner);

  String get _path =>
      _inner.fullPath.replaceFirst('gs://${_storage.bucket}', '');

  @override
  Future<void> delete() async {
    final failure = _storage.deleteFailures[_path];
    if (failure != null) throw failure;
    await _inner.delete();
  }

  @override
  Future<ListResult> listAll() async {
    final failure = _storage.listFailure;
    if (failure != null) throw failure;
    return _inner.listAll();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
