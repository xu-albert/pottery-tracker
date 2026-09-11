import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/providers/sync_provider.dart';
import 'package:pottery_tracker/services/sync_queue.dart';
import 'package:pottery_tracker/services/sync_service.dart';

// ── Mocks ──────────────────────────────────────────────

class MockSyncService extends Mock implements SyncService {}

class MockSyncQueue extends Mock implements SyncQueue {}

// ── Helpers ────────────────────────────────────────────

const _signedIn = AuthState(
  status: AuthStatus.authenticated,
  uid: 'user-1',
  displayName: 'Test User',
);

const _signedOut = AuthState(status: AuthStatus.unauthenticated);

/// Creates a [SyncNotifier] wired to the given auth state, with mock
/// SyncService and SyncQueue. Returns the notifier and the container so
/// callers can read state and manipulate the auth provider.
({
  SyncNotifier notifier,
  ProviderContainer container,
  MockSyncService syncService,
  MockSyncQueue queue,
})
_setup({AuthState auth = _signedOut, SyncClock? clock}) {
  final syncService = MockSyncService();
  final queue = MockSyncQueue();

  // Default stubs so any test can call syncNow without wiring every method.
  when(() => queue.pendingCount).thenAnswer((_) async => 0);
  when(() => queue.getAll()).thenAnswer((_) async => []);
  when(() => queue.clear()).thenAnswer((_) async {});
  when(() => queue.remove(any())).thenAnswer((_) async {});
  // Nothing edits an entity mid-push in these tests, so every entry keeps the
  // revision the drain captured. The concurrent-edit case is pinned against a
  // real queue in sync_queue_durability_test.dart.
  when(() => queue.revisionOf(any())).thenReturn(0);

  when(() => syncService.getLastPulledAt(any())).thenAnswer((_) async => null);
  when(() => syncService.pushAllLocal(any())).thenAnswer((_) async {});
  when(() => syncService.pullAll(any())).thenAnswer((_) async {});
  when(
    () => syncService.pullChangedSince(any(), any()),
  ).thenAnswer((_) async {});
  when(() => syncService.retryMissingUploads(any())).thenAnswer((_) async {});
  when(() => syncService.deleteCloudData(any())).thenAnswer((_) async {});
  when(() => syncService.deleteLocalData()).thenAnswer((_) async {});
  // Unowned by default: the device belongs to whoever signs in first.
  when(() => syncService.getLocalDataOwner()).thenAnswer((_) async => null);
  when(() => syncService.setLocalDataOwner(any())).thenAnswer((_) async {});
  // The refusal marker is device-ownership state like the stamp above: the
  // notifier reads it on every claim, so a mock has to answer for it.
  when(() => syncService.getDeviceContested()).thenAnswer((_) async => false);

  // Push / delete stubs
  when(() => syncService.pushPiece(any(), any())).thenAnswer((_) async {});
  when(() => syncService.pushPhoto(any(), any())).thenAnswer((_) async {});
  when(
    () => syncService.uploadPhotoFile(any(), any()),
  ).thenAnswer((_) async {});
  when(() => syncService.pushClay(any(), any())).thenAnswer((_) async {});
  when(() => syncService.pushGlaze(any(), any())).thenAnswer((_) async {});
  when(() => syncService.pushTag(any(), any())).thenAnswer((_) async {});
  when(
    () => syncService.pushPieceGlazes(any(), any()),
  ).thenAnswer((_) async {});
  when(() => syncService.pushPieceTags(any(), any())).thenAnswer((_) async {});
  when(
    () => syncService.pushPieceDeletion(any(), any()),
  ).thenAnswer((_) async {});
  when(
    () => syncService.pushDeletion(any(), any(), any()),
  ).thenAnswer((_) async {});

  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith((_) => AuthNotifier.withState(auth)),
      syncQueueProvider.overrideWithValue(queue),
      syncServiceProvider.overrideWithValue(syncService),
      if (clock != null)
        syncStateProvider.overrideWith(
          (ref) => SyncNotifier(ref, queue, syncService, clock: clock),
        ),
    ],
  );

  // Reading syncStateProvider triggers the SyncNotifier constructor.
  final notifier = container.read(syncStateProvider.notifier);

  return (
    notifier: notifier,
    container: container,
    syncService: syncService,
    queue: queue,
  );
}

