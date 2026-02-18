import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
_setup({AuthState auth = _signedOut}) {
  final syncService = MockSyncService();
  final queue = MockSyncQueue();

  // Default stubs so any test can call syncNow without wiring every method.
  when(() => queue.pendingCount).thenAnswer((_) async => 0);
  when(() => queue.getAll()).thenAnswer((_) async => []);
  when(() => queue.clear()).thenAnswer((_) async {});
  when(() => queue.remove(any())).thenAnswer((_) async {});

  when(() => syncService.getLastPulledAt(any())).thenAnswer((_) async => null);
  when(() => syncService.pushAllLocal(any())).thenAnswer((_) async {});
  when(() => syncService.pullAll(any())).thenAnswer((_) async {});
  when(
    () => syncService.pullChangedSince(any(), any()),
  ).thenAnswer((_) async {});
  when(() => syncService.retryMissingUploads(any())).thenAnswer((_) async {});
  when(() => syncService.deleteAllData(any())).thenAnswer((_) async {});

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
  setUpAll(() {
    registerFallbackValue(
      const SyncQueueEntry(operation: SyncOperation.pushPiece, entityId: ''),
    );
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

    test('clears queue after successful sync', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      await s.notifier.syncNow();

      // called(2): once from the constructor's auto-sync, once from this test
      verify(() => s.queue.clear()).called(2);
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

    test('does not run concurrently (second call is no-op)', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      // Track calls AFTER the constructor's auto-sync has completed
      var callCount = 0;
      when(() => s.syncService.pushAllLocal(any())).thenAnswer((_) async {
        callCount++;
        await Future.delayed(const Duration(milliseconds: 50));
      });

      // Fire two syncs concurrently
      final first = s.notifier.syncNow();
      final second = s.notifier.syncNow();
      await Future.wait([first, second]);

      // Only one of the two concurrent calls should have run
      expect(callCount, 1);
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
    test('calls syncService.deleteAllData and clears queue', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      await s.notifier.deleteAllData();

      verify(() => s.syncService.deleteAllData('user-1')).called(1);
      // called(2): once from the constructor's auto-sync, once from deleteAllData
      verify(() => s.queue.clear()).called(2);

      final state = s.container.read(syncStateProvider);
      expect(state.status, SyncStatus.idle);
      expect(state.pendingCount, 0);
    });

    test('does nothing when not signed in', () async {
      final s = _setup(auth: _signedOut);
      addTearDown(s.container.dispose);

      await s.notifier.deleteAllData();

      verifyNever(() => s.syncService.deleteAllData(any()));
    });

    test('sets error state on failure', () async {
      final s = _setup(auth: _signedIn);
      addTearDown(s.container.dispose);
      await Future<void>.delayed(Duration.zero);

      when(
        () => s.syncService.deleteAllData(any()),
      ).thenThrow(Exception('permission denied'));

      await s.notifier.deleteAllData();

      final state = s.container.read(syncStateProvider);
      expect(state.status, SyncStatus.error);
      expect(state.errorMessage, contains('permission denied'));
    });
  });
}
