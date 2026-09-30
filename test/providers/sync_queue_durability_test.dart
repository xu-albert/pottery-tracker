import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/providers/sync_provider.dart';
import 'package:pottery_tracker/services/image_service.dart';
import 'package:pottery_tracker/services/piece_writer.dart';
import 'package:pottery_tracker/services/sync_queue.dart';
import 'package:pottery_tracker/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SyncService extends Mock implements SyncService {}

class _Images extends Mock implements ImageService {}

/// The test fires the debounce explicitly, independently of network gates.
class _Clock extends SyncClock {
  _Timer? timer;

  /// The instant a completed sync stamps itself with, so a test can wait for
  /// the exact `lastSyncedAt` it publishes rather than for a count that only
  /// appears once the behaviour under test is right.
  DateTime instant = DateTime(2026);

  @override
  DateTime now() => instant;

  @override
  Timer runAfter(Duration delay, void Function() callback) {
    expect(delay, debounceDelay);
    return timer = _Timer(callback);
  }

  @override
  Future<void> sleep(Duration duration) async {}

  void fire() {
    expect(timer?.isActive, isTrue, reason: 'a queue drain must be scheduled');
    timer!.fire();
  }
}

class _Timer implements Timer {
  final void Function() callback;
  _Timer(this.callback);

  @override
  bool isActive = true;

  @override
  int tick = 0;

  @override
  void cancel() => isActive = false;

