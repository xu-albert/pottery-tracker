import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/providers/sync_provider.dart';
import 'package:pottery_tracker/services/sync_queue.dart';
import 'package:pottery_tracker/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Service extends SyncService {
  _Service(super.db, super.firestore, super.storage);
  bool failUpload = true;
  Completer<void>? _pulled;

  /// Holds every photo upload until completed, standing in for a slow one.
  Completer<void>? uploadGate;
  int uploadsHeld = 0;

  /// Runs once a snapshot has been read and before it is staged.
  Future<void> Function()? afterSnapshotRead;

  /// Completes once the next pull has finished, which a sync only starts
  /// after its photo uploads have settled.
  Future<void> expectPull() {
    _pulled = Completer<void>();
    return _pulled!.future;
  }

  void _notifyPulled() {
    _pulled?.complete();
    _pulled = null;
  }

  @override
  Future<void> uploadPhotoFile(String uid, String photoId) async {
    if (failUpload) throw Exception('storage unavailable');
    final gate = uploadGate;
    if (gate != null) {
      uploadsHeld++;
      await gate.future;
    }
    await super.uploadPhotoFile(uid, photoId);
  }

  @override
  Future<List<SyncQueueEntry>> fullUploadEntries(String uid) async {
    final entries = await super.fullUploadEntries(uid);
    await afterSnapshotRead?.call();
    return entries;
  }

  @override
  Future<void> pullAll(String uid) async {
    await super.pullAll(uid);
    _notifyPulled();
  }

  @override
  Future<void> pullChangedSince(String uid, DateTime since) async {
    await super.pullChangedSince(uid, since);
    _notifyPulled();
  }
}

/// Counts what reaches Storage: file uploads, and the download-URL lookups
/// that each precede publishing an uploaded file's URL on its photo document.
class _CountingStorage extends MockFirebaseStorage {
  int uploads = 0;
  int urlLookups = 0;

  /// Holds each file upload until completed; the object exists only after.
  Completer<void>? putFileGate;
  int putFilesHeld = 0;

  @override
  Reference ref([String? path]) => _CountingReference(super.ref(path), this);
}

class _CountingReference implements Reference {
  _CountingReference(this._inner, this._storage);
  final Reference _inner;
  final _CountingStorage _storage;

  @override
  UploadTask putFile(File file, [SettableMetadata? metadata]) {
    _storage.uploads++;
    final gate = _storage.putFileGate;
    if (gate == null) return _inner.putFile(file, metadata);
    _storage.putFilesHeld++;
    return _HeldUpload(
      gate.future.then<TaskSnapshot>((_) => _inner.putFile(file, metadata)),
    );
  }

  @override
  Future<void> delete() => _inner.delete();