void main() {
  group('SyncState.copyWith', () {
    const failed = SyncState(
      status: SyncStatus.error,
      errorMessage: 'stale failure',
    );

    test('clears the error message, which describes one transition', () {
      expect(
        failed.copyWith(pendingCount: 3).errorMessage,
        isNull,
        reason:
            'carrying it forward would caption a healthy state with a failure '
            'that is already over',
      );
      expect(failed.copyWith(errorMessage: 'boom').errorMessage, 'boom');
    });

    test('carries the fields it was not asked to change', () {
      final next = failed.copyWith(status: SyncStatus.idle);
      expect(next.status, SyncStatus.idle);
      expect(next.pendingCount, failed.pendingCount);
    });
  });

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(
      const SyncQueueEntry(operation: SyncOperation.pushPiece, entityId: ''),
    );
  });

  // A pending-wipe flag now blocks every push, so it must not leak from one
  // test into the next.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SyncNotifier auth state transitions', () {
    test('status is disabled when user is signed out', () {
      final s = _setup(auth: _signedOut);
      addTearDown(s.container.dispose);

      expect(s.container.read(syncStateProvider).status, SyncStatus.disabled);
    });

    test('status becomes idle when user signs in', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);

      // _onAuthChanged is async — let microtasks settle
      await Future<void>.delayed(Duration.zero);

      expect(s.container.read(syncStateProvider).status, SyncStatus.idle);
    });

    test('status goes back to disabled when user signs out', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      // Sign out
      s.container.read(authProvider.notifier).state = _signedOut;
      await Future<void>.delayed(Duration.zero);

      expect(s.container.read(syncStateProvider).status, SyncStatus.disabled);
    });
  });

  group('syncNow', () {
    test('sets status to disabled and returns when not signed in', () async {
      final s = _setup(auth: _signedOut);
      addTearDown(s.container.dispose);

      await s.notifier.syncNow();

      expect(s.container.read(syncStateProvider).status, SyncStatus.disabled);
      verifyNever(() => s.syncService.pushAllLocal(any()));
      verifyNever(() => s.syncService.pullAll(any()));
    });

    test(
      'first sync: pushAllLocal then pullAll when no lastPulledAt',
      () async {
        final s = _setup(auth: _signedIn);
        addTearDown(s.container.dispose);
        await Future<void>.delayed(Duration.zero);

        when(
          () => s.syncService.getLastPulledAt('user-1'),
        ).thenAnswer((_) async => null);

        await s.notifier.syncNow();

        verifyInOrder([
          () => s.syncService.pushAllLocal('user-1'),
          () => s.syncService.pullAll('user-1'),
          () => s.syncService.retryMissingUploads('user-1'),
        ]);

        final state = s.container.read(syncStateProvider);
        expect(state.status, SyncStatus.idle);
        expect(state.pendingCount, 0);
        expect(state.lastSyncedAt, isNotNull);
      },
    );

    test('incremental sync: processes queue then pullChangedSince', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      final lastPulled = DateTime(2025, 1, 1);
      when(
        () => s.syncService.getLastPulledAt('user-1'),
      ).thenAnswer((_) async => lastPulled);

      await s.notifier.syncNow();

      verify(
        () => s.syncService.pullChangedSince('user-1', lastPulled),
      ).called(1);
      // pushAllLocal was called once by the constructor's auto-sync (before
      // we stubbed getLastPulledAt to return a date), but not by this syncNow.
      verify(() => s.syncService.pushAllLocal(any())).called(1);
    });

    test('forceFullSync ignores lastPulledAt and does full sync', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      // Even though lastPulledAt would return a date, forceFullSync skips it
      when(
        () => s.syncService.getLastPulledAt('user-1'),
      ).thenAnswer((_) async => DateTime(2025, 1, 1));

      await s.notifier.syncNow(forceFullSync: true);

      // called(2): once from the constructor's auto-sync, once from this test
      verify(() => s.syncService.pushAllLocal('user-1')).called(2);
      verify(() => s.syncService.pullAll('user-1')).called(2);
      verifyNever(() => s.syncService.pullChangedSince(any(), any()));
    });

    test('full sync acknowledges only the entries it pushes', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);
      clearInteractions(s.syncService);
      clearInteractions(s.queue);

      const entry = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
      );
      final queued = <SyncQueueEntry>[entry];
      when(() => s.queue.getAll()).thenAnswer((_) async => [...queued]);
      when(() => s.queue.remove(entry)).thenAnswer((_) async {
        queued.remove(entry);
      });
      when(() => s.queue.revisionOf(entry)).thenReturn(7);
      await s.notifier.syncNow();

      verifyInOrder([
        () => s.queue.getAll(),
        () => s.queue.revisionOf(entry),
        () => s.syncService.pushAllLocal('user-1'),
        () => s.queue.revisionOf(entry),
        () => s.queue.remove(entry),
      ]);
      verifyNever(() => s.syncService.pushPiece(any(), any()));
      verifyNever(() => s.queue.clear());
    });

    test('full sync sends a queued deletion before it pulls', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);
      clearInteractions(s.syncService);
      clearInteractions(s.queue);

      const entry = SyncQueueEntry(
        operation: SyncOperation.deletePiece,
        entityId: 'gone',
      );
      final queued = <SyncQueueEntry>[entry];
      when(() => s.queue.getAll()).thenAnswer((_) async => [...queued]);
      when(() => s.queue.remove(entry)).thenAnswer((_) async {
        queued.remove(entry);
      });
      await s.notifier.syncNow();

      verifyInOrder([
        () => s.syncService.pushAllLocal('user-1'),
        () => s.syncService.pushPieceDeletion('user-1', 'gone'),
        () => s.queue.remove(entry),
        () => s.syncService.pullAll('user-1'),
      ]);
    });

    test('sets error state when sync fails', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      when(
        () => s.syncService.pushAllLocal(any()),
      ).thenThrow(Exception('network down'));

      await s.notifier.syncNow();

      final state = s.container.read(syncStateProvider);
      expect(state.status, SyncStatus.error);
      expect(state.errorMessage, contains('network down'));
    });

    test('a sync that stands down is replayed, not dropped', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      // Track calls AFTER the constructor's auto-sync has completed
      var callCount = 0;
      var running = 0;
      var everOverlapped = false;
      when(() => s.syncService.pushAllLocal(any())).thenAnswer((_) async {
        callCount++;
        running++;
        if (running > 1) everOverlapped = true;
        await Future.delayed(const Duration(milliseconds: 50));
        running--;
      });

      // Fire two syncs concurrently
      final first = s.notifier.syncNow();
      final second = s.notifier.syncNow();
      await Future.wait([first, second]);

      expect(everOverlapped, isFalse, reason: 'syncs must not run together');
      expect(
        callCount,
        2,
        reason:
            'the second stood down for the first, but the debt is owed and '
            'replayed afterwards — dropping it silently loses the pull',
      );
    });
  });

  group('_processQueueInternal retry logic', () {
    test(
      'retries up to 3 times on failure, then keeps entry in queue',
      () async {
        final s = _setup(auth: _signedIn);
        addTearDown(s.container.dispose);
        await Future<void>.delayed(Duration.zero);

        final entry = SyncQueueEntry(
          operation: SyncOperation.pushPiece,
          entityId: 'piece-1',
        );
        when(() => s.queue.getAll()).thenAnswer((_) async => [entry]);

        // Set up lastPulledAt so it goes through incremental path
        when(
          () => s.syncService.getLastPulledAt('user-1'),
        ).thenAnswer((_) async => DateTime(2025, 1, 1));

        // Fail all 3 attempts
        var callCount = 0;
        when(() => s.syncService.pushPiece('user-1', 'piece-1')).thenAnswer((
          _,
        ) {
          callCount++;
          throw Exception('fail attempt $callCount');
        });

        await s.notifier.syncNow();

        expect(callCount, 3);
        // Entry should NOT have been removed since all retries failed
        verifyNever(() => s.queue.remove(entry));
      },
    );

    test('succeeds on second attempt and removes entry', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      final entry = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'piece-1',
      );
      when(() => s.queue.getAll()).thenAnswer((_) async => [entry]);
      when(
        () => s.syncService.getLastPulledAt('user-1'),
      ).thenAnswer((_) async => DateTime(2025, 1, 1));

      var callCount = 0;
      when(() => s.syncService.pushPiece('user-1', 'piece-1')).thenAnswer((_) {
        callCount++;
        if (callCount == 1) throw Exception('transient');
        return Future.value();
      });

      await s.notifier.syncNow();

      expect(callCount, 2);
      verify(() => s.queue.remove(entry)).called(1);
    });

    test('pushPhotoFile is best-effort: no retry, always removed', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      final entry = SyncQueueEntry(
        operation: SyncOperation.pushPhotoFile,
        entityId: 'photo-1',
      );
      when(() => s.queue.getAll()).thenAnswer((_) async => [entry]);
      when(
        () => s.syncService.getLastPulledAt('user-1'),
      ).thenAnswer((_) async => DateTime(2025, 1, 1));

      when(
        () => s.syncService.uploadPhotoFile('user-1', 'photo-1'),
      ).thenThrow(Exception('storage unavailable'));

      await s.notifier.syncNow();

      // Only 1 attempt (no retry for best-effort)
      verify(
        () => s.syncService.uploadPhotoFile('user-1', 'photo-1'),
      ).called(1);
      // Still removed from queue despite failure
      verify(() => s.queue.remove(entry)).called(1);
    });
  });

  group('the debounced drain reports its own outcome', () {
    /// The entry every test in this group leaves in the queue: one edited
    /// piece, the shape the 500ms debounce was built for.
    const entry = SyncQueueEntry(
      operation: SyncOperation.pushPiece,
      entityId: 'piece-1',
    );

    /// Wires the queue to hold [entry] with [pending] entries outstanding.
    void queueHolds(MockSyncQueue queue, {required int pending}) {
      when(() => queue.getAll()).thenAnswer((_) async => [entry]);
      when(() => queue.pendingCount).thenAnswer((_) async => pending);
    }

    test(
      'a recovered drain returns the device to idle and backed up',
      () async {
        final clock = _StubSyncClock();
        final s = _setup(auth: _signedIn, clock: clock);
        addTearDown(s.container.dispose);
        await _settle();

        // Offline: the push fails every attempt, so the drain exhausts its
        // three retries and the entry stays queued.
        queueHolds(s.queue, pending: 1);
        when(
          () => s.syncService.pushPiece('user-1', 'piece-1'),
        ).thenThrow(Exception('network unreachable'));

        s.notifier.scheduleProcessQueue();
        await _settle();

        var state = s.container.read(syncStateProvider);
        expect(state.status, SyncStatus.error);
        expect(state.errorMessage, contains('network unreachable'));

        // The network comes back and the user edits again. This drain pushes
        // everything, so it — not the status the failed one latched — is what
        // the tile is entitled to read.
        when(
          () => s.syncService.pushPiece('user-1', 'piece-1'),
        ).thenAnswer((_) async {});
        when(() => s.queue.pendingCount).thenAnswer((_) async => 0);
        clock.instant = clock.instant.add(const Duration(minutes: 5));

        s.notifier.scheduleProcessQueue();
        await _settle();

        state = s.container.read(syncStateProvider);
        expect(
          state.status,
          SyncStatus.idle,
          reason:
              'everything queued reached the cloud, so reading the latched '
              'error here leaves Settings saying "Sync error" about a run '
              'that is over',
        );
        expect(
          state.errorMessage,
          isNull,
          reason: 'the message captions a failure that no longer stands',
        );
        expect(state.pendingCount, 0);
        expect(
          state.lastSyncedAt,
          clock.instant,
          reason: 'the recovered drain is what backed the device up',
        );
      },
    );

    test('a drain that is still failing keeps the error', () async {
      final clock = _StubSyncClock();
      final s = _setup(auth: _signedIn, clock: clock);
      addTearDown(s.container.dispose);
      await _settle();

      queueHolds(s.queue, pending: 1);
      when(
        () => s.syncService.pushPiece('user-1', 'piece-1'),
      ).thenThrow(Exception('network unreachable'));

      s.notifier.scheduleProcessQueue();
      await _settle();

      final afterFirstFailure = s.container.read(syncStateProvider);
      expect(afterFirstFailure.status, SyncStatus.error);

      // Still offline. The second debounce must not talk itself into idle
      // just because it is a fresh run.
      clock.instant = clock.instant.add(const Duration(minutes: 5));
      s.notifier.scheduleProcessQueue();
      await _settle();

      final state = s.container.read(syncStateProvider);
      expect(state.status, SyncStatus.error);
      expect(state.errorMessage, contains('network unreachable'));
      expect(
        state.lastSyncedAt,
        afterFirstFailure.lastSyncedAt,
        reason: 'nothing was backed up, so the timestamp may not move',
      );
      verifyNever(() => s.queue.remove(entry));
    });

    test('a best-effort photo file failure is not a drain failure', () async {
      final clock = _StubSyncClock();
      final s = _setup(auth: _signedIn, clock: clock);
      addTearDown(s.container.dispose);
      await _settle();

      const photo = SyncQueueEntry(
        operation: SyncOperation.pushPhotoFile,
        entityId: 'photo-1',
      );
      when(() => s.queue.getAll()).thenAnswer((_) async => [photo]);
      when(() => s.queue.pendingCount).thenAnswer((_) async => 0);
      when(
        () => s.syncService.uploadPhotoFile('user-1', 'photo-1'),
      ).thenThrow(Exception('storage unavailable'));
      clock.instant = clock.instant.add(const Duration(minutes: 5));

      s.notifier.scheduleProcessQueue();
      await _settle();

      final state = s.container.read(syncStateProvider);
      expect(
        state.status,
        SyncStatus.idle,
        reason:
            'photo files are best-effort and retryMissingUploads picks them '
            'up on the next full sync, so one must not raise a sync error',
      );
      expect(state.lastSyncedAt, clock.instant);
    });
  });

  group('_processEntry dispatches correctly', () {
    Future<void> testDispatch({
      required SyncOperation operation,
      required String entityId,
      String? extraData,
      required void Function(MockSyncService) verifyCall,
    }) async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      final entry = SyncQueueEntry(
        operation: operation,
        entityId: entityId,
        extraData: extraData,
      );
      when(() => s.queue.getAll()).thenAnswer((_) async => [entry]);
      when(
        () => s.syncService.getLastPulledAt('user-1'),
      ).thenAnswer((_) async => DateTime(2025, 1, 1));

      await s.notifier.syncNow();

      verifyCall(s.syncService);
    }

    test('pushPiece', () async {
      await testDispatch(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
        verifyCall: (svc) =>
            verify(() => svc.pushPiece('user-1', 'p1')).called(1),
      );
    });

    test('pushPhoto', () async {
      await testDispatch(
        operation: SyncOperation.pushPhoto,
        entityId: 'ph1',
        verifyCall: (svc) =>
            verify(() => svc.pushPhoto('user-1', 'ph1')).called(1),
      );
    });

    test('pushPhotoFile', () async {
      await testDispatch(
        operation: SyncOperation.pushPhotoFile,
        entityId: 'ph1',
        verifyCall: (svc) =>
            verify(() => svc.uploadPhotoFile('user-1', 'ph1')).called(1),
      );
    });

    test('pushClay', () async {
      await testDispatch(
        operation: SyncOperation.pushClay,
        entityId: 'c1',
        verifyCall: (svc) =>
            verify(() => svc.pushClay('user-1', 'c1')).called(1),
      );
    });

    test('pushGlaze', () async {
      await testDispatch(
        operation: SyncOperation.pushGlaze,
        entityId: 'g1',
        verifyCall: (svc) =>
            verify(() => svc.pushGlaze('user-1', 'g1')).called(1),
      );
    });

    test('pushTag', () async {
      await testDispatch(
        operation: SyncOperation.pushTag,
        entityId: 't1',
        verifyCall: (svc) =>
            verify(() => svc.pushTag('user-1', 't1')).called(1),
      );
    });

    test('pushPieceGlazes', () async {
      await testDispatch(
        operation: SyncOperation.pushPieceGlazes,
        entityId: 'p1',
        verifyCall: (svc) =>
            verify(() => svc.pushPieceGlazes('user-1', 'p1')).called(1),
      );
    });

    test('pushPieceTags', () async {
      await testDispatch(
        operation: SyncOperation.pushPieceTags,
        entityId: 'p1',
        verifyCall: (svc) =>
            verify(() => svc.pushPieceTags('user-1', 'p1')).called(1),
      );
    });

    test('deletePiece', () async {
      await testDispatch(
        operation: SyncOperation.deletePiece,
        entityId: 'p1',
        verifyCall: (svc) =>
            verify(() => svc.pushPieceDeletion('user-1', 'p1')).called(1),
      );
    });

    test('deletePhoto', () async {
      await testDispatch(
        operation: SyncOperation.deletePhoto,
        entityId: 'ph1',
        verifyCall: (svc) =>
            verify(() => svc.pushDeletion('user-1', 'photos', 'ph1')).called(1),
      );
    });

    test('deleteMaterial uses extraData as collection name', () async {
      await testDispatch(
        operation: SyncOperation.deleteMaterial,
        entityId: 'g1',
        extraData: 'glazes',
        verifyCall: (svc) =>
            verify(() => svc.pushDeletion('user-1', 'glazes', 'g1')).called(1),
      );
    });

    test('deleteMaterial defaults to clays when extraData is null', () async {
      await testDispatch(
        operation: SyncOperation.deleteMaterial,
        entityId: 'c1',
        verifyCall: (svc) =>
            verify(() => svc.pushDeletion('user-1', 'clays', 'c1')).called(1),
      );
    });
  });

  group('scheduleProcessQueue', () {
    test('debounces and fires push after 500ms', () {
      fakeAsync((async) {
        final s = _setup(auth: _signedIn);
        addTearDown(s.container.dispose);
        async.elapse(Duration.zero); // let _onAuthChanged settle
        // The sign-in sync reads the queue itself now, so only what happens
        // from here is the debounce under test.
        clearInteractions(s.queue);

        s.notifier.scheduleProcessQueue();
        s.notifier.scheduleProcessQueue();
        s.notifier.scheduleProcessQueue();

        // Not yet — timer hasn't fired
        verifyNever(() => s.queue.getAll());

        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();

        // Timer fired, _pushQueue called getAll
        verify(() => s.queue.getAll()).called(greaterThanOrEqualTo(1));
      });
    });
  });

  group('deleteAllData', () {
    test('deletes cloud and local data when signed in', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      await s.notifier.deleteAllData();

      verify(() => s.syncService.deleteCloudData('user-1')).called(1);
      verify(() => s.syncService.deleteLocalData()).called(1);
      // Only the explicit deletion may clear the whole queue.
      verify(() => s.queue.clear()).called(1);

      final state = s.container.read(syncStateProvider);
      expect(state.status, SyncStatus.disabled);
      expect(state.pendingCount, 0);
    });

    test('deletes only local data when not signed in', () async {
      final s = _setup(auth: _signedOut);
      addTearDown(s.container.dispose);

      await s.notifier.deleteAllData();

      verifyNever(() => s.syncService.deleteCloudData(any()));
      verify(() => s.syncService.deleteLocalData()).called(1);
    });

    test('sets error state on failure', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      when(
        () => s.syncService.deleteLocalData(),
      ).thenThrow(Exception('permission denied'));

      await s.notifier.deleteAllData();

      final state = s.container.read(syncStateProvider);
      expect(state.status, SyncStatus.error);
      expect(state.errorMessage, contains('permission denied'));
    });
  });

  group('pending wipe blocks pushing', () {
    test('syncNow refuses to push while a wipe is still owed', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      // The resumed wipe keeps failing, so the flag survives every attempt.
      when(
        () => s.syncService.deleteLocalData(),
      ).thenThrow(Exception('disk error'));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SyncNotifier.pendingWipeKey, true);
      clearInteractions(s.syncService);

      await s.notifier.syncNow(forceFullSync: true);

      verifyNever(() => s.syncService.pushAllLocal(any()));
      expect(s.container.read(syncStateProvider).status, SyncStatus.blocked);
      expect(prefs.getBool(SyncNotifier.pendingWipeKey), isTrue);
    });

    test('the debounced queue push refuses while a wipe is owed', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      when(
        () => s.syncService.deleteLocalData(),
      ).thenThrow(Exception('disk error'));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SyncNotifier.pendingWipeKey, true);
      clearInteractions(s.queue);

      s.notifier.scheduleProcessQueue();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      verifyNever(() => s.queue.getAll());
      expect(s.container.read(syncStateProvider).status, SyncStatus.blocked);
    });

    test('a sync attempt never carries the wipe with it', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SyncNotifier.pendingWipeKey, true);
      clearInteractions(s.syncService);

      await s.notifier.syncNow(forceFullSync: true);

      // Refused, and nothing was deleted: a wipe on the push path could land
      // in the middle of a later session, on the current account's own work.
      verifyNever(() => s.syncService.deleteLocalData());
      verifyNever(() => s.syncService.pushAllLocal(any()));
      expect(s.container.read(syncStateProvider).status, SyncStatus.blocked);
      expect(prefs.getBool(SyncNotifier.pendingWipeKey), isTrue);
    });

    test('the debounced queue push never carries the wipe either', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SyncNotifier.pendingWipeKey, true);
      clearInteractions(s.syncService);

      s.notifier.scheduleProcessQueue();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      verifyNever(() => s.syncService.deleteLocalData());
      expect(prefs.getBool(SyncNotifier.pendingWipeKey), isTrue);
    });

    test(
      'the explicit erase clears the wipe and lets pushing resume',
      () async {
        final s = _setup(auth: _signedIn);
        addTearDown(s.container.dispose);
        await Future<void>.delayed(Duration.zero);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(SyncNotifier.pendingWipeKey, true);
        clearInteractions(s.syncService);

        await s.notifier.eraseLocalDataNow();

        verifyInOrder([
          () => s.syncService.deleteLocalData(),
          () => s.syncService.pushAllLocal('user-1'),
        ]);
        expect(s.container.read(syncStateProvider).status, SyncStatus.idle);
        expect(prefs.getBool(SyncNotifier.pendingWipeKey), isNull);
      },
    );
  });

  group('signOutAndWipeLocalData', () {
    test('flags the wipe before the session is dropped', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      bool? flaggedWhenSessionEnded;

      await s.notifier.signOutAndWipeLocalData(() async {
        flaggedWhenSessionEnded = prefs.getBool(SyncNotifier.pendingWipeKey);
      });

      // A process killed while the session is being dropped has to come back
      // owing the wipe; otherwise the next account pushes what survived.
      expect(flaggedWhenSessionEnded, isTrue);
      expect(prefs.getBool(SyncNotifier.pendingWipeKey), isNull);
    });

    test('a wipe that gives up on an in-flight sync stays pending', () {
      fakeAsync((async) {
        final s = _setup(auth: _signedIn);
        addTearDown(s.container.dispose);
        async.elapse(Duration.zero);
        async.flushMicrotasks();

        SharedPreferences? prefs;
        unawaited(SharedPreferences.getInstance().then((p) => prefs = p));
        async.flushMicrotasks();

        // A pull that outlives the wipe's bounded wait, still writing rows
        // behind the delete.
        when(
          () => s.syncService.pullAll(any()),
        ).thenAnswer((_) => Future<void>.delayed(const Duration(minutes: 5)));
        unawaited(s.notifier.syncNow(forceFullSync: true));
        async.elapse(Duration.zero);
        async.flushMicrotasks();

        unawaited(s.notifier.signOutAndWipeLocalData(() async {}));
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();

        verify(() => s.syncService.deleteLocalData()).called(1);
        expect(prefs!.getBool(SyncNotifier.pendingWipeKey), isTrue);

        // SettingsScreen._confirmSignOut drops the auth state immediately
        // afterwards, which wakes the resumed wipe. It must not clear the flag
        // while the abandoned pull is still writing rows behind the delete.
        s.container.read(authProvider.notifier).state = _signedOut;
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(prefs!.getBool(SyncNotifier.pendingWipeKey), isTrue);

        // So the next account still finds the wipe owed, and pushes nothing.
        clearInteractions(s.syncService);
        s.container.read(authProvider.notifier).state = const AuthState(
          status: AuthStatus.authenticated,
          uid: 'user-2',
        );
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        verifyNever(() => s.syncService.pushAllLocal(any()));
        expect(prefs!.getBool(SyncNotifier.pendingWipeKey), isTrue);
      });
    });

    test('drops the session before touching the data', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      final order = <String>[];
      when(() => s.syncService.deleteLocalData()).thenAnswer((_) async {
        order.add('wipe');
      });

      await s.notifier.signOutAndWipeLocalData(() async {
        order.add('endSession');
      });

      // The session has to go first: if the process dies between the two, the
      // device comes back signed out with the wipe still pending, rather than
      // signed in with the data already gone.
      expect(order, ['endSession', 'wipe']);
      expect(s.container.read(syncStateProvider).status, SyncStatus.disabled);
    });

    test('completes the wipe even when ending the session fails', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      await s.notifier.signOutAndWipeLocalData(
        () async => throw Exception('network down'),
      );

      verify(() => s.syncService.deleteLocalData()).called(1);
    });

    test(
      'leaves the wipe pending when it fails, and retries on sign-in',
      () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(SyncNotifier.pendingWipeKey);

        final s = _setup(auth: _signedIn);
        addTearDown(s.container.dispose);
        await Future<void>.delayed(Duration.zero);

        when(
          () => s.syncService.deleteLocalData(),
        ).thenThrow(Exception('disk error'));

        await expectLater(
          s.notifier.signOutAndWipeLocalData(() async {}),
          throwsException,
        );
        expect(prefs.getBool(SyncNotifier.pendingWipeKey), isTrue);

        // Next sign-in: the wipe runs again, and it runs before any push.
        when(() => s.syncService.deleteLocalData()).thenAnswer((_) async {});
        s.container.read(authProvider.notifier).state = const AuthState(
          status: AuthStatus.authenticated,
          uid: 'user-2',
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        verifyInOrder([
          () => s.syncService.deleteLocalData(),
          () => s.syncService.pushAllLocal('user-2'),
        ]);
        expect(prefs.getBool(SyncNotifier.pendingWipeKey), isNull);
      },
    );
  });
}

/// A clock the drain tests drive by hand: debounced pushes fire on the next
/// event-loop turn, retry backoff returns immediately, and [now] only moves
/// when a test moves it — so "the timestamp advanced" is an assertion about
/// the notifier rather than about how long the test took to run.
class _StubSyncClock extends SyncClock {
  DateTime instant = DateTime.utc(2026, 9, 9, 10);

  @override
  DateTime now() => instant;

  @override
  Timer runAfter(Duration delay, void Function() callback) =>
      Timer(Duration.zero, callback);

  @override
  Future<void> sleep(Duration duration) => Future<void>.value();
}

/// Lets every zero-delay timer and microtask the notifier scheduled run out.
/// A drain is several awaits deep behind a debounce, so one turn is not
/// enough and pumping a fixed number costs nothing on a stubbed clock.
Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
