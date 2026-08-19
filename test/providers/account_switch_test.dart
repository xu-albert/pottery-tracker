import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/providers/sync_provider.dart';
import 'package:pottery_tracker/services/sync_queue.dart';
import 'package:pottery_tracker/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end cover for the cross-account leak: sign-out has to destroy this
/// device's local data, because the *next* account's first sync pushes
/// whatever it finds locally into that account's own cloud tree.
///
/// Everything here is real except the network: a real Drift database, the real
/// [SyncService], the real [SyncNotifier], against a fake Firestore/Storage.
void main() {
  late AppDatabase db;
  late FakeFirebaseFirestore firestore;
  late MockFirebaseStorage storage;
  late _FlakyWipeSyncService syncService;
  late _StallableSyncQueue queue;
  late _TestAuthNotifier auth;
  late ProviderContainer container;
  late SyncNotifier notifier;
  late Directory docsDir;
  late Directory cacheDir;

  const uidA = 'account-a';
  const uidB = 'account-b';
  const uidC = 'account-c';

  AuthState signedInAs(String uid) =>
      AuthState(status: AuthStatus.authenticated, uid: uid);

  /// Lets the sync chain (auth listener → `_onAuthChanged` → `syncNow`) run to
  /// completion; every step is async but none of it waits on a real clock.
  Future<void> settle() async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  /// Writes the on-disk photo files the database rows point at, so the wipe
  /// has real files to orphan.
  Future<void> insertPieceWithPhoto(String pieceId, String title) async {
    final photoDir = Directory('${docsDir.path}/photos/$pieceId')
      ..createSync(recursive: true);
    File('${photoDir.path}/photo-$pieceId.jpg').writeAsBytesSync([1, 2, 3]);
    File('${photoDir.path}/photo-${pieceId}_thumb.jpg').writeAsBytesSync([4]);

    final now = DateTime.now();
    await db.piecesDao.insertPiece(
      PiecesCompanion(
        id: Value(pieceId),
        title: Value(title),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await db.photosDao.insertPhoto(
      PhotosCompanion(
        id: Value('photo-$pieceId'),
        pieceId: Value(pieceId),
        localPath: Value('${docsDir.path}/photos/$pieceId/photo-$pieceId.jpg'),
        cloudUrl: const Value('https://example.test/already-uploaded.jpg'),
        dateTaken: Value(now),
        createdAt: Value(now),
      ),
    );
    await db.materialsDao.findOrCreateClay('Stoneware for $title');
  }

  Future<List<String>> cloudPieceIds(String uid) async {
    final snap = await firestore.collection('users/$uid/pieces').get();
    return snap.docs.map((d) => d.id).toList()..sort();
  }

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    docsDir = Directory.systemTemp.createTempSync('account_switch_docs_');
    cacheDir = Directory.systemTemp.createTempSync('account_switch_cache_');
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
    syncService = _FlakyWipeSyncService(db, firestore, storage);
    queue = _StallableSyncQueue();
    auth = _TestAuthNotifier(signedInAs(uidA));

    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        syncQueueProvider.overrideWithValue(queue),
        syncServiceProvider.overrideWithValue(syncService),
      ],
    );
    notifier = container.read(syncStateProvider.notifier);
    // Reading the provider starts A's first sync; let it finish so no test
    // begins with one still in flight.
    await settle();
  });

  tearDown(() async {
    await settle();
    container.dispose();
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

  test('account A signed in backs its pieces up to its own tree', () async {
    await insertPieceWithPhoto('piece-a', "A's mug");
    await notifier.syncNow(forceFullSync: true);

    expect(await cloudPieceIds(uidA), ['piece-a']);
  });

  test('signing out then signing in as another account uploads nothing of the '
      "first account's", () async {
    await insertPieceWithPhoto('piece-a', "A's mug");
    await notifier.syncNow(forceFullSync: true);
    expect(await cloudPieceIds(uidA), ['piece-a']);

    // A photo staged by image_picker, still sitting in the cache directory.
    final staged = File('${cacheDir.path}/image_picker_stray.jpg')
      ..writeAsBytesSync([9, 9, 9]);

    // Sign out — this is the wipe under test.
    await notifier.signOutAndWipeLocalData(() async {});
    auth.set(const AuthState(status: AuthStatus.unauthenticated));
    await settle();

    // Nothing of A's is left on the device.
    expect(await db.select(db.pieces).get(), isEmpty);
    expect(await db.select(db.photos).get(), isEmpty);
    expect(await db.materialsDao.getAllClays(), isEmpty);
    expect(Directory('${docsDir.path}/photos').existsSync(), isFalse);
    expect(staged.existsSync(), isFalse);

    // Account B signs in on the same device and takes the first-sync path.
    auth.set(signedInAs(uidB));
    await settle();

    expect(
      await cloudPieceIds(uidB),
      isEmpty,
      reason: "account B's tree must contain nothing belonging to A",
    );
    final bPhotos = await firestore.collection('users/$uidB/photos').get();
    expect(bPhotos.docs, isEmpty);
    final bClays = await firestore.collection('users/$uidB/clays').get();
    expect(bClays.docs, isEmpty);

    // A's own backup is untouched — the wipe is local-only.
    expect(await cloudPieceIds(uidA), ['piece-a']);
  });

  test('B keeps its own pieces after the switch', () async {
    await insertPieceWithPhoto('piece-a', "A's mug");
    await notifier.syncNow(forceFullSync: true);

    await notifier.signOutAndWipeLocalData(() async {});
    auth.set(const AuthState(status: AuthStatus.unauthenticated));
    await settle();

    auth.set(signedInAs(uidB));
    await settle();

    await insertPieceWithPhoto('piece-b', "B's bowl");
    await notifier.syncNow(forceFullSync: true);
    await settle();

    expect(await cloudPieceIds(uidB), ['piece-b']);
    expect(await cloudPieceIds(uidA), ['piece-a']);
  });

  test(
    'the same account signing back in re-pulls its own cloud data',
    () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);

      await notifier.signOutAndWipeLocalData(() async {});
      auth.set(const AuthState(status: AuthStatus.unauthenticated));
      await settle();
      expect(await db.select(db.pieces).get(), isEmpty);

      // The watermark for A has to be gone, or this sign-in would take the
      // incremental branch and never re-download what the wipe deleted.
      auth.set(signedInAs(uidA));
      await settle();

      final restored = await db.select(db.pieces).get();
      expect(restored.map((p) => p.id), ['piece-a']);
    },
  );

  test('the wipe is owed from before the session is dropped', () async {
    await insertPieceWithPhoto('piece-a', "A's mug");
    await notifier.syncNow(forceFullSync: true);

    final prefs = await SharedPreferences.getInstance();
    bool? flaggedWhenSessionEnded;
    await notifier.signOutAndWipeLocalData(() async {
      flaggedWhenSessionEnded = prefs.getBool(SyncNotifier.pendingWipeKey);
    });

    // If the process dies while the session is going away, the device has to
    // come back knowing A's rows are still here and must not be pushed.
    expect(flaggedWhenSessionEnded, isTrue);
    expect(prefs.getBool(SyncNotifier.pendingWipeKey), isNull);
  });

  test('a wipe that keeps failing stops B from pushing anything', () async {
    await insertPieceWithPhoto('piece-a', "A's mug");
    await notifier.syncNow(forceFullSync: true);

    syncService.wipeFails = true;
    await expectLater(
      notifier.signOutAndWipeLocalData(() async {}),
      throwsException,
    );
    auth.set(const AuthState(status: AuthStatus.unauthenticated));
    await settle();

    // A's rows survived the failed wipe — which is exactly why B must not push.
    expect(await db.select(db.pieces).get(), isNotEmpty);

    auth.set(signedInAs(uidB));
    await settle();

    expect(
      await cloudPieceIds(uidB),
      isEmpty,
      reason: "B must not push A's surviving rows, even on a retried wipe",
    );
    expect(container.read(syncStateProvider).status, SyncStatus.blocked);

    // The manual "Sync Now" button is refused for as long as the wipe is owed.
    await notifier.syncNow(forceFullSync: true);
    expect(await cloudPieceIds(uidB), isEmpty);
    expect(container.read(syncStateProvider).status, SyncStatus.blocked);

    // Even once the wipe could succeed, "Sync Now" does not carry it: a delete
    // must never ride the push path, or it lands mid-session on whatever the
    // current account has since made.
    syncService.wipeFails = false;
    await notifier.syncNow(forceFullSync: true);
    expect(await db.select(db.pieces).get(), isNotEmpty);
    expect(container.read(syncStateProvider).status, SyncStatus.blocked);

    // The explicit, confirmed erase is the way out.
    await notifier.eraseLocalDataNow();
    await settle();

    expect(await db.select(db.pieces).get(), isEmpty);
    expect(await cloudPieceIds(uidB), isEmpty);
    expect(await cloudPieceIds(uidA), ['piece-a']);
    expect(container.read(syncStateProvider).status, SyncStatus.idle);
  });

  test(
    'an involuntary session loss keeps the data and blocks the next account',
    () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);
      expect(await cloudPieceIds(uidA), ['piece-a']);

      // Involuntary sign-out: AuthNotifier._init's reload()-failure path drops
      // the session without wiping, so A's data is still here and the owner
      // stamp is the only thing that knows whose it is.
      auth.set(const AuthState(status: AuthStatus.authenticated));
      await settle();
      expect(
        (await db.select(db.pieces).get()).map((p) => p.id),
        ['piece-a'],
        reason: 'an involuntary sign-out must not destroy anything',
      );

      auth.set(signedInAs(uidB));
      await settle();

      expect(
        await cloudPieceIds(uidB),
        isEmpty,
        reason: "B must not upload A's pieces",
      );
      expect(
        container.read(syncStateProvider).status,
        SyncStatus.blocked,
        reason: 'B is refused, not silently failing',
      );
      expect(
        container.read(syncStateProvider).blockedReason,
        SyncBlockedReason.foreignLocalData,
      );
      expect((await db.select(db.pieces).get()).map((p) => p.id), ['piece-a']);
      expect(await cloudPieceIds(uidA), ['piece-a']);
    },
  );

  test('the owner signing back in resumes backup normally', () async {
    await insertPieceWithPhoto('piece-a', "A's mug");
    await notifier.syncNow(forceFullSync: true);

    auth.set(const AuthState(status: AuthStatus.authenticated));
    await settle();
    auth.set(signedInAs(uidB));
    await settle();
    expect(container.read(syncStateProvider).status, SyncStatus.blocked);

    // Re-authenticating as the owner is the way out, with nothing deleted.
    auth.set(signedInAs(uidA));
    await settle();

    expect(container.read(syncStateProvider).status, SyncStatus.idle);
    expect((await db.select(db.pieces).get()).map((p) => p.id), ['piece-a']);
  });

  test(
    'an explicit erase releases the device to the signed-in account',
    () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);

      auth.set(const AuthState(status: AuthStatus.authenticated));
      await settle();
      auth.set(signedInAs(uidB));
      await settle();
      expect(container.read(syncStateProvider).status, SyncStatus.blocked);

      await notifier.eraseLocalDataNow();
      await settle();

      expect(await db.select(db.pieces).get(), isEmpty);
      expect(
        await cloudPieceIds(uidB),
        isEmpty,
        reason: "the erase must not push A's data on the way out",
      );
      expect(await cloudPieceIds(uidA), ['piece-a']);

      // B now owns a clean device and backs up its own work.
      await insertPieceWithPhoto('piece-b', "B's bowl");
      await notifier.syncNow(forceFullSync: true);
      expect(await cloudPieceIds(uidB), ['piece-b']);
    },
  );

  test(
    'a local-only user signing in for the first time still uploads',
    () async {
      // The upgrade path the leak fix must not regress: unowned local data
      // belongs to whoever signs in first.
      await notifier.signOutAndWipeLocalData(() async {});
      auth.set(const AuthState(status: AuthStatus.authenticated));
      await settle();

      await insertPieceWithPhoto('piece-local', 'Made before signing in');
      auth.set(signedInAs(uidB));
      await settle();

      expect(await cloudPieceIds(uidB), ['piece-local']);
    },
  );

  test(
    'a debounced push never resumes the wipe under the current account',
    () async {
      // The failure this guards: a wipe owed from A's sign-out must not fire
      // 500ms after B's own edit and delete the piece B just made.
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);

      syncService.wipeFails = true;
      await expectLater(
        notifier.signOutAndWipeLocalData(() async {}),
        throwsException,
      );
      auth.set(const AuthState(status: AuthStatus.unauthenticated));
      await settle();
      auth.set(signedInAs(uidB));
      await settle();
      expect(container.read(syncStateProvider).status, SyncStatus.blocked);

      // B works while backup is paused, then the wipe becomes possible again.
      await insertPieceWithPhoto('piece-b', "B's bowl");
      syncService.wipeFails = false;
      notifier.scheduleProcessQueue();
      await settle();

      expect(
        (await db.select(db.pieces).get()).map((p) => p.id),
        containsAll(['piece-b']),
        reason: "the debounced push must not delete B's work",
      );
      expect(
        await cloudPieceIds(uidB),
        isEmpty,
        reason: "and it must still refuse to upload A's data",
      );
    },
  );

  test('the explicit erase is the way out of an owed wipe', () async {
    await insertPieceWithPhoto('piece-a', "A's mug");
    await notifier.syncNow(forceFullSync: true);

    syncService.wipeFails = true;
    await expectLater(
      notifier.signOutAndWipeLocalData(() async {}),
      throwsException,
    );
    auth.set(const AuthState(status: AuthStatus.unauthenticated));
    await settle();
    auth.set(signedInAs(uidB));
    await settle();
    expect(container.read(syncStateProvider).status, SyncStatus.blocked);

    syncService.wipeFails = false;
    await notifier.eraseLocalDataNow();
    await settle();

    expect(await db.select(db.pieces).get(), isEmpty);
    expect(container.read(syncStateProvider).status, SyncStatus.idle);
    expect(await cloudPieceIds(uidB), isEmpty);
    expect(await cloudPieceIds(uidA), ['piece-a']);
  });

  test(
    'a queued push that beats the sign-in sync still claims the device',
    () async {
      // The device is unowned — A's sign-out wiped it — which is also the
      // state a fresh install is in.
      await notifier.signOutAndWipeLocalData(() async {});
      auth.set(const AuthState(status: AuthStatus.unauthenticated));
      await settle();
      expect(await syncService.getLocalDataOwner(), isNull);

      // B makes a piece as the sign-in lands, so its debounced push is already
      // scheduled when the auth state flips.
      await insertPieceWithPhoto('piece-b', "B's bowl");
      await container.read(syncTriggerProvider).afterPieceWrite('piece-b');

      // Stall the pending-count read `_onAuthChanged` awaits before it starts
      // the sign-in sync. That is the async gap the debounced push slips
      // through in production; holding it open just makes the order certain.
      queue.pendingCountDelay = const Duration(milliseconds: 1000);
      syncService.pushAllLocalCalls.clear();
      syncService.pushLog.clear();
      auth.set(signedInAs(uidB));
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      queue.pendingCountDelay = Duration.zero;
      await settle();

      expect(
        await cloudPieceIds(uidB),
        ['piece-b'],
        reason: 'the debounced push, not the sign-in sync, did the upload',
      );
      expect(syncService.pushLog, contains('pushPiece:piece-b'));
      expect(
        syncService.pushLog,
        contains('pushAllLocal:$uidB'),
        reason:
            'the sign-in sync stood down for the drain, so it has to have been '
            'run afterwards rather than dropped',
      );
      expect(
        syncService.pushLog.indexOf('pushPiece:piece-b'),
        lessThan(syncService.pushLog.indexOf('pushAllLocal:$uidB')),
        reason:
            'the drain has to have lost nothing by winning: it uploaded first '
            'and the owed full sync followed, or this test is no longer '
            'exercising the race the stamp fix is about',
      );
      expect(
        await syncService.getLastPulledAt(uidB),
        isNotNull,
        reason:
            "the owed sync's pull actually ran — a drain never pulls, so a "
            'dropped sign-in sync would leave no watermark',
      );
      expect(
        await syncService.getLocalDataOwner(),
        uidB,
        reason:
            'a device that has pushed for an account must be stamped with '
            'it, whichever push path did the pushing',
      );

      // Without that stamp the next account is free to take the device over.
      auth.set(const AuthState(status: AuthStatus.authenticated));
      await settle();
      auth.set(signedInAs(uidC));
      await settle();

      expect(
        await cloudPieceIds(uidC),
        isEmpty,
        reason: "C must not upload B's bowl",
      );
      expect(container.read(syncStateProvider).status, SyncStatus.blocked);
      expect(
        container.read(syncStateProvider).blockedReason,
        SyncBlockedReason.foreignLocalData,
      );
      expect((await db.select(db.pieces).get()).map((p) => p.id), ['piece-b']);
    },
  );

  test('a confirmed erase reports back when the device is busy', () async {
    await insertPieceWithPhoto('piece-a', "A's mug");

    syncService.pushAllLocalDelay = const Duration(milliseconds: 600);
    final inFlight = notifier.syncNow(forceFullSync: true);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(
      await notifier.eraseLocalDataNow(),
      EraseLocalDataResult.busy,
      reason: 'the user already answered a destructive confirmation',
    );
    expect(
      await db.select(db.pieces).get(),
      isNotEmpty,
      reason: 'a refused erase must not half-delete anything',
    );

    syncService.pushAllLocalDelay = Duration.zero;
    await inFlight;
    await settle();

    // Backed up by the sync above, so A's mug comes straight back down after
    // the erase. This one never reached the cloud, so its absence is what
    // shows the erase ran this time.
    await insertPieceWithPhoto('piece-unsynced', 'Never backed up');

    expect(await notifier.eraseLocalDataNow(), EraseLocalDataResult.erased);
    await settle();
    expect(
      (await db.select(db.pieces).get()).map((p) => p.id),
      isNot(contains('piece-unsynced')),
    );
  });

  test('a confirmed erase that fails is reported, not swallowed', () async {
    await insertPieceWithPhoto('piece-a', "A's mug");
    await notifier.syncNow(forceFullSync: true);

    syncService.wipeFails = true;
    expect(await notifier.eraseLocalDataNow(), EraseLocalDataResult.failed);
    expect(container.read(syncStateProvider).status, SyncStatus.error);
    expect(await db.select(db.pieces).get(), isNotEmpty);
  });

  test(
    'a forced full sync that loses the race is replayed as forced',
    () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      // A has synced once already, so anything short of a forced sync takes the
      // incremental branch and never reaches pushAllLocal.
      expect(await syncService.getLastPulledAt(uidA), isNotNull);

      await container.read(syncTriggerProvider).afterPieceWrite('piece-a');
      queue.pendingCountDelay = const Duration(milliseconds: 1200);

      // Let the debounced drain start and stall, then reach for the sync tile's
      // long press while it still holds the device.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      syncService.pushAllLocalCalls.clear();
      await notifier.syncNow(forceFullSync: true);
      expect(
        syncService.pushAllLocalCalls,
        isEmpty,
        reason: 'the drain held the device, so this request stood down',
      );

      await Future<void>.delayed(const Duration(milliseconds: 1500));
      queue.pendingCountDelay = Duration.zero;
      await settle();

      expect(
        syncService.pushAllLocalCalls,
        contains(uidA),
        reason:
            'the owed sync is replayed as the forced full sync that was asked '
            'for, not downgraded to the incremental branch',
      );
    },
  );

  group('read-only lock', () {
    test(
      'a refused device is locked, not merely blocked from pushing',
      () async {
        await insertPieceWithPhoto('piece-a', "A's mug");
        await notifier.syncNow(forceFullSync: true);

        // Involuntary session loss, then a different account signs in.
        auth.set(const AuthState(status: AuthStatus.authenticated));
        await settle();
        auth.set(signedInAs(uidB));
        await settle();

        expect(
          container.read(deviceLockedProvider),
          isTrue,
          reason:
              'the lock is what makes the device read-only: it keeps the '
              'refused account off every screen that can write, rather than '
              'letting it write and trying to track what it touched',
        );
        expect(container.read(syncStateProvider).status, SyncStatus.blocked);
        expect(
          container.read(syncStateProvider).blockedReason,
          SyncBlockedReason.foreignLocalData,
        );
      },
    );

    test(
      "the owner's pottery survives a contested session untouched",
      () async {
        await insertPieceWithPhoto('piece-a', "A's mug");
        await notifier.syncNow(forceFullSync: true);
        final before = await db.select(db.pieces).get();
        final photosBefore = await db.select(db.photos).get();
        final claysBefore = await db.materialsDao.getAllClays();

        auth.set(const AuthState(status: AuthStatus.authenticated));
        await settle();
        auth.set(signedInAs(uidB));
        await settle();
        // B sits on the lock screen for a while; a debounced push may fire.
        notifier.scheduleProcessQueue();
        await settle();
        await notifier.syncNow();
        await settle();

        expect(
          (await db.select(db.pieces).get()).map((p) => p.id),
          before.map((p) => p.id),
          reason: "nothing of the owner's may be deleted while refused",
        );
        expect(
          (await db.select(db.photos).get()).map((p) => p.id),
          photosBefore.map((p) => p.id),
        );
        expect(
          (await db.materialsDao.getAllClays()).map((c) => c.id),
          claysBefore.map((c) => c.id),
        );
        expect(
          await cloudPieceIds(uidB),
          isEmpty,
          reason: "and nothing of the owner's may reach the refused account",
        );
        expect(await cloudPieceIds(uidA), ['piece-a']);
      },
    );

    test(
      'the owner signing back in clears the lock with nothing lost',
      () async {
        await insertPieceWithPhoto('piece-a', "A's mug");
        await notifier.syncNow(forceFullSync: true);

        auth.set(const AuthState(status: AuthStatus.authenticated));
        await settle();
        auth.set(signedInAs(uidB));
        await settle();
        expect(container.read(deviceLockedProvider), isTrue);

        auth.set(signedInAs(uidA));
        await settle();

        expect(container.read(deviceLockedProvider), isFalse);
        expect((await db.select(db.pieces).get()).map((p) => p.id), [
          'piece-a',
        ]);
        expect(await cloudPieceIds(uidA), ['piece-a']);
      },
    );

    test('leaving a refused device deletes none of the owner data', () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);

      auth.set(const AuthState(status: AuthStatus.authenticated));
      await settle();
      auth.set(signedInAs(uidB));
      await settle();
      expect(container.read(deviceLockedProvider), isTrue);

      // The lock screen's way out: end the session, keep everything. None of
      // this pottery is B's to destroy.
      await notifier.endForeignSession(() async {});
      auth.set(const AuthState(status: AuthStatus.unauthenticated));
      await settle();

      expect((await db.select(db.pieces).get()).map((p) => p.id), ['piece-a']);
      expect(await cloudPieceIds(uidA), ['piece-a']);

      // And the owner can still come back to it.
      auth.set(signedInAs(uidA));
      await settle();
      expect(container.read(syncStateProvider).status, SyncStatus.idle);
      expect((await db.select(db.pieces).get()).map((p) => p.id), ['piece-a']);
    });

    test('an explicit erase from the lock releases the device', () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);

      auth.set(const AuthState(status: AuthStatus.authenticated));
      await settle();
      auth.set(signedInAs(uidB));
      await settle();
      expect(container.read(deviceLockedProvider), isTrue);

      expect(await notifier.eraseLocalDataNow(), EraseLocalDataResult.erased);
      await settle();

      expect(container.read(deviceLockedProvider), isFalse);
      expect(await db.select(db.pieces).get(), isEmpty);
      expect(
        await cloudPieceIds(uidB),
        isEmpty,
        reason: "the erase must not push A's data on the way out",
      );
      expect(await cloudPieceIds(uidA), ['piece-a']);
    });
  });

  test(
    'a wipe interrupted before it finished is completed on next sign-in',
    () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);

      // Simulate the process dying mid-wipe: the flag is set, the data is not
      // gone, and the session is already over.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SyncNotifier.pendingWipeKey, true);
      auth.set(const AuthState(status: AuthStatus.unauthenticated));
      await settle();

      auth.set(signedInAs(uidB));
      await settle();

      expect(await db.select(db.pieces).get(), isEmpty);
      expect(
        await cloudPieceIds(uidB),
        isEmpty,
        reason: 'the resumed wipe must run before B pushes anything',
      );
    },
  );
}

