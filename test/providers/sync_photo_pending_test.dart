import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
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

  @override
  Future<void> uploadPhotoFile(String uid, String photoId) async {
    if (failUpload) throw Exception('storage unavailable');
    await super.uploadPhotoFile(uid, photoId);
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
        final done = Completer<void>();
        final sub = container.listen(syncStateProvider, (_, next) {
          if (next.lastSyncedAt != null && !done.isCompleted) done.complete();
        });
        container.read(authProvider.notifier).state = const AuthState(
          status: AuthStatus.authenticated,
          uid: 'user-1',
        );
        await done.future.timeout(const Duration(seconds: 5));
        sub.close();
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
      final drained = Completer<void>();
      final sub = container.listen(syncStateProvider, (_, next) {
        if (next.lastSyncedAt != previous && !drained.isCompleted) {
          drained.complete();
        }
      });
      container.read(syncStateProvider.notifier).scheduleProcessQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(syncStateProvider).pendingCount, 1);
      await drained.future.timeout(const Duration(seconds: 5));
      sub.close();
      expect(await container.read(syncQueueProvider).pendingCount, 0);
      expect(container.read(syncStateProvider).pendingCount, 1);
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
}
