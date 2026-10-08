import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/providers/sync_provider.dart';
import 'package:pottery_tracker/services/material_writer.dart';
import 'package:pottery_tracker/services/sync_queue.dart';
import 'package:pottery_tracker/services/sync_service.dart';
import 'package:pottery_tracker/services/sync_trigger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How a sync orders its pulls around local work, run through the real
/// notifier, service, queue and Drift against a fake Firestore.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A sync pulls even when its pushes failed with the server reachable —
  // permission denied, App Check, an exhausted write quota. That pull must
  // not revert the edit the failed push still owes the cloud, or the retry
  // would send the reverted row and report it backed up (sync audit H2).
  test('a pull after a failed push keeps the unpushed edit and its queue '
      'entry', () async {
    SharedPreferences.setMockInitialValues({
      '${SyncService.lastPulledAtPrefix}user-1': DateTime(
        2026,
      ).millisecondsSinceEpoch,
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final firestore = FakeFirebaseFirestore();
    final queue = SyncQueue();
    final service = _RefusedPushService(
      db,
      firestore,
      MockFirebaseStorage(),
      queue: queue,
    );

    final edited = DateTime(2026, 2, 1);
    await db.piecesDao.insertPiece(
      PiecesCompanion(
        id: const Value('p1'),
        title: const Value('Unpushed local edit'),
        createdAt: Value(edited),
        updatedAt: Value(edited),
      ),
    );
    const entry = SyncQueueEntry(
      operation: SyncOperation.pushPiece,
      entityId: 'p1',
    );
    await queue.enqueue(entry);
    // Another device's edit, pushed since this device's last pull.
    await firestore.doc('users/user-1/pieces/p1').set({
      'title': 'Remote edit',
      'isArchived': false,
      'createdAt': Timestamp.fromDate(edited),
      'updatedAt': Timestamp.now(),
    });

    final container = _container(queue, service);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    // The spinner stops once the pushes are dispatched; the verdict is the
    // state the pull publishes after them.
    final finished = Completer<SyncState>();
    final sub = container.listen(syncStateProvider, (_, next) {
      if (service.pulls > 0 &&
          next.status != SyncStatus.syncing &&
          !finished.isCompleted) {
        finished.complete(next);
      }
    });
    addTearDown(sub.close);

    container.read(authProvider.notifier).state = const AuthState(
      status: AuthStatus.authenticated,
      uid: 'user-1',
    );
    final result = await finished.future.timeout(const Duration(seconds: 5));

    expect(service.pushAttempts, greaterThan(0));
    expect(service.pulls, 1, reason: 'the pull ran after the failed push');
    expect(
      (await db.piecesDao.getPieceById('p1'))!.title,
      'Unpushed local edit',
    );
    expect(await queue.getAll(), [entry]);
    expect(result.status, SyncStatus.error);
    expect(result.lastSyncedAt, isNull);
  });

  // A forced sync pushes every local row with a fresh server stamp. Pushed
  // before the pull, a copy this device held out of date would replace the
  // newer edit on every other device.
  test('a forced sync from a stale device keeps the newer edit made '
      'elsewhere', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final firestore = FakeFirebaseFirestore();
    final queue = SyncQueue();
    final service = SyncService(
      db,
      firestore,
      MockFirebaseStorage(),
      queue: queue,
    );
    final created = DateTime.now().subtract(const Duration(days: 7));
    await db.piecesDao.insertPiece(
      PiecesCompanion(
        id: const Value('p1'),
        title: const Value('Bowl'),
        createdAt: Value(created),
        updatedAt: Value(created),
      ),
    );

    final container = _container(queue, service);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    final synced = Completer<void>();
    final sub = container.listen(syncStateProvider, (_, next) {
      if (next.lastSyncedAt != null && !synced.isCompleted) synced.complete();
    });
    addTearDown(sub.close);
    container.read(authProvider.notifier).state = const AuthState(
      status: AuthStatus.authenticated,
      uid: 'user-1',
    );
    await synced.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(Duration.zero);

    // Another device edits the piece after this one last synced.
    await firestore.doc('users/user-1/pieces/p1').set({
      'title': 'Edited on another device',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await container
        .read(syncStateProvider.notifier)
        .syncNow(forceFullSync: true);

    final remote = await firestore.doc('users/user-1/pieces/p1').get();
    expect(remote['title'], 'Edited on another device');
    expect(
      (await db.piecesDao.getPieceById('p1'))!.title,
      'Edited on another device',
    );
    expect(container.read(syncStateProvider).status, SyncStatus.idle);
  });

  // A clay rename queues every piece it renamed, and the drain sends them with
  // no pull first. Sent whole, this device's copy of such a piece would
  // replace an edit another device made to it since this one last pulled.
  test('a clay rename on a stale device keeps the edit another device made '
      'to a renamed piece', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final firestore = FakeFirebaseFirestore();
    final queue = SyncQueue();
    final service = SyncService(
      db,
      firestore,
      MockFirebaseStorage(),
      queue: queue,
    );
    final (clay, _) = await db.materialsDao.findOrCreateClay('Stoneware');
    final created = DateTime.now().subtract(const Duration(days: 7));
    await db.piecesDao.insertPiece(
      PiecesCompanion(
        id: const Value('p1'),
        notes: const Value('Bisque at 04'),
        clayType: const Value('Stoneware'),
        createdAt: Value(created),
        updatedAt: Value(created),
      ),
    );

    final container = _container(queue, service);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    final synced = _syncedOnce(container);
    container.read(authProvider.notifier).state = const AuthState(
      status: AuthStatus.authenticated,
      uid: 'user-1',
    );
    await synced.timeout(const Duration(seconds: 5));
    await _until(() async => (await queue.getAll()).isEmpty);

    // On the iPad the user edits the piece's notes, and the iPad pushes.
    await firestore.doc('users/user-1/pieces/p1').update({
      'notes': 'Glazed in celadon',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // On this phone, which has not pulled since, the user renames the clay.
    await MaterialWriter(
      db.materialsDao,
      container.read(syncTriggerProvider),
    ).renameClay(clay.id, 'B-Mix');
    await _until(() async => (await queue.getAll()).isEmpty);

    final remote = await firestore.doc('users/user-1/pieces/p1').get();
    expect(remote['notes'], 'Glazed in celadon');
    expect(remote['clayType'], 'B-Mix');

    await container.read(syncStateProvider.notifier).syncNow();
    final piece = (await db.piecesDao.getPieceById('p1'))!;
    expect(piece.notes, 'Glazed in celadon');
    expect(piece.clayType, 'B-Mix');
  });

  // A reorder queues every material in the list, and the drain sends them
  // with no pull first. Sent whole, this device's copy of a material would
  // put back a name another device gave it since this one last pulled, and
  // leave the pieces that rename reached naming a clay the list no longer has.
  test('a reorder on a stale device keeps the rename another device made to '
      'a reordered clay', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final firestore = FakeFirebaseFirestore();
    final queue = SyncQueue();
    final service = SyncService(
      db,
      firestore,
      MockFirebaseStorage(),
      queue: queue,
    );
    final (misspelt, _) = await db.materialsDao.findOrCreateClay('Stonewar');
    final (porcelain, _) = await db.materialsDao.findOrCreateClay('Porcelain');
    final created = DateTime.now().subtract(const Duration(days: 7));
    await db.piecesDao.insertPiece(
      PiecesCompanion(
        id: const Value('p1'),
        clayType: const Value('Stonewar'),
        createdAt: Value(created),
        updatedAt: Value(created),
      ),
    );

    final container = _container(queue, service);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    final synced = _syncedOnce(container);
    container.read(authProvider.notifier).state = const AuthState(
      status: AuthStatus.authenticated,
      uid: 'user-1',
    );
    await synced.timeout(const Duration(seconds: 5));
    await _until(() async => (await queue.getAll()).isEmpty);

    // On the phone the user fixes the clay's name, and the phone pushes the
    // clay and the piece the rename reached.
    await firestore.doc('users/user-1/clays/${misspelt.id}').update({
      'name': 'Stoneware',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await firestore.doc('users/user-1/pieces/p1').update({
      'clayType': 'Stoneware',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // On this iPad, which has not pulled since, the user drags Porcelain up.
    await MaterialWriter(
      db.materialsDao,
      container.read(syncTriggerProvider),
    ).reorderClays([porcelain.id, misspelt.id]);
    await _until(() async => (await queue.getAll()).isEmpty);

    final remote = await firestore
        .doc('users/user-1/clays/${misspelt.id}')
        .get();
    expect(remote['name'], 'Stoneware');
    expect(remote['sortOrder'], 1);

    await container.read(syncStateProvider.notifier).syncNow();
    expect((await db.materialsDao.getAllClays()).map((c) => c.name), [
      'Porcelain',
      'Stoneware',
    ]);
    expect((await db.piecesDao.getPieceById('p1'))!.clayType, 'Stoneware');
  });

  test('a reorder on a stale device keeps the glaze rename and tag colour '
      'another device made', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final firestore = FakeFirebaseFirestore();
    final queue = SyncQueue();
    final service = SyncService(
      db,
      firestore,
      MockFirebaseStorage(),
      queue: queue,
    );
    final materials = db.materialsDao;
    final (celadon, _) = await materials.findOrCreateGlaze('Celadon');
    final (tenmoku, _) = await materials.findOrCreateGlaze('Tenmoku');
    final (gift, _) = await materials.findOrCreateTag('Gift');
    final (sold, _) = await materials.findOrCreateTag('Sold');
    await materials.updateTagColor(gift.id, '#E53935');

    final container = _container(queue, service);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    final synced = _syncedOnce(container);
    container.read(authProvider.notifier).state = const AuthState(
      status: AuthStatus.authenticated,
      uid: 'user-1',
    );
    await synced.timeout(const Duration(seconds: 5));
    await _until(() async => (await queue.getAll()).isEmpty);

    // On the phone the user renames a glaze and recolours a tag.
    await firestore.doc('users/user-1/glazes/${celadon.id}').update({
      'name': 'Celadon Blue',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await firestore.doc('users/user-1/tags/${gift.id}').update({
      'color': '#43A047',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // On this iPad, which has not pulled since, the user drags both lists.
    final writer = MaterialWriter(
      materials,
      container.read(syncTriggerProvider),
    );
    await writer.reorderGlazes([tenmoku.id, celadon.id]);
    await writer.reorderTags([sold.id, gift.id]);
    await _until(() async => (await queue.getAll()).isEmpty);

    final glaze = await firestore
        .doc('users/user-1/glazes/${celadon.id}')
        .get();
    expect(glaze['name'], 'Celadon Blue');
    expect(glaze['sortOrder'], 1);
    final tag = await firestore.doc('users/user-1/tags/${gift.id}').get();
    expect(tag['name'], 'Gift');
    expect(tag['color'], '#43A047');
    expect(tag['sortOrder'], 1);

    await container.read(syncStateProvider.notifier).syncNow();
    expect((await materials.getAllGlazes()).map((g) => g.name), [
      'Tenmoku',
      'Celadon Blue',
    ]);
    expect(
      [for (final t in await materials.getAllTags()) (t.name, t.color)],
      [('Sold', sold.color), ('Gift', '#43A047')],
    );
  });

  // A drain reads the queue once, then reaches each entry when its lane does.
  // An edit made in between widens the queued rename to the whole row, and a
  // push sending only the clay must not be the one that answers for it.
  test('an edit made while a clay rename waits in its lane behind a held '
      'link push is pushed', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final firestore = FakeFirebaseFirestore();
    final queue = SyncQueue();
    final service = _HeldLinksService(
      db,
      firestore,
      MockFirebaseStorage(),
      queue: queue,
    );
    final (clay, _) = await db.materialsDao.findOrCreateClay('Stoneware');
    final created = DateTime.now().subtract(const Duration(days: 7));
    await db.piecesDao.insertPiece(
      PiecesCompanion(
        id: const Value('p1'),
        notes: const Value('Bisque at 04'),
        clayType: const Value('Stoneware'),
        createdAt: Value(created),
        updatedAt: Value(created),
      ),
    );

    final container = _container(queue, service);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    final synced = _syncedOnce(container);
    container.read(authProvider.notifier).state = const AuthState(
      status: AuthStatus.authenticated,
      uid: 'user-1',
    );
    await synced.timeout(const Duration(seconds: 5));
    await _until(() async => (await queue.getAll()).isEmpty);

    // Writes whose own drains have not fired yet, so one drain reads them all.
    final pending = SyncTrigger(queue);
    final release = Completer<void>();
    service.hold = release.future;
    await pending.afterPieceGlazesWrite('p1');
    await MaterialWriter(db.materialsDao, pending).renameClay(clay.id, 'B-Mix');
    container.read(syncStateProvider.notifier).scheduleProcessQueue();
    await _until(() async => service.held);

    // The user edits the notes while the rename waits behind the link push.
    await db.piecesDao.updatePiece(
      const PiecesCompanion(id: Value('p1'), notes: Value('Glazed in celadon')),
    );
    await pending.afterPieceWrite('p1');
    release.complete();
    await _until(() async => (await queue.getAll()).isEmpty);

    final remote = await firestore.doc('users/user-1/pieces/p1').get();
    expect(remote['notes'], 'Glazed in celadon');
    expect(remote['clayType'], 'B-Mix');
  });

  // A snapshot push lands with the server's time whenever it gets through, so
  // a copy of a row the cloud already held, sent after a dropped connection
  // let it through late, would replace an edit made meanwhile elsewhere.
  test('a first sync leaves out of its snapshot what its pull found in the '
      'cloud', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final firestore = FakeFirebaseFirestore();
    final queue = SyncQueue();
    final service = _HeldPushService(
      db,
      firestore,
      MockFirebaseStorage(),
      queue: queue,
    );
    final created = DateTime.now().subtract(const Duration(days: 7));
    // The cloud holds p1 as this device has it; p2 was made here.
    await firestore.doc('users/user-1/pieces/p1').set({
      'title': 'Bowl',
      'isArchived': false,
      'createdAt': Timestamp.fromDate(created),
      'updatedAt': Timestamp.fromDate(created),
    });
    for (final (id, title) in [('p1', 'Bowl'), ('p2', 'Mug')]) {
      await db.piecesDao.insertPiece(
        PiecesCompanion(
          id: Value(id),
          title: Value(title),
          createdAt: Value(created),
          updatedAt: Value(created),
        ),
      );
    }

    final container = _container(queue, service);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    final synced = Completer<void>();
    final sub = container.listen(syncStateProvider, (_, next) {
      if (next.lastSyncedAt != null && !synced.isCompleted) synced.complete();
    });
    addTearDown(sub.close);
    container.read(authProvider.notifier).state = const AuthState(
      status: AuthStatus.authenticated,
      uid: 'user-1',
    );
    await _until(() async => service.heldPushes.isNotEmpty);

    // Another device edits p1 while the snapshot's pushes are held up.
    await firestore.doc('users/user-1/pieces/p1').set({
      'title': 'Edited on another device',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    service.release.complete();
    await synced.future.timeout(const Duration(seconds: 5));

    expect(service.heldPushes, ['p2']);
    final remote = await firestore.doc('users/user-1/pieces/p1').get();
    expect(remote['title'], 'Edited on another device');
    expect(
      (await db.piecesDao.getPieceById('p1'))!.title,
      'Edited on another device',
    );
  });

  // Links are pushed as a whole set: pushing this device's links for a piece
  // the cloud already holds would restore one another device removed.
  test('a first sync does not push the links of a piece its pull found in '
      'the cloud', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final firestore = FakeFirebaseFirestore();
    final queue = SyncQueue();
    final service = SyncService(
      db,
      firestore,
      MockFirebaseStorage(),
      queue: queue,
    );
    final created = DateTime.now().subtract(const Duration(days: 7));
    // Another device removed p1's glaze and tag, so the cloud has no links.
    await firestore.doc('users/user-1/pieces/p1').set({
      'title': 'Bowl',
      'isArchived': false,
      'createdAt': Timestamp.fromDate(created),
      'updatedAt': Timestamp.fromDate(created),
    });
    await db.piecesDao.insertPiece(
      PiecesCompanion(
        id: const Value('p1'),
        title: const Value('Bowl'),
        createdAt: Value(created),
        updatedAt: Value(created),
      ),
    );
    await db
        .into(db.glazeOptions)
        .insert(
          GlazeOptionsCompanion.insert(
            id: 'g1',
            name: 'Celadon',
            createdAt: created,
          ),
        );
    await db
        .into(db.tagOptions)
        .insert(
          TagOptionsCompanion.insert(
            id: 't1',
            name: 'Gift',
            createdAt: created,
          ),
        );
    await db.materialsDao.setGlazesForPiece('p1', [
      'g1',
    ], touchUpdatedAt: false);
    await db.materialsDao.setTagsForPiece('p1', ['t1'], touchUpdatedAt: false);

    final container = _container(queue, service);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    final synced = _syncedOnce(container);
    container.read(authProvider.notifier).state = const AuthState(
      status: AuthStatus.authenticated,
      uid: 'user-1',
    );
    await synced.timeout(const Duration(seconds: 5));

    for (final links in ['pieceGlazes', 'pieceTags']) {
      expect(
        (await firestore.collection('users/user-1/$links').get()).docs,
        isEmpty,
        reason: 'the removal made elsewhere must stand',
      );
    }
  });

  // A row only the snapshot uploads — like the glaze a schema backfill
  // creates, with no queue entry of its own — stays local for good if a first
  // sync is recorded as done before its snapshot is queued.
  test('a first sync interrupted after its pull stages its snapshot on the '
      'next launch', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final firestore = FakeFirebaseFirestore();
    await db
        .into(db.glazeOptions)
        .insert(
          GlazeOptionsCompanion.insert(
            id: 'g1',
            name: 'Celadon',
            createdAt: DateTime(2025),
          ),
        );

    final interruptedQueue = SyncQueue();
    final interrupted = _container(
      interruptedQueue,
      _InterruptedSnapshotService(
        db,
        firestore,
        MockFirebaseStorage(),
        queue: interruptedQueue,
      ),
    );
    final failed = Completer<void>();
    final sub = interrupted.listen(syncStateProvider, (_, next) {
      if (next.status == SyncStatus.error && !failed.isCompleted) {
        failed.complete();
      }
    });
    interrupted.read(authProvider.notifier).state = const AuthState(
      status: AuthStatus.authenticated,
      uid: 'user-1',
    );
    await failed.future.timeout(const Duration(seconds: 5));
    sub.close();
    interrupted.dispose();

    final queue = SyncQueue();
    final service = SyncService(
      db,
      firestore,
      MockFirebaseStorage(),
      queue: queue,
    );
    expect(await service.getLastPulledAt('user-1'), isNull);
    final relaunched = _container(queue, service);
    addTearDown(relaunched.dispose);
    final synced = _syncedOnce(relaunched);
    relaunched.read(authProvider.notifier).state = const AuthState(
      status: AuthStatus.authenticated,
      uid: 'user-1',
    );
    await synced.timeout(const Duration(seconds: 5));

    final glaze = await firestore.doc('users/user-1/glazes/g1').get();
    expect(glaze.data()?['name'], 'Celadon');
  });

  test('a photo URL a pull finds nulled is pushed back without waiting for '
      'another sync', () async {
    SharedPreferences.setMockInitialValues({
      '${SyncService.lastPulledAtPrefix}user-1': DateTime(
        2026,
      ).millisecondsSinceEpoch,
    });
    final dir = Directory.systemTemp.createTempSync('url_repair_');
    final file = File('${dir.path}/ph1.jpg')..writeAsBytesSync([1, 2, 3]);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final firestore = FakeFirebaseFirestore();
    final queue = SyncQueue();
    const url = 'https://example.test/ph1.jpg';
    final created = DateTime(2026);
    await db.piecesDao.insertPiece(
      PiecesCompanion(
        id: const Value('p1'),
        createdAt: Value(created),
        updatedAt: Value(created),
      ),
    );
    await db.photosDao.insertPhoto(
      PhotosCompanion(
        id: const Value('ph1'),
        pieceId: const Value('p1'),
        localPath: Value(file.path),
        cloudUrl: const Value(url),
        dateTaken: Value(created),
        createdAt: Value(created),
      ),
    );
    // An earlier version's pushPhoto from a device without the URL.
    await firestore.doc('users/user-1/photos/ph1').set({
      'pieceId': 'p1',
      'cloudUrl': null,
      'dateTaken': Timestamp.fromDate(created),
      'createdAt': Timestamp.fromDate(created),
      'sortOrder': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (_) => AuthNotifier.withState(
            const AuthState(status: AuthStatus.unauthenticated),
          ),
        ),
        syncQueueProvider.overrideWithValue(queue),
        syncServiceProvider.overrideWith(
          (ref) => SyncService(
            db,
            firestore,
            MockFirebaseStorage(),
            queue: queue,
            trigger: ref.watch(syncTriggerProvider),
          ),
        ),
        syncStateProvider.overrideWith(
          (ref) => SyncNotifier(
            ref,
            queue,
            ref.watch(syncServiceProvider),
            clock: const _ImmediateClock(),
          ),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
      dir.deleteSync(recursive: true);
    });
    container.read(syncStateProvider.notifier);
    container.read(authProvider.notifier).state = const AuthState(
      status: AuthStatus.authenticated,
      uid: 'user-1',
    );

    await _until(
      () async =>
          (await firestore.doc('users/user-1/photos/ph1').get())
              .data()?['cloudUrl'] ==
          url,
    );
    await _until(() async => (await queue.getAll()).isEmpty);
  });
}

ProviderContainer _container(SyncQueue queue, SyncService service) =>
    ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (_) => AuthNotifier.withState(
            const AuthState(status: AuthStatus.unauthenticated),
          ),
        ),
        syncQueueProvider.overrideWithValue(queue),
        syncServiceProvider.overrideWithValue(service),
        syncStateProvider.overrideWith(
          (ref) =>
              SyncNotifier(ref, queue, service, clock: const _ImmediateClock()),
        ),
      ],
    );

/// Completes the first time a sync stamps Last synced, which it does only
/// after its closing pull.
Future<void> _syncedOnce(ProviderContainer container) {
  final synced = Completer<void>();
  late final ProviderSubscription<SyncState> sub;
  sub = container.listen(syncStateProvider, (_, next) {
    if (next.lastSyncedAt != null && !synced.isCompleted) {
      synced.complete();
      sub.close();
    }
  });
  return synced.future;
}

Future<void> _until(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) fail('the condition never held');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Fails staging its first snapshot, standing in for the app dying between a
/// first sync's pull and the snapshot reaching the queue.
class _InterruptedSnapshotService extends SyncService {
  _InterruptedSnapshotService(
    super.db,
    super.firestore,
    super.storage, {
    super.queue,
  });

  @override
  Future<List<SyncQueueEntry>> fullUploadEntries(String uid) async {
    throw StateError('the app died before the snapshot was queued');
  }
}

/// Holds every glaze-link push while [hold] is set, standing in for one a
/// slow or flapping connection keeps in the air.
class _HeldLinksService extends SyncService {
  _HeldLinksService(super.db, super.firestore, super.storage, {super.queue});

  Future<void>? hold;
  bool held = false;

  @override
  Future<void> pushPieceGlazes(String uid, String pieceId) async {
    final gate = hold;
    if (gate != null) {
      held = true;
      await gate;
    }
    await super.pushPieceGlazes(uid, pieceId);
  }
}

/// Holds every piece push until [release] completes, standing in for writes a
/// dropped connection keeps from the server.
class _HeldPushService extends SyncService {
  _HeldPushService(super.db, super.firestore, super.storage, {super.queue});

  final heldPushes = <String>[];
  final release = Completer<void>();

  @override
  Future<void> pushPiece(
    String uid,
    String pieceId, {
    List<String>? fields,
  }) async {
    heldPushes.add(pieceId);
    await release.future;
    await super.pushPiece(uid, pieceId, fields: fields);
  }
}

class _RefusedPushService extends SyncService {
  _RefusedPushService(super.db, super.firestore, super.storage, {super.queue});

  int pushAttempts = 0;
  int pulls = 0;

  @override
  Future<void> pushPiece(
    String uid,
    String pieceId, {
    List<String>? fields,
  }) async {
    pushAttempts++;
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
  }

  @override
  Future<void> pullChangedSince(String uid) async {
    pulls++;
    await super.pullChangedSince(uid);
  }
}

class _ImmediateClock extends SyncClock {
  const _ImmediateClock();

  @override
  Timer runAfter(Duration delay, void Function() callback) =>
      Timer(Duration.zero, callback);

  @override
  Future<void> sleep(Duration duration) => Future<void>.value();
}
