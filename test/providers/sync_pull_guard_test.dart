import 'dart:async';

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
import 'package:pottery_tracker/services/sync_queue.dart';
import 'package:pottery_tracker/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A sync pulls even when its pushes failed with the server reachable —
/// permission denied, App Check, an exhausted write quota. That pull must not
/// revert the edit the failed push still owes the cloud, or the retry would
/// send the reverted row and report it backed up (sync audit H2).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    final container = ProviderContainer(
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
}

class _RefusedPushService extends SyncService {
  _RefusedPushService(super.db, super.firestore, super.storage, {super.queue});

  int pushAttempts = 0;
  int pulls = 0;

  @override
  Future<void> pushPiece(String uid, String pieceId) async {
    pushAttempts++;
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
  }

  @override
  Future<void> pullChangedSince(String uid, DateTime since) async {
    pulls++;
    await super.pullChangedSince(uid, since);
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