  @override
  Future<String> getDownloadURL() {
    _storage.urlLookups++;
    return _inner.getDownloadURL();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HeldUpload implements UploadTask {
  _HeldUpload(this._done);
  final Future<TaskSnapshot> _done;

  @override
  Future<S> then<S>(
    FutureOr<S> Function(TaskSnapshot) onValue, {
    Function? onError,
  }) => _done.then(onValue, onError: onError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _waitUntil(Future<bool> Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition was not met');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final full in [true, false]) {
    test('${full ? 'full' : 'incremental'} sync keeps failed photos pending '
        'across restart and clears them after upload', () async {
      SharedPreferences.setMockInitialValues({
        if (!full)
          '${SyncService.lastPulledAtPrefix}user-1': DateTime(
            2020,
          ).millisecondsSinceEpoch,
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final dir = Directory.systemTemp.createTempSync('photo_pending_');
      final file = File('${dir.path}/photo.jpg')..writeAsBytesSync([1, 2, 3]);
      final now = DateTime(2026);
      await db.piecesDao.insertPiece(
        PiecesCompanion.insert(id: 'piece', createdAt: now, updatedAt: now),
      );
      await db.photosDao.insertPhoto(
        PhotosCompanion.insert(
          id: 'photo',
          pieceId: 'piece',
          localPath: file.path,
          dateTaken: now,
          createdAt: now,
        ),
      );
      final firestore = FakeFirebaseFirestore();
      final service = _Service(db, firestore, MockFirebaseStorage());
      final queue = SyncQueue();
      await service.pushPhoto('user-1', 'photo');
      await queue.enqueue(
        const SyncQueueEntry(
          operation: SyncOperation.pushPhotoFile,
          entityId: 'photo',
        ),
      );
      ProviderContainer makeContainer() => ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (_) => AuthNotifier.withState(
              const AuthState(status: AuthStatus.unauthenticated),
            ),
          ),
          syncServiceProvider.overrideWithValue(service),
          syncQueueProvider.overrideWithValue(SyncQueue()),
        ],
      );
      var container = makeContainer();
      addTearDown(() async {
        container.dispose();
        await db.close();
        dir.deleteSync(recursive: true);
      });
      Future<void> signIn() async {
        container.read(syncStateProvider.notifier);
        final pulled = service.expectPull();
        container.read(authProvider.notifier).state = const AuthState(
          status: AuthStatus.authenticated,
          uid: 'user-1',
        );
        await pulled.timeout(const Duration(seconds: 5));
        await _waitUntil(
          () async =>
              container.read(syncStateProvider).status != SyncStatus.syncing,
        );
      }

      await signIn();
      expect(
        container.read(syncStateProvider).pendingCount,
        1,
        reason: 'an unuploaded photo must prevent the backed-up claim',
      );
      container.dispose();
      container = makeContainer();
      await signIn();
      expect(container.read(syncStateProvider).pendingCount, 1);
      service.failUpload = false;
      await container.read(syncStateProvider.notifier).syncNow();
      expect(container.read(syncStateProvider).pendingCount, 0);
      expect((await db.photosDao.getPhotoById('photo'))!.cloudUrl, isNotNull);
      // Publishing the URL is part of upload completion too.
      await db.photosDao.updatePhoto(
        const PhotosCompanion(id: Value('photo'), cloudUrl: Value(null)),
      );
      await firestore.doc('users/user-1/photos/photo').delete();
      await expectLater(
        service.uploadPhotoFile('user-1', 'photo'),
        throwsException,
      );
      expect(await service.pendingPhotoUploadIds(), {'photo'});
      await service.pushPhoto('user-1', 'photo');

      // The debounced path also counts this file exactly once while queued,
      // and continues counting it after its failed attempt leaves the queue.
      service.failUpload = true;
      await container
          .read(syncQueueProvider)
          .enqueue(
            const SyncQueueEntry(
              operation: SyncOperation.pushPhotoFile,
              entityId: 'photo',
            ),
          );
      final previous = container.read(syncStateProvider).lastSyncedAt;
      container.read(syncStateProvider.notifier).scheduleProcessQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(syncStateProvider).pendingCount, 1);
      await _waitUntil(
        () async => await container.read(syncQueueProvider).pendingCount == 0,
      );
      expect(await container.read(syncQueueProvider).pendingCount, 0);
      expect(container.read(syncStateProvider).pendingCount, 1);
      expect(
        container.read(syncStateProvider).lastSyncedAt,
        previous,
        reason: 'a queue-only drain does not prove a full sync',
      );
      service.failUpload = false;
      await container.read(syncStateProvider.notifier).syncNow();
      expect(container.read(syncStateProvider).pendingCount, 0);

      // Deleted photos must not leave phantom pending work.
      await db.photosDao.updatePhoto(
        const PhotosCompanion(id: Value('photo'), cloudUrl: Value(null)),
      );
      await db.photosDao.deletePhoto('photo');
      await container.read(syncStateProvider.notifier).syncNow();
      expect(container.read(syncStateProvider).pendingCount, 0);
    });
  }

  group('a photo upload in flight', () {
    late AppDatabase db;
    late Directory dir;
    late FakeFirebaseFirestore firestore;
    late _CountingStorage storage;
    late _Service service;
    late ProviderContainer container;

    setUp(() async {
      // Synced before, so signing in takes the incremental path and retries
      // the pending photo from its row.
      SharedPreferences.setMockInitialValues({
        '${SyncService.lastPulledAtPrefix}user-1': DateTime(
          2020,
        ).millisecondsSinceEpoch,
      });
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dir = Directory.systemTemp.createTempSync('photo_once_');
      final file = File('${dir.path}/photo.jpg')..writeAsBytesSync([1, 2, 3]);
      final now = DateTime(2026);
      await db.piecesDao.insertPiece(
        PiecesCompanion.insert(id: 'piece', createdAt: now, updatedAt: now),
      );
      await db.photosDao.insertPhoto(
        PhotosCompanion.insert(
          id: 'photo',
          pieceId: 'piece',
          localPath: file.path,
          dateTaken: now,
          createdAt: now,
        ),
      );
      firestore = FakeFirebaseFirestore();
      storage = _CountingStorage();
      service = _Service(db, firestore, storage)
        ..failUpload = false
        ..uploadGate = Completer<void>();
      await service.pushPhoto('user-1', 'photo');
      container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (_) => AuthNotifier.withState(
              const AuthState(status: AuthStatus.unauthenticated),
            ),
          ),
          syncServiceProvider.overrideWithValue(service),
          syncQueueProvider.overrideWithValue(SyncQueue()),
        ],
      );
      container.read(syncStateProvider.notifier);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
      dir.deleteSync(recursive: true);
    });

