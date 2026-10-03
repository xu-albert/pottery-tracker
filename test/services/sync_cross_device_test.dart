import 'dart:io';

import 'package:clock/clock.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/services/sync_queue.dart';
import 'package:pottery_tracker/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_secure_storage.dart';

const _uid = 'u1';

/// Two devices, A and B, as two in-memory databases sharing one fake
/// Firestore and Storage — the regression cases of the 2026-10-02 sync audit
/// (H1–H3), each of which needs a second device to show.
///
/// Both devices share one preferences store, so each test gives B nothing
/// stored that A's pull would read: B only ever pushes, or pulls with no
/// watermark of its own in play.
void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseStorage storage;
  late AppDatabase dbA;
  late AppDatabase dbB;
  late SyncQueue queueA;
  late SyncService a;
  late SyncService b;
  late Directory docsDir;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    docsDir = Directory.systemTemp.createTempSync('cross_device_docs_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => docsDir.path,
        );
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance = FakeSecureStoragePlatform();
    firestore = FakeFirebaseFirestore();
    storage = MockFirebaseStorage();
    dbA = AppDatabase.forTesting(NativeDatabase.memory());
    dbB = AppDatabase.forTesting(NativeDatabase.memory());
    queueA = SyncQueue();
    a = SyncService(dbA, firestore, storage, queue: queueA);
    b = SyncService(dbB, firestore, storage, queue: SyncQueue());
  });

  tearDown(() async {
    await dbA.close();
    await dbB.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (docsDir.existsSync()) docsDir.deleteSync(recursive: true);
  });

  Future<void> insertPiece(
    AppDatabase db,
    String id, {
    String? title,
    required DateTime at,
  }) => db.piecesDao.insertPiece(
    PiecesCompanion(
      id: Value(id),
      title: Value(title),
      createdAt: Value(at),
      updatedAt: Value(at),
    ),
  );

  Future<void> retitle(AppDatabase db, String id, String title, DateTime at) =>
      db.piecesDao.updatePiece(
        PiecesCompanion(
          id: Value(id),
          title: Value(title),
          updatedAt: Value(at),
        ),
      );

  /// A piece doc as the server holds it, stamped [updatedAt] — what another
  /// device's push leaves behind, with the stamp chosen by the test.
  Future<void> remotePiece(String id, String title, DateTime updatedAt) =>
      firestore.doc('users/$_uid/pieces/$id').set({
        'title': title,
        'isArchived': false,
        'createdAt': Timestamp.fromDate(DateTime(2025)),
        'updatedAt': Timestamp.fromDate(updatedAt),
      });

  Future<void> insertGlaze(AppDatabase db, String id, String name) => db
      .into(db.glazeOptions)
      .insert(
        GlazeOptionsCompanion.insert(
          id: id,
          name: name,
          createdAt: DateTime(2025),
        ),
      );

  Future<String?> titleOn(AppDatabase db, String id) async =>
      (await db.piecesDao.getPieceById(id))?.title;

  CollectionReference<Map<String, dynamic>> col(String name) =>
      firestore.collection('users/$_uid/$name');

  group('H1: incremental pulls reach every remote edit', () {
    test('an edit made offline on another device and pushed after this '
        'device pulled still arrives', () async {
      final t0 = DateTime.now().subtract(const Duration(hours: 2));
      await insertPiece(dbB, 'p1', title: 'Bowl', at: t0);
      await b.pushPiece(_uid, 'p1');
      // A's own recent work, so A's pull reaches the present.
      await insertPiece(dbA, 'p0', title: 'Mug', at: DateTime.now());
      await a.pushPiece(_uid, 'p0');
      await a.pullAll(_uid);
      expect(await titleOn(dbA, 'p1'), 'Bowl');

      // B edits at 09:00 while offline; A syncs at 10:00; B reconnects at
      // 12:00 and pushes the 09:00 edit.
      await retitle(
        dbB,
        'p1',
        'Edited on B while offline',
        DateTime.now().subtract(const Duration(hours: 1)),
      );
      await a.pullChangedSince(_uid);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await b.pushPiece(_uid, 'p1');

      await a.pullChangedSince(_uid);
      expect(await titleOn(dbA, 'p1'), 'Edited on B while offline');
    });

    test('a pushed piece carries server time, not its edit time', () async {
      final edited = DateTime(2025, 1, 1);
      await insertPiece(dbB, 'p1', title: 'Bowl', at: edited);
      final before = DateTime.now();
      await b.pushPiece(_uid, 'p1');

      final stamp =
          ((await col('pieces').doc('p1').get())['updatedAt'] as Timestamp)
              .toDate();
      expect(stamp.isBefore(before), isFalse);
    });

    test('the watermark is server time: writes the server stamps behind a '
        'fast local clock still arrive', () async {
      // The server runs two hours behind this device.
      final serverNow = DateTime.now().subtract(const Duration(hours: 2));
      await remotePiece('p1', 'First', serverNow);
      await a.pullAll(_uid);

      await remotePiece(
        'p2',
        'Written after A pulled',
        serverNow.add(const Duration(minutes: 5)),
      );
      await a.pullChangedSince(_uid);

      expect(await titleOn(dbA, 'p2'), 'Written after A pulled');
    });

    test('a piece dated ahead by an earlier version on a fast clock does not '
        'carry the watermark past later writes', () async {
      await remotePiece(
        'legacy',
        'From a fast clock',
        DateTime.now().add(const Duration(days: 1)),
      );
      await a.pullAll(_uid);

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await insertPiece(dbB, 'p2', title: 'Pushed later', at: DateTime(2025));
      await b.pushPiece(_uid, 'p2');
      await a.pullChangedSince(_uid);

      expect(await titleOn(dbA, 'p2'), 'Pushed later');
    });

    test('a device whose clock runs ahead takes a later edit from another '
        'device', () async {
      await insertPiece(
        dbB,
        'p1',
        title: 'Bowl',
        at: DateTime.now().subtract(const Duration(hours: 1)),
      );
      await b.pushPiece(_uid, 'p1');
      await a.pullAll(_uid);

      // A's clock runs two hours ahead, so its edit carries a time two hours
      // after the server's.
      await retitle(
        dbA,
        'p1',
        'Edited on A',
        DateTime.now().add(const Duration(hours: 2)),
      );
      await a.pushPiece(_uid, 'p1');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await retitle(dbB, 'p1', 'Edited on B afterwards', DateTime.now());
      await b.pushPiece(_uid, 'p1');

      await a.pullChangedSince(_uid);
      expect(await titleOn(dbA, 'p1'), 'Edited on B afterwards');
    });

    test('the watermark is capped at the server clock, not this device\'s: a '
        'piece an earlier version dated ahead of the server but behind this '
        'device does not carry it past later writes', () async {
      // The server runs two hours behind this device.
      final server = FakeFirebaseFirestore(
        clock: Clock(() => DateTime.now().subtract(const Duration(hours: 2))),
      );
      final onA = SyncService(dbA, server, storage, queue: queueA);
      final onB = SyncService(dbB, server, storage, queue: SyncQueue());
      // Pushed by an earlier version on a device as fast as this one.
      await server.doc('users/$_uid/pieces/legacy').set({
        'title': 'From a fast clock',
        'isArchived': false,
        'createdAt': Timestamp.fromDate(DateTime(2025)),
        'updatedAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(hours: 1)),
        ),
      });
      await onA.pullAll(_uid);

      await insertPiece(dbB, 'p2', title: 'Pushed later', at: DateTime(2025));
      await onB.pushPiece(_uid, 'p2');
      await onA.pullChangedSince(_uid);

      expect(await titleOn(dbA, 'p2'), 'Pushed later');
    });

    test('after an upgrade, the first incremental pull heals an edit and a '
        'photo URL the previous version missed a week ago', () async {
      final weekAgo = DateTime.now().subtract(const Duration(days: 7));
      // The previous version kept one device-clock watermark, saved now.
      SharedPreferences.setMockInitialValues({
        '${SyncService.lastPulledAtPrefix}$_uid':
            DateTime.now().millisecondsSinceEpoch,
      });
      await insertPiece(
        dbA,
        'p1',
        title: 'Before the missed edit',
        at: weekAgo.subtract(const Duration(days: 1)),
      );
      await dbA.photosDao.insertPhoto(
        PhotosCompanion(
          id: const Value('ph1'),
          pieceId: const Value('p1'),
          localPath: Value('${docsDir.path}/photos/p1/ph1.jpg'),
          dateTaken: Value(weekAgo),
          createdAt: Value(weekAgo),
        ),
      );
      // Written by the server a week ago, behind every watermark since.
      await remotePiece('p1', 'Edited a week ago', weekAgo);
      await col('photos').doc('ph1').set({
        'pieceId': 'p1',
        'cloudUrl': 'https://example.test/ph1.jpg',
        'dateTaken': Timestamp.fromDate(weekAgo),
        'createdAt': Timestamp.fromDate(weekAgo),
        'sortOrder': 0,
        'updatedAt': Timestamp.fromDate(weekAgo),
      });

      await a.pullChangedSince(_uid);

      expect(await titleOn(dbA, 'p1'), 'Edited a week ago');
      expect(
        (await dbA.photosDao.getPhotoById('ph1'))!.cloudUrl,
        'https://example.test/ph1.jpg',
      );
    });
  });

  group(
    'H2: a pull never overwrites local edits that have not been pushed',
    () {
      test('an incremental pull does not replace a newer local piece edit with '
          'an older remote one', () async {
        final t0 = DateTime.now().subtract(const Duration(hours: 3));
        await insertPiece(dbA, 'p1', title: 'Bowl', at: t0);
        await a.pushPiece(_uid, 'p1');
        await a.pullAll(_uid);

        // Stamped after the watermark's overlap begins, so the pull reads it.
        await remotePiece(
          'p1',
          'Older remote edit',
          DateTime.now().subtract(const Duration(seconds: 30)),
        );
        await retitle(dbA, 'p1', 'Newer local edit', DateTime.now());

        await a.pullChangedSince(_uid);
        expect(await titleOn(dbA, 'p1'), 'Newer local edit');
      });

      test('a piece edit still queued is kept even against a newer remote '
          'edit, and stays queued', () async {
        final t0 = DateTime.now().subtract(const Duration(hours: 3));
        await insertPiece(dbA, 'p1', title: 'Queued local edit', at: t0);
        const entry = SyncQueueEntry(
          operation: SyncOperation.pushPiece,
          entityId: 'p1',
        );
        await queueA.enqueue(entry);
        await remotePiece('p1', 'Remote edit', DateTime.now());

        await a.pullAll(_uid);

        expect(await titleOn(dbA, 'p1'), 'Queued local edit');
        expect(await queueA.getAll(), [entry]);
      });

      test('an unpushed glaze change survives the pull, and the pull does not '
          'move updatedAt', () async {
        final t0 = DateTime.now().subtract(const Duration(days: 1));
        await insertPiece(dbA, 'p1', at: t0);
        await insertGlaze(dbA, 'g1', 'Celadon');
        await insertGlaze(dbA, 'g2', 'Tenmoku');
        await dbA.materialsDao.setGlazesForPiece('p1', ['g1']);
        await a.pushPiece(_uid, 'p1');
        await a.pushPieceGlazes(_uid, 'p1');

        // The user swaps the glaze, which queues the piece's links and the
        // piece itself as the piece screen does; neither push has happened.
        await dbA.materialsDao.setGlazesForPiece('p1', ['g2']);
        for (final operation in [
          SyncOperation.pushPieceGlazes,
          SyncOperation.pushPiece,
        ]) {
          await queueA.enqueue(
            SyncQueueEntry(operation: operation, entityId: 'p1'),
          );
        }

        final stamp = (await dbA.piecesDao.getPieceById('p1'))!.updatedAt;

        await a.pullChangedSince(_uid);

        final glazes = await dbA.materialsDao.getGlazesForPiece('p1');
        expect(glazes.map((g) => g.id), ['g2']);
        final piece = (await dbA.piecesDao.getPieceById('p1'))!;
        expect(piece.updatedAt, stamp);
      });

      test("applying another device's glaze links does not move the piece's "
          'updatedAt', () async {
        final t0 = DateTime.now().subtract(const Duration(days: 1));
        for (final db in [dbA, dbB]) {
          await insertPiece(db, 'p1', title: 'Bowl', at: t0);
          await insertGlaze(db, 'g1', 'Celadon');
        }
        await a.pullAll(_uid);
        final stamp = (await dbA.piecesDao.getPieceById('p1'))!.updatedAt;

        await dbB.materialsDao.setGlazesForPiece('p1', ['g1']);
        await b.pushPieceGlazes(_uid, 'p1');
        await a.pullChangedSince(_uid);

        expect(
          (await dbA.materialsDao.getGlazesForPiece('p1')).map((g) => g.id),
          ['g1'],
        );
        final piece = (await dbA.piecesDao.getPieceById('p1'))!;
        expect(piece.updatedAt, stamp);
      });

      test('a piece deleted here with its deletion still queued is not brought '
          'back by a pull', () async {
        await remotePiece('p1', 'Deleted on A', DateTime.now());
        await queueA.enqueue(
          const SyncQueueEntry(
            operation: SyncOperation.deletePiece,
            entityId: 'p1',
          ),
        );

        await a.pullAll(_uid);

        expect(await dbA.piecesDao.getPieceById('p1'), isNull);
      });

      test('a photo reorder still queued is not reverted', () async {
        final t0 = DateTime.now().subtract(const Duration(hours: 1));
        await insertPiece(dbA, 'p1', at: t0);
        await dbA.photosDao.insertPhoto(
          PhotosCompanion(
            id: const Value('ph1'),
            pieceId: const Value('p1'),
            localPath: const Value('/nowhere.jpg'),
            dateTaken: Value(t0),
            createdAt: Value(t0),
            sortOrder: const Value(0),
          ),
        );
        await a.pushPhoto(_uid, 'ph1');
        await dbA.photosDao.updateSortOrders([(id: 'ph1', sortOrder: 4)]);
        await queueA.enqueue(
          const SyncQueueEntry(
            operation: SyncOperation.pushPhoto,
            entityId: 'ph1',
          ),
        );

        await a.pullAll(_uid);

        expect((await dbA.photosDao.getPhotoById('ph1'))!.sortOrder, 4);
      });

      test('a material rename still queued is not reverted', () async {
        await insertGlaze(dbA, 'g1', 'Celadon');
        await a.pushGlaze(_uid, 'g1');
        await dbA.materialsDao.updateGlazeName('g1', 'Celadon Blue');
        await queueA.enqueue(
          const SyncQueueEntry(
            operation: SyncOperation.pushGlaze,
            entityId: 'g1',
          ),
        );

        await a.pullAll(_uid);

        final glazes = await dbA.materialsDao.getAllGlazes();
        expect(glazes.map((g) => g.name), ['Celadon Blue']);
      });
    },
  );

  group('H3: a photo URL reaches every device and is never nulled', () {
    Future<File> photoOnA() async {
      final t0 = DateTime.now().subtract(const Duration(hours: 1));
      await insertPiece(dbA, 'p1', at: t0);
      final file = File('${docsDir.path}/photos/p1/ph1.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      await dbA.photosDao.insertPhoto(
        PhotosCompanion(
          id: const Value('ph1'),
          pieceId: const Value('p1'),
          localPath: Value(file.path),
          dateTaken: Value(t0),
          createdAt: Value(t0),
        ),
      );
      await a.pushPiece(_uid, 'p1');
      await a.pushPhoto(_uid, 'ph1');
      return file;
    }

    test('a URL published after another device pulled the photo reaches that '
        'device, and its pushPhoto keeps it', () async {
      await photoOnA();
      // ph1's metadata reached the cloud a while ago, and another photo since,
      // so B's pull passes ph1 by more than its overlap.
      await col('photos').doc('ph1').update({
        'updatedAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(hours: 1)),
        ),
      });
      await col('photos').doc('ph0').set({
        'pieceId': 'p1',
        'dateTaken': Timestamp.fromDate(DateTime(2025)),
        'createdAt': Timestamp.fromDate(DateTime(2025)),
        'sortOrder': 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await b.pullAll(_uid);
      expect((await dbB.photosDao.getPhotoById('ph1'))!.cloudUrl, isNull);

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await a.uploadPhotoFile(_uid, 'ph1');
      final url = (await col('photos').doc('ph1').get())['cloudUrl'];
      expect(url, isNotNull);

      await b.pullChangedSince(_uid);
      expect((await dbB.photosDao.getPhotoById('ph1'))!.cloudUrl, url);

      await b.pushPhoto(_uid, 'ph1');
      expect((await col('photos').doc('ph1').get())['cloudUrl'], url);
    });

    test('a device that has not learned the URL does not null it with '
        'pushPhoto', () async {
      await photoOnA();
      await b.pullAll(_uid);
      await a.uploadPhotoFile(_uid, 'ph1');
      final url = (await col('photos').doc('ph1').get())['cloudUrl'];

      // B reorders before its next pull.
      await dbB.photosDao.updateSortOrders([(id: 'ph1', sortOrder: 2)]);
      await b.pushPhoto(_uid, 'ph1');

      final remote = (await col('photos').doc('ph1').get()).data()!;
      expect(remote['cloudUrl'], url);
      expect(remote['sortOrder'], 2);
    });

    test('a remote null written by an earlier version does not replace a '
        'local URL, and the device holding it puts it back', () async {
      await photoOnA();
      await a.uploadPhotoFile(_uid, 'ph1');
      final url = (await dbA.photosDao.getPhotoById('ph1'))!.cloudUrl;
      expect(url, isNotNull);

      // An earlier version's pushPhoto from a device without the URL.
      await col('photos').doc('ph1').set({
        'cloudUrl': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await a.pullAll(_uid);

      expect((await dbA.photosDao.getPhotoById('ph1'))!.cloudUrl, url);
      const republish = SyncQueueEntry(
        operation: SyncOperation.pushPhoto,
        entityId: 'ph1',
      );
      expect(await queueA.getAll(), [republish]);
      await a.pushPhoto(_uid, 'ph1');
      expect((await col('photos').doc('ph1').get())['cloudUrl'], url);
    });

    test('a full pull recovers a URL an earlier version published without '
        'moving updatedAt', () async {
      await photoOnA();
      await b.pullAll(_uid);
      await col(
        'photos',
      ).doc('ph1').update({'cloudUrl': 'https://example.test/ph1.jpg'});

      await b.pullAll(_uid);

      expect(
        (await dbB.photosDao.getPhotoById('ph1'))!.cloudUrl,
        'https://example.test/ph1.jpg',
      );
    });
  });
}
