import 'dart:async';
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

  /// Whether Firebase accepts the account deletion. In production it refuses
  /// with `requires-recent-login` far more often than not, so that is the
  /// default here; a test that needs the account really gone flips it.
  var accountDeleteSucceeds = false;

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
    accountDeleteSucceeds = false;

    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((_) => auth),
        syncQueueProvider.overrideWithValue(queue),
        syncServiceProvider.overrideWithValue(syncService),
        syncStateProvider.overrideWith(
          (ref) => SyncNotifier(
            ref,
            queue,
            syncService,
            deleteAuthAccount: () async {
              if (!accountDeleteSucceeds) {
                throw PlatformException(code: 'requires-recent-login');
              }
            },
          ),
        ),
      ],
    );
    notifier = container.read(syncStateProvider.notifier);
    // `routerProvider` keeps this alive in the app. It owns the refusal marker,
    // which is deliberately not written from the sync path.
    container.read(deviceRefusalRecorderProvider);
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
    expect(
      await notifier.eraseLocalDataNow(),
      EraseLocalDataResult.failed,
      reason: 'nothing was deleted, so this is the outcome that says so',
    );
    expect(container.read(syncStateProvider).status, SyncStatus.error);
    expect(await db.select(db.pieces).get(), isNotEmpty);
  });

  test(
    'an erase that removed everything but the photo files says exactly that',
    () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);

      // Take away the documents directory's write permission so the photos
      // directory inside it cannot be unlinked. Root ignores the mode bits,
      // so the setup is checked before anything is asserted on it.
      final photosDir = Directory('${docsDir.path}/photos');
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

      expect(
        await notifier.eraseLocalDataNow(),
        EraseLocalDataResult.photosSurvived,
        reason:
            '"nothing was deleted" would be false: every row is gone and '
            'only the photographs are not',
      );
      await settle();

      expect(await db.select(db.pieces).get(), isEmpty);
      expect(photosDir.existsSync(), isTrue);
      expect(
        container.read(deviceLockReasonProvider),
        DeviceLockReason.pendingWipe,
        reason: 'the photographs are still here, so the erase is still owed',
      );

      // The lock screen keeps offering the erase. Once the directory can be
      // removed again, retrying is what finishes it. (The photos directory
      // itself comes straight back: A's backed-up mug is pulled down again by
      // the sync that follows a clean erase.)
      Process.runSync('chmod', ['700', docsDir.path]);
      expect(await notifier.eraseLocalDataNow(), EraseLocalDataResult.erased);
      await settle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SyncNotifier.pendingWipeKey), isNull);
      expect(container.read(deviceLockReasonProvider), isNull);
    },
  );

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

  group('the lock cannot be escaped', () {
    // Four ways the lock silently released when it was derived from the live
    // sync status instead of the persisted owner stamp. Each one put a refused
    // account on the owner's writable album.
    Future<void> refuseB() async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);
      auth.set(const AuthState(status: AuthStatus.authenticated));
      await settle();
      auth.set(signedInAs(uidB));
      await settle();
      expect(container.read(deviceLockedProvider), isTrue);
    }

    test('a failed erase does not release it', () async {
      await refuseB();

      syncService.wipeFails = true;
      expect(await notifier.eraseLocalDataNow(), EraseLocalDataResult.failed);
      await settle();

      expect(
        container.read(syncStateProvider).status,
        SyncStatus.error,
        reason: 'the erase really did fail',
      );
      expect(
        container.read(deviceLockedProvider),
        isTrue,
        reason:
            "an error transition must not hand the refused account the "
            "owner's album, writable, with the owner's rows still on it",
      );
    });

    test(
      'ending the session does not release it while the data stays',
      () async {
        await refuseB();

        // endForeignSession sets the sync state to disabled; the lock must not
        // follow it down while B is still, for a frame, the signed-in account.
        await notifier.endForeignSession(() async {});
        expect(
          container.read(deviceLockedProvider),
          isTrue,
          reason: 'the stamp still names A and B is still the session',
        );
      },
    );

    test('a local-only session cannot walk in past it', () async {
      await refuseB();

      // "Skip for now" makes a session-less state. It must not be a door into
      // the owner's pottery — the control itself is hidden on a stamped
      // device, and the stamp is what proves it is stamped.
      expect(
        container.read(skipSignInAllowedProvider),
        isFalse,
        reason: 'skipping sign-in is closed once the device has an owner',
      );
    });

    test('it holds on the first frame, before any sync has run', () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);

      // A fresh container, as at launch: nothing has synced yet, so a lock
      // derived from sync status would still read unlocked here.
      final fresh = ProviderContainer(
        overrides: [
          authProvider.overrideWith((_) => _TestAuthNotifier(signedInAs(uidB))),
          syncQueueProvider.overrideWithValue(SyncQueue()),
          syncServiceProvider.overrideWithValue(syncService),
        ],
      );
      // Seed the stamp exactly as `main` does before runApp — from
      // preferences, synchronously, with no sync having run.
      fresh.read(localDataOwnerProvider.notifier).state = await syncService
          .getLocalDataOwner();

      expect(
        fresh.read(deviceLockedProvider),
        isTrue,
        reason:
            'the album must never render for a refused account, not even for '
            'the frame before the first async claim resolves',
      );

      // Let the container's own sync finish before tearing it down, so no
      // in-flight work outlives it.
      await settle();
      fresh.dispose();
    });

    test('the owner is never locked out by an offline launch', () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);

      // Ruling 2's ordinary offline launch: session-less, on a stamped device.
      auth.set(const AuthState(status: AuthStatus.authenticated));
      await settle();

      expect(
        container.read(deviceLockedProvider),
        isFalse,
        reason:
            'a session-less launch is the owner opening the app offline, and '
            'locking them out of their own pottery is what ruling 2 forbids',
      );
    });

    /// A relaunch: a brand new container seeded from preferences exactly the
    /// way `main` seeds it before `runApp`, with nothing carried over in
    /// memory. [session] is what `AuthNotifier._init` would have settled on.
    Future<ProviderContainer> relaunch(AuthState session) async {
      final prefs = await SharedPreferences.getInstance();
      return ProviderContainer(
        overrides: [
          authProvider.overrideWith((_) => _TestAuthNotifier(session)),
          syncQueueProvider.overrideWithValue(SyncQueue()),
          syncServiceProvider.overrideWithValue(syncService),
          // The same seeding `main` does, not a hand-copied version of it: a
          // container that supplies a provider from the preference the test
          // then asserts proves only that the key was written.
          ...deviceStateOverrides(prefs),
        ],
      );
    }

    test(
      'force-quitting the lock and relaunching offline does not open it',
      () async {
        await refuseB();

        // The likeliest response to a screen whose only buttons leave or erase:
        // kill the app. Relaunching with no network makes `reload()` fail, so
        // `AuthNotifier._init` signs out of Firebase and — onboarding is long
        // since done — comes back session-less. No uid to compare the stamp
        // against, and no race: this is simply what the next launch looks like.
        final relaunched = await relaunch(
          const AuthState(status: AuthStatus.authenticated),
        );
        addTearDown(relaunched.dispose);

        expect(
          relaunched.read(deviceLockedProvider),
          isTrue,
          reason:
              'the refusal is remembered, so killing the app is not a way back '
              "onto the owner's album with a delete that later pushes under "
              "the owner's own name",
        );
      },
    );

    test(
      'the owner relaunching offline is not locked out of their own',
      () async {
        await insertPieceWithPhoto('piece-a', "A's mug");
        await notifier.syncNow(forceFullSync: true);

        // The same session-less relaunch, on a device nobody has been refused
        // on. Ruling 2 requires this to keep working: an ordinary offline launch
        // must not lock the owner out of their own pottery.
        final relaunched = await relaunch(
          const AuthState(status: AuthStatus.authenticated),
        );
        addTearDown(relaunched.dispose);

        expect(
          relaunched.read(deviceLockedProvider),
          isFalse,
          reason:
              'a session-less launch on an uncontested device is the owner '
              'offline, and locking them out is what ruling 2 forbids',
        );
      },
    );

    test('an owed wipe still locks the device after a relaunch', () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);

      // The wipe A confirmed fails and the process dies. The flag is on disk;
      // the lock has to be back up on the next launch's first frame, which is
      // what seeding it before `runApp` buys.
      syncService.wipeFails = true;
      await expectLater(
        notifier.signOutAndWipeLocalData(() async {}),
        throwsException,
      );
      await settle();

      final relaunched = await relaunch(signedInAs(uidA));
      addTearDown(relaunched.dispose);

      expect(
        relaunched.read(deviceLockedProvider),
        isTrue,
        reason:
            'A asked for this library to be destroyed, so it must not come '
            'back browsable because the app was restarted',
      );
    });

    test('the owner reclaiming the device lifts the refusal', () async {
      await refuseB();

      auth.set(signedInAs(uidA));
      await settle();
      expect(container.read(deviceLockedProvider), isFalse);

      // And it stays lifted across a relaunch: reclaiming is one of only two
      // things that clears the refusal, so the next offline launch is an
      // ordinary one again.
      final relaunched = await relaunch(
        const AuthState(status: AuthStatus.authenticated),
      );
      addTearDown(relaunched.dispose);
      expect(relaunched.read(deviceLockedProvider), isFalse);
    });

    test('erasing the device lifts the refusal', () async {
      await refuseB();

      expect(await notifier.eraseLocalDataNow(), EraseLocalDataResult.erased);
      await settle();

      final relaunched = await relaunch(
        const AuthState(status: AuthStatus.authenticated),
      );
      addTearDown(relaunched.dispose);
      expect(
        relaunched.read(deviceLockedProvider),
        isFalse,
        reason: 'there is nothing left here for anyone to be refused over',
      );
    });

    test('a failed erase does not release an owed wipe', () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);

      // A asks for the data to be destroyed and the wipe fails, so A — the
      // owner — signs back in owing one. The stamp cannot lock this: A is both
      // the owner and the session, so only the owed wipe holds the device.
      syncService.wipeFails = true;
      await expectLater(
        notifier.signOutAndWipeLocalData(() async {}),
        throwsException,
      );
      auth.set(const AuthState(status: AuthStatus.unauthenticated));
      await settle();
      auth.set(signedInAs(uidA));
      await settle();
      expect(container.read(deviceLockedProvider), isTrue);

      expect(await notifier.eraseLocalDataNow(), EraseLocalDataResult.failed);
      await settle();

      expect(
        container.read(syncStateProvider).status,
        SyncStatus.error,
        reason: 'the erase really did fail',
      );
      expect(
        container.read(deviceLockedProvider),
        isTrue,
        reason:
            'A asked for this library to be destroyed; an error transition '
            'must not hand it back browsable and editable while the wipe is '
            'still owed',
      );
    });

    test('an owed wipe locks the device too', () async {
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

      expect(
        container.read(deviceLockedProvider),
        isTrue,
        reason:
            'A signed out asking for this data to be destroyed; until the '
            'wipe succeeds it must not be browsable and editable by whoever '
            'picks the phone up next',
      );
    });
  });

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

  group('a wipe in flight is not an owed wipe', () {
    // The lock exists for a wipe that was confirmed and did not happen. While
    // one is still running it must not engage, because the router would tear
    // down the screen that owes the user the result of what they confirmed.
    test('the lock stays down while a confirmed wipe is running', () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);

      final gate = Completer<void>();
      syncService.wipeGate = gate;
      final erase = notifier.eraseLocalDataNow();
      await settle();

      expect(
        container.read(deviceLockedProvider),
        isFalse,
        reason:
            'the wipe is in flight, not owed — locking here redirects away '
            'from the screen that has to report how it went',
      );

      gate.complete();
      syncService.wipeGate = null;
      expect(await erase, EraseLocalDataResult.erased);
      await settle();
      expect(container.read(deviceLockedProvider), isFalse);
    });

    test('a sign-out wipe reports before the lock goes up', () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);

      final gate = Completer<void>();
      syncService.wipeGate = gate;
      syncService.wipeFails = true;
      final signOut = notifier.signOutAndWipeLocalData(() async {});
      await settle();

      expect(
        container.read(deviceLockedProvider),
        isFalse,
        reason: 'Settings has to survive long enough to say the wipe failed',
      );

      gate.complete();
      syncService.wipeGate = null;
      await expectLater(signOut, throwsException);
      await settle();

      expect(
        container.read(deviceLockedProvider),
        isTrue,
        reason: 'and once it has failed the wipe really is owed',
      );
    });

    test('a delete-account wipe reports before the lock goes up', () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);

      final gate = Completer<void>();
      syncService.wipeGate = gate;
      syncService.wipeFails = true;
      final delete = notifier.deleteAllData();
      await settle();

      expect(container.read(deviceLockedProvider), isFalse);

      gate.complete();
      syncService.wipeGate = null;
      expect(await delete, DeleteAllDataResult.accountAndLocalDataSurvived);
      await settle();
      expect(container.read(deviceLockedProvider), isTrue);
    });
  });

  test(
    'a delete that loses both halves never reports the account as gone',
    () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);

      // The double failure. The cloud tree goes; the account does not, because
      // Firebase refuses (here by not existing at all, in production almost
      // always 'requires-recent-login'); and then the local wipe fails too.
      syncService.wipeFails = true;
      final result = await notifier.deleteAllData();

      expect(
        result,
        DeleteAllDataResult.accountAndLocalDataSurvived,
        reason:
            'a live account described as deleted is the one outcome the user '
            'will not act on, because they have been told there is nothing '
            'left to do',
      );
      expect(
        await db.select(db.pieces).get(),
        isNotEmpty,
        reason: 'and the local copy really is still here to be erased',
      );
    },
  );

  group('a deletion Firebase accepts', () {
    setUp(() => accountDeleteSucceeds = true);

    test('ends the session along with everything else', () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);

      expect(await notifier.deleteAllData(), DeleteAllDataResult.deleted);
      await settle();

      expect(container.read(authProvider).isSignedIn, isFalse);
      expect(await db.select(db.pieces).get(), isEmpty);
      expect(await cloudPieceIds(uidA), isEmpty);
      expect(await syncService.getLocalDataOwner(), isNull);
      expect(container.read(deviceLockedProvider), isFalse);
    });

    test('whose local wipe failed still ends the session, and never stamps the '
        'deleted uid', () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);
      expect(await syncService.getLocalDataOwner(), uidA);

      syncService.wipeFails = true;
      expect(
        await notifier.deleteAllData(),
        DeleteAllDataResult.localDataSurvived,
      );
      await settle();

      // User.delete signed the SDK out as it went. The app has to agree,
      // or the album comes back for an account that no longer exists.
      expect(
        container.read(authProvider).isSignedIn,
        isFalse,
        reason: 'the account is gone, so the session naming it must be too',
      );
      expect(
        container.read(deviceLockReasonProvider),
        DeviceLockReason.pendingWipe,
        reason: 'the local copy survived, and the wipe is still owed',
      );
      expect(await db.select(db.pieces).get(), isNotEmpty);

      // The lock screen retries the wipe when it opens; this time it goes
      // through, and the lock lifts.
      syncService.wipeFails = false;
      await notifier.retryOwedWipe();
      await settle();
      expect(container.read(deviceLockReasonProvider), isNull);
      expect(await db.select(db.pieces).get(), isEmpty);

      // Nothing is left that could claim the device for A: with no session
      // neither the debounced push nor a manual sync reaches the stamp.
      syncService.pushAllLocalCalls.clear();
      notifier.scheduleProcessQueue();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await notifier.syncNow(forceFullSync: true);
      await settle();

      expect(
        await syncService.getLocalDataOwner(),
        isNull,
        reason:
            'a stamp for a deleted uid can never be matched by any '
            'sign-in again, so it would lock this device for good',
      );
      expect(container.read(localDataOwnerProvider), isNull);
      expect(syncService.pushAllLocalCalls, isEmpty);
    });
  });

  group('a half-finished account deletion', () {
    /// Relaunches the app the way `main` does — every persisted input seeded
    /// through the same helper, so dropping one there fails here.
    Future<ProviderContainer> relaunchAs(String uid) async {
      final prefs = await SharedPreferences.getInstance();
      final fresh = ProviderContainer(
        overrides: [
          authProvider.overrideWith((_) => _TestAuthNotifier(signedInAs(uid))),
          syncQueueProvider.overrideWithValue(SyncQueue()),
          syncServiceProvider.overrideWithValue(syncService),
          ...deviceStateOverrides(prefs),
        ],
      );
      addTearDown(fresh.dispose);
      return fresh;
    }

    test('survives the local wipe, which deletes no account', () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);

      // The cloud tree goes, the account does not, and the local wipe
      // succeeds — so the whole recovery is a later retry, and this is the
      // outcome that used to keep nothing.
      expect(
        await notifier.deleteAllData(),
        DeleteAllDataResult.accountSurvived,
      );
      await settle();

      expect(
        container.read(accountDeletionOwedProvider),
        uidA,
        reason:
            'erasing local data deletes no Firebase account, so it must not '
            'erase the record that one is still standing',
      );
      expect(
        (await relaunchAs(uidA)).read(accountDeletionOwedForSessionProvider),
        isTrue,
        reason:
            'A signs back in to retry, and the delete-account surface has to '
            'still say the deletion is outstanding',
      );
    });

    test('survives the erase the lock screen tells the user to do', () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);

      syncService.wipeFails = true;
      expect(
        await notifier.deleteAllData(),
        DeleteAllDataResult.accountAndLocalDataSurvived,
      );
      await settle();

      // Step one of the instruction is the erase. It must not destroy the
      // memory of step two.
      syncService.wipeFails = false;
      expect(await notifier.eraseLocalDataNow(), EraseLocalDataResult.erased);
      await settle();

      expect(container.read(accountDeletionOwedProvider), uidA);
      expect(
        (await relaunchAs(uidA)).read(accountDeletionOwedForSessionProvider),
        isTrue,
      );
    });

    test('is not reported to the next account to sign in here', () async {
      await insertPieceWithPhoto('piece-a', "A's mug");
      await notifier.syncNow(forceFullSync: true);
      await notifier.deleteAllData();
      await settle();

      expect(
        (await relaunchAs(uidB)).read(accountDeletionOwedForSessionProvider),
        isFalse,
        reason:
            "B never asked for anything to be deleted, and B's account did "
            'not survive anything',
      );
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

  /// Holds `deleteLocalData` open, so a test can look at the device while the
  /// wipe the user confirmed is still running.
  Completer<void>? wipeGate;

  @override
  Future<void> deleteLocalData() async {
    final gate = wipeGate;
    if (gate != null) await gate.future;
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