  void fire() {
    if (!isActive) return;
    isActive = false;
    tick++;
    callback();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late SyncQueue queue;
  late _SyncService service;
  late _Clock clock;
  late ProviderContainer container;
  late PieceWriter writer;
  late List<String?> pushedTitles;

  Future<void> waitForState(bool Function(SyncState) matches) {
    if (matches(container.read(syncStateProvider))) return Future.value();
    final done = Completer<void>();
    final sub = container.listen(syncStateProvider, (_, next) {
      if (matches(next) && !done.isCompleted) done.complete();
    });
    return done.future.whenComplete(sub.close);
  }

  Future<void> settle() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> waitForQueueCount(int count) async {
    for (var i = 0; i < 100; i++) {
      if (await queue.pendingCount == count) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('queue did not reach $count entries');
  }

  void signIn() {
    container.read(authProvider.notifier).state = const AuthState(
      status: AuthStatus.authenticated,
      uid: 'user-1',
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    queue = SyncQueue();
    service = _SyncService();
    clock = _Clock();
    pushedTitles = [];
    when(
      () => service.pendingPhotoUploadIds(),
    ).thenAnswer((_) async => <String>{});
    when(() => service.getLocalDataOwner()).thenAnswer((_) async => null);
    when(() => service.setLocalDataOwner(any())).thenAnswer((_) async {});
    when(() => service.getDeviceContested()).thenAnswer((_) async => false);
    when(
      () => service.getLastPulledAt(any()),
    ).thenAnswer((_) async => DateTime(2026));
    when(() => service.checkServerReachability(any())).thenAnswer((_) async {});
    when(() => service.fullUploadEntries(any())).thenAnswer((_) async => []);
    when(() => service.pullAll(any())).thenAnswer((_) async {});
    when(() => service.pullChangedSince(any(), any())).thenAnswer((_) async {});
    when(() => service.pushPiece(any(), any())).thenAnswer((call) async {
      final piece = await db.piecesDao.getPieceById(
        call.positionalArguments[1] as String,
      );
      if (piece != null) pushedTitles.add(piece.title);
    });
    when(() => service.pushPhoto(any(), any())).thenAnswer((_) async {});
    when(() => service.uploadPhotoFile(any(), any())).thenAnswer((_) async {});
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (_) => AuthNotifier.withState(
            const AuthState(status: AuthStatus.unauthenticated),
          ),
        ),
        syncQueueProvider.overrideWithValue(queue),
        syncServiceProvider.overrideWithValue(service),
        syncStateProvider.overrideWith(
          (ref) => SyncNotifier(ref, queue, service, clock: clock),
        ),
      ],
    );
    container.read(syncStateProvider.notifier);
    writer = PieceWriter(
      piecesDao: db.piecesDao,
      photosDao: db.photosDao,
      imageService: _Images(),
      syncTrigger: container.read(syncTriggerProvider),
    );
    await db.piecesDao.insertPiece(
      PiecesCompanion.insert(
        id: 'p1',
        title: const Value('original'),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  for (final startDrain in [false, true]) {
    test(
      'offline edit is pending ${startDrain ? 'during upload' : 'before debounce'}',
      () async {
        signIn();
        await waitForState((s) => s.lastSyncedAt == clock.instant);
        final lastSynced = container.read(syncStateProvider).lastSyncedAt;
        final entered = Completer<void>();
        final release = Completer<void>();
        when(() => service.pushPiece(any(), any())).thenAnswer((_) async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
        });

        await writer.updateFields('p1', title: 'offline edit');
        // Let the enqueue notification settle without advancing the debounce.
        await Future<void>.delayed(Duration.zero);
        if (startDrain) {
          clock.fire();
          await entered.future;
        }
        expect(await SyncQueue().pendingCount, 1);
        expect(
          container.read(syncStateProvider).pendingCount,
          1,
          reason: 'Settings must not claim backed up while this edit is unsent',
        );
        expect(container.read(syncStateProvider).lastSyncedAt, lastSynced);

        final drained = waitForState((s) => s.pendingCount == 0);
        release.complete();
        if (!startDrain) clock.fire();
        await drained;
        expect(await queue.pendingCount, 0);
      },
    );
  }

  for (final fullSync in [false, true]) {
    test('${fullSync ? 'first' : 'incremental'} sign-in sync preserves '
        'an edit during pull and repays its expired debounce', () async {
      if (fullSync) {
        when(
          () => service.getLastPulledAt(any()),
        ).thenAnswer((_) async => null);
      }
      final entered = Completer<void>();
      final release = Completer<void>();
      Future<void> stall() async {
        entered.complete();
        await release.future;
      }

      if (fullSync) {
        when(() => service.pullAll(any())).thenAnswer((_) => stall());
      } else {
        when(
          () => service.pullChangedSince(any(), any()),
        ).thenAnswer((_) => stall());
      }
      await writer.updateFields('p1', title: 'before sync');
      signIn();
      await entered.future;
      expect(
        await queue.pendingCount,
        0,
        reason: 'only the original queue snapshot has been drained',
      );

      await writer.updateFields('p1', title: 'edited during sync');
      clock.fire();
      await Future<void>.delayed(Duration.zero);
      expect(await queue.pendingCount, 1);
      final finished = waitForState((s) => s.status == SyncStatus.idle);
      release.complete();
      await finished;

      expect(
        (await SyncQueue().getAll()).single.entityId,
        'p1',
        reason: 'the unacknowledged edit must survive in persisted storage',
      );
      expect(container.read(syncStateProvider).pendingCount, 1);
      final drained = waitForState((s) => s.pendingCount == 0);
      clock.fire();
      await drained;
      expect(
        pushedTitles,
        ['before sync', 'edited during sync'],
        reason: 'both full and incremental sync drain the durable queue',
      );
      expect(await queue.pendingCount, 0);
      expect(clock.timer!.isActive, isFalse);
    });
  }

  for (final fullSync in [false, true]) {
    test('${fullSync ? 'first' : 'incremental'} sign-in sync retries a photo '
        'upload without spinning or holding back a later edit', () async {
      if (fullSync) {
        when(
          () => service.getLastPulledAt(any()),
        ).thenAnswer((_) async => null);
      }
      var pendingPhotos = {'photo-1'};
      when(
        () => service.pendingPhotoUploadIds(),
      ).thenAnswer((_) async => {...pendingPhotos});
      final entered = Completer<void>();
      final release = Completer<void>();
      when(() => service.uploadPhotoFile('user-1', 'photo-1')).thenAnswer((
        _,
      ) async {
        entered.complete();
        await release.future;
        pendingPhotos = {};
      });

      signIn();
      await entered.future;
      await settle();
      expect(
        container.read(syncStateProvider).status,
        SyncStatus.idle,
        reason: 'a Storage retry awaiting the server must not spin the tile',
      );
      expect(container.read(syncStateProvider).pendingCount, 1);
      verifyNever(() => service.pullAll(any()));
      verifyNever(() => service.pullChangedSince(any(), any()));

      await writer.updateFields('p1', title: 'edited during retry');
      clock.fire();
      await waitForQueueCount(0);
      expect(
        pushedTitles,
        ['edited during retry'],
        reason: 'the edit is delivered while the upload is still in the air',
      );

      final synced = waitForState(
        (s) => s.status == SyncStatus.idle && s.lastSyncedAt != null,
      );
      release.complete();
      await synced;
      expect(container.read(syncStateProvider).pendingCount, 0);
      verify(() => service.uploadPhotoFile('user-1', 'photo-1')).called(1);
    });
  }

  test(
    'first sign-in drains its queue snapshot through ordinary operations',
    () async {
      when(() => service.getLastPulledAt(any())).thenAnswer((_) async => null);
      for (var i = 0; i < 12; i++) {
        await queue.enqueue(
          SyncQueueEntry(
            operation: SyncOperation.pushPiece,
            entityId: 'piece-$i',
          ),
        );
        await queue.enqueue(
          SyncQueueEntry(
            operation: SyncOperation.pushPhoto,
            entityId: 'photo-$i',
          ),
        );
        await queue.enqueue(
          SyncQueueEntry(
            operation: SyncOperation.pushPhotoFile,
            entityId: 'photo-$i',
          ),
        );
      }

      expect(await queue.pendingCount, 36);
      signIn();
      await waitForState(
        (s) => s.status == SyncStatus.idle && s.lastSyncedAt != null,
      );

      expect(await queue.pendingCount, 0);
      expect(container.read(syncStateProvider).pendingCount, 0);
      verify(() => service.fullUploadEntries('user-1')).called(1);
      verify(() => service.uploadPhotoFile('user-1', any())).called(12);

      when(
        () => service.getLastPulledAt('user-1'),
      ).thenAnswer((_) async => DateTime(2026));
      final lastSynced = container.read(syncStateProvider).lastSyncedAt;
      await writer.updateFields('p1', title: 'one later edit');
      clock.instant = DateTime(2026, 6);
      clock.fire();
      await waitForQueueCount(0);

      expect(pushedTitles, ['one later edit']);
      expect(container.read(syncStateProvider).lastSyncedAt, lastSynced);
      verifyNever(() => service.uploadPhotoFile(any(), any()));
    },
  );

  test('first sign-in tombstones a queued deletion before it pulls', () async {
    when(() => service.getLastPulledAt(any())).thenAnswer((_) async => null);
    final calls = <String>[];
    when(() => service.fullUploadEntries('user-1')).thenAnswer((_) async {
      calls.add('fullUploadEntries');
      return [];
    });
    when(() => service.pushPieceDeletion('user-1', 'gone')).thenAnswer((
      _,
    ) async {
      calls.add('pushPieceDeletion');
    });
    when(
      () => service.pushDeletion('user-1', 'photos', 'gone-photo'),
    ).thenAnswer((_) async {
      calls.add('pushDeletion');
    });
    when(() => service.pullAll(any())).thenAnswer((_) async {
      calls.add('pullAll');
    });
    await queue.enqueue(
      const SyncQueueEntry(
        operation: SyncOperation.deletePhoto,
        entityId: 'gone-photo',
      ),
    );
    await queue.enqueue(
      const SyncQueueEntry(
        operation: SyncOperation.deletePiece,
        entityId: 'gone',
      ),
    );

    signIn();
    await waitForState(
      (s) => s.status == SyncStatus.idle && s.lastSyncedAt != null,
    );

    expect(calls, [
      'fullUploadEntries',
      'pushDeletion',
      'pushPieceDeletion',
      'pullAll',
    ], reason: 'full snapshots and tombstones use the same queue drain');
    expect(await queue.pendingCount, 0);
  });

  test('a deletion whose tombstone fails stays queued', () async {
    when(() => service.getLastPulledAt(any())).thenAnswer((_) async => null);
    var pulled = false;
    when(() => service.pullAll(any())).thenAnswer((_) async {
      pulled = true;
    });
    when(
      () => service.pushPieceDeletion('user-1', 'gone'),
    ).thenThrow(Exception('offline'));
    await queue.enqueue(
      const SyncQueueEntry(
        operation: SyncOperation.deletePiece,
        entityId: 'gone',
      ),
    );

    signIn();
    await waitForState(
      (s) => pulled && s.status == SyncStatus.error && s.pendingCount == 1,
    );

    expect(
      (await SyncQueue().getAll()).single.operation,
      SyncOperation.deletePiece,
      reason: 'an unsent tombstone must survive in persisted storage',
    );
    expect(container.read(syncStateProvider).pendingCount, 1);
    expect(
      container.read(syncStateProvider).lastSyncedAt,
      isNull,
      reason: 'a successful pull cannot claim an unsent tombstone',
    );
  });

  test('a later drain sends an unrelated edit past a held push', () async {
    signIn();
    await waitForState(
      (s) => s.status == SyncStatus.idle && s.lastSyncedAt != null,
    );
    final entered = Completer<void>();
    final release = Completer<void>();
    when(() => service.pushPiece('user-1', 'p1')).thenAnswer((_) async {
      pushedTitles.add((await db.piecesDao.getPieceById('p1'))!.title);
      entered.complete();
      await release.future;
    });
    await db.piecesDao.insertPiece(
      PiecesCompanion.insert(
        id: 'p2',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    await writer.updateFields('p1', title: 'first drain');
    clock.fire();
    await entered.future;
    await writer.updateFields('p2', title: 'second drain');
    clock.fire();
    await settle();
    expect(pushedTitles, [
      'first drain',
      'second drain',
    ], reason: 'an unrelated entity does not wait behind a held push');
    expect(clock.timer!.isActive, isFalse);

    final drained = waitForState((s) => s.pendingCount == 0);
    release.complete();
    await drained;
    expect(
      pushedTitles,
      ['first drain', 'second drain'],
      reason: 'the second drain attached to the held push, never resent it',
    );
    expect(await queue.pendingCount, 0);
  });

  test(
    'repeated taps during a first sync never send a held write twice',
    () async {
      DateTime? pulledAt;
      when(
        () => service.getLastPulledAt(any()),
      ).thenAnswer((_) async => pulledAt);
      when(() => service.pullAll(any())).thenAnswer((_) async {
        pulledAt = DateTime(2026);
      });
      var pendingPhotos = {'photo-1'};
      when(
        () => service.pendingPhotoUploadIds(),
      ).thenAnswer((_) async => {...pendingPhotos});
      when(() => service.fullUploadEntries('user-1')).thenAnswer(
        (_) async => const [
          SyncQueueEntry(
            operation: SyncOperation.pushPieceGlazes,
            entityId: 'p1',
          ),
          SyncQueueEntry(
            operation: SyncOperation.pushPhotoFile,
            entityId: 'photo-1',
          ),
        ],
      );
      final release = Completer<void>();
      var junctionWrites = 0;
      var uploads = 0;
      when(() => service.pushPieceGlazes('user-1', 'p1')).thenAnswer((_) async {
        junctionWrites++;
        await release.future;
      });
      when(() => service.uploadPhotoFile('user-1', 'photo-1')).thenAnswer((
        _,
      ) async {
        uploads++;
        await release.future;
        pendingPhotos = {};
      });

      signIn();
      for (var i = 0; i < 100 && (junctionWrites == 0 || uploads == 0); i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(junctionWrites, 1);
      expect(uploads, 1);

      // Sync Now while the first sync's writes are in the air, then two forced
      // taps — the second stands down behind the first — and Sync Now again.
      final notifier = container.read(syncStateProvider.notifier);
      final taps = [notifier.syncNow()];
      await settle();
      taps
        ..add(notifier.syncNow(forceFullSync: true))
        ..add(notifier.syncNow(forceFullSync: true));
      await settle();
      taps.add(notifier.syncNow());
      await settle();

      expect(junctionWrites, 1, reason: 'each tap attaches to the held write');
      expect(uploads, 1, reason: 'no tap uploads a photo still uploading');
      verify(() => service.fullUploadEntries('user-1')).called(1);

      release.complete();
      await Future.wait(taps);
      await waitForState(
        (s) =>
            s.status == SyncStatus.idle &&
            s.lastSyncedAt != null &&
            s.pendingCount == 0,
      );

      expect(
        junctionWrites,
        1,
        reason: 'nothing sends the delivered junction batch again',
      );
      expect(uploads, 1, reason: 'nothing uploads the delivered photo again');
      verifyNever(() => service.fullUploadEntries(any()));
      expect(await queue.pendingCount, 0);
    },
  );

  test(
    'a delivered entry is retired while a sibling lane is still held',
    () async {
      signIn();
      await waitForState(
        (s) => s.status == SyncStatus.idle && s.lastSyncedAt != null,
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      when(() => service.pushPiece('user-1', 'p1')).thenAnswer((_) async {
        entered.complete();
        await release.future;
      });
      await db.piecesDao.insertPiece(
        PiecesCompanion.insert(
          id: 'p2',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      await writer.updateFields('p1', title: 'held');
      await writer.updateFields('p2', title: 'delivered');
      clock.fire();
      await entered.future;

      await waitForQueueCount(1);
      expect(
        (await SyncQueue().getAll()).single.entityId,
        'p1',
        reason: 'p2 reached the cloud, so a relaunch must not send it again',
      );
      await waitForState((s) => s.pendingCount == 1);

      final drained = waitForState((s) => s.pendingCount == 0);
      release.complete();
      await drained;
      expect(await queue.pendingCount, 0);
    },
  );

  test('an edit during the in-flight push of the same entity is not '
      'acknowledged by that push', () async {
    signIn();
    await waitForState(
      (s) => s.status == SyncStatus.idle && s.lastSyncedAt != null,
    );
    final entered = Completer<void>();
    final release = Completer<void>();
    final pushReturned = Completer<void>();
    when(() => service.pushPiece('user-1', 'p1')).thenAnswer((_) async {
      pushedTitles.add((await db.piecesDao.getPieceById('p1'))!.title);
      if (release.isCompleted) return;
      entered.complete();
      await release.future;
      pushReturned.complete();
    });

    await writer.updateFields('p1', title: 'read by the push');
    clock.fire();
    await entered.future;

    // Merges into the entry the drain is holding — the two are `==`, both
    // carry null changedFields, and nothing about the row distinguishes them.
    await writer.updateFields('p1', title: 'edited mid-push');
    expect(await queue.pendingCount, 1);

    release.complete();
    await pushReturned.future;
    await settle();

    expect(
      (await SyncQueue().getAll()).single.entityId,
      'p1',
      reason: 'the revision the push never sent must survive on disk',
    );
    expect(
      container.read(syncStateProvider).pendingCount,
      1,
      reason: 'the mid-push edit was never uploaded, so it is still pending',
    );

    final drained = waitForState((s) => s.pendingCount == 0);
    clock.fire();
    await drained;
    expect(pushedTitles, ['read by the push', 'edited mid-push']);
    expect(await queue.pendingCount, 0);
    expect(clock.timer!.isActive, isFalse);
  });

  test(
    'exhausted pushes survive sync completion without a hot retry loop',
    () async {
      var attempts = 0;
      when(() => service.pushPiece(any(), any())).thenAnswer((_) {
        attempts++;
        throw Exception('offline');
      });
      await writer.updateFields('p1', title: 'keep me');
      // No outstanding debounce: only syncNow owns this attempt.
      clock.timer!.cancel();
      signIn();
      await waitForState(
        (s) =>
            attempts == 3 &&
            s.status == SyncStatus.error &&
            s.pendingCount == 1,
      );
      expect(await queue.pendingCount, 1);
      expect(container.read(syncStateProvider).pendingCount, 1);
      verify(() => service.pushPiece('user-1', 'p1')).called(3);
      expect(clock.timer!.isActive, isFalse);
    },
  );
}