/// The real [SyncService] with one seam: [wipeFails] makes `deleteLocalData`
/// throw, standing in for the disk error or database failure that leaves the
/// device owing a wipe it could not perform.
class _FlakyWipeSyncService extends SyncService {
  _FlakyWipeSyncService(super.db, super.firestore, super.storage);

  bool wipeFails = false;

  /// Every uid `pushAllLocal` has run for. Only [SyncNotifier.syncNow] takes
  /// that branch, so it is how a test tells which of the two push paths did an
  /// upload — both leave the same rows in the cloud.
  final List<String> pushAllLocalCalls = [];

  /// Uploads in the order they happened, so a test can assert which push path
  /// got there first rather than only that both eventually ran.
  final List<String> pushLog = [];

  /// Holds `pushAllLocal` open, standing in for a slow first sync.
  Duration pushAllLocalDelay = Duration.zero;

  @override
  Future<void> deleteLocalData() async {
    if (wipeFails) throw Exception('simulated local wipe failure');
    return super.deleteLocalData();
  }

  @override
  Future<void> pushAllLocal(String uid) async {
    pushAllLocalCalls.add(uid);
    pushLog.add('pushAllLocal:$uid');
    if (pushAllLocalDelay > Duration.zero) {
      await Future<void>.delayed(pushAllLocalDelay);
    }
    return super.pushAllLocal(uid);
  }

  @override
  Future<void> pushPiece(String uid, String pieceId) {
    pushLog.add('pushPiece:$pieceId');
    return super.pushPiece(uid, pieceId);
  }
}

/// The real [SyncQueue] with one seam: [pendingCountDelay] stalls the pending
/// count read that `_onAuthChanged` awaits before it starts the sign-in sync,
/// which is the window a debounced push slips through in production.
class _StallableSyncQueue extends SyncQueue {
  Duration pendingCountDelay = Duration.zero;

  @override
  Future<int> get pendingCount async {
    if (pendingCountDelay > Duration.zero) {
      await Future<void>.delayed(pendingCountDelay);
    }
    return super.pendingCount;
  }
}

/// An [AuthNotifier] whose state the test drives directly, standing in for
/// Firebase sign-in/sign-out.
class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(super.initial) : super.withState();

  void set(AuthState next) => state = next;
}