    Future<void> signInWithUploadHeld() async {
      container.read(authProvider.notifier).state = const AuthState(
        status: AuthStatus.authenticated,
        uid: 'user-1',
      );
      await _waitUntil(() async => service.uploadsHeld == 1);
    }

    Future<void> settled() => _waitUntil(() async {
      final state = container.read(syncStateProvider);
      return state.status == SyncStatus.idle &&
          state.pendingCount == 0 &&
          state.lastSyncedAt != null;
    });

    Future<void> expectUploadedOnce() async {
      expect(storage.uploads, 1, reason: 'the photo file reaches Storage once');
      expect(
        storage.urlLookups,
        1,
        reason: 'and its URL is published on the photo document once',
      );
      final url = (await db.photosDao.getPhotoById('photo'))!.cloudUrl;
      expect(url, isNotNull);
      final remote = await firestore.doc('users/user-1/photos/photo').get();
      expect(remote.data()!['cloudUrl'], url);
    }

    test('a forced sync does not upload a photo whose retry is still '
        'uploading', () async {
      await signInWithUploadHeld();

      final forced = container
          .read(syncStateProvider.notifier)
          .syncNow(forceFullSync: true);
      await _waitUntil(() async => (await SyncQueue().getAll()).isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      service.uploadGate!.complete();
      await forced;
      await settled();

      await expectUploadedOnce();
    });

    test('a forced sync does not upload a photo delivered while it reads its '
        'snapshot', () async {
      await SyncQueue().enqueue(
        const SyncQueueEntry(
          operation: SyncOperation.pushPhotoFile,
          entityId: 'photo',
        ),
      );
      await signInWithUploadHeld();

      // The snapshot reads the photo as not yet uploaded; the held upload
      // then lands and retires its queue entry before the snapshot is staged.
      service.afterSnapshotRead = () async {
        service.afterSnapshotRead = null;
        service.uploadGate!.complete();
        await _waitUntil(() async => (await SyncQueue().getAll()).isEmpty);
      };
      await container
          .read(syncStateProvider.notifier)
          .syncNow(forceFullSync: true);
      await settled();

      await expectUploadedOnce();
    });

    test('a piece deleted during the upload keeps its file out of Storage '
        'and its URL unpublished', () async {
      service.uploadGate = null;
      storage.putFileGate = Completer<void>();
      container.read(authProvider.notifier).state = const AuthState(
        status: AuthStatus.authenticated,
        uid: 'user-1',
      );
      await _waitUntil(() async => storage.putFilesHeld == 1);

      // The piece is deleted while its photo's file is still uploading, and
      // that deletion reaches the cloud before the file does.
      await db.photosDao.deletePhotosForPiece('piece');
      await db.piecesDao.deletePiece('piece');
      await container.read(syncTriggerProvider).afterPieceDeletion('piece', [
        'photo',
      ]);
      await _waitUntil(() async => (await SyncQueue().getAll()).isEmpty);
      final photoDoc = firestore.doc('users/user-1/photos/photo');
      expect((await photoDoc.get()).data()!['deletedAt'], isNotNull);

      storage.putFileGate!.complete();
      await settled();

      expect(
        storage.storedFilesMap.keys,
        isNot(contains('users/user-1/photos/piece/photo.jpg')),
        reason: "the deleted piece's photo must not stay in Storage",
      );
      expect(
        (await photoDoc.get()).data()!['cloudUrl'],
        isNull,
        reason: 'a deleted photo gets no URL published',
      );
    });
  });
}
