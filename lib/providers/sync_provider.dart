import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/material_writer.dart';
import '../services/sync_queue.dart';
import '../services/sync_service.dart';
import '../services/sync_trigger.dart';
import 'auth_provider.dart';
import 'database_provider.dart';

/// [SyncStatus.blocked] is a refusal, not a failure: this device is not
/// allowed to push yet. Which refusal it is, and what the user does about it,
/// is [DeviceLockReason]'s job — a device refusing to push is always a locked
/// device, and the lock outlives any one sync attempt.
enum SyncStatus { idle, syncing, error, blocked, disabled }

/// Why the router is holding this device read-only, and so also why a push
/// would be refused. Read from persisted state rather than from [SyncState],
/// which is transient.
enum DeviceLockReason {
  /// A wipe the user confirmed has not finished. The way out is to finish it.
  pendingWipe,

  /// The pottery here belongs to a different account. The way out is for that
  /// account to sign back in, or for the user to erase the device.
  foreignLocalData,
}

class SyncState {
  final SyncStatus status;
  final int pendingCount;
  final DateTime? lastSyncedAt;
  final String? errorMessage;

  const SyncState({
    this.status = SyncStatus.disabled,
    this.pendingCount = 0,
    this.lastSyncedAt,
    this.errorMessage,
  });

  /// [errorMessage] deliberately does not survive a `copyWith` that omits it:
  /// it describes the transition that put the state into [SyncStatus.error],
  /// and carrying it into the next one would caption a healthy state with a
  /// stale failure. Several callers rely on that.
  SyncState copyWith({
    SyncStatus? status,
    int? pendingCount,
    DateTime? lastSyncedAt,
    String? errorMessage,
  }) {
    return SyncState(
      status: status ?? this.status,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      errorMessage: errorMessage,
    );
  }
}

/// What an explicit erase actually did, so the caller can tell the user.
enum EraseLocalDataResult {
  /// Every local store is gone and the device is unclaimed.
  erased,

  /// Nothing was attempted: a sync or wipe held the device.
  busy,

  /// Nothing was deleted.
  failed,

  /// The rows, the queue, the watermarks and the ownership stamp are gone,
  /// but some photo files are still on disk and the wipe stays owed. Reported
  /// separately because "nothing was deleted" is false here, and the user has
  /// a retry available on the lock screen that finishes it.
  photosSurvived,
}

/// What a confirmed account deletion actually did. Mirrors
/// [EraseLocalDataResult]: both are destructive actions the user has already
/// confirmed, so both report rather than returning silently.
///
/// The partial outcomes are named separately because "it failed" and "your
/// cloud data is gone but your account is not" are different things to be
/// told, and only one of them is recoverable by trying again.
enum DeleteAllDataResult {
  /// Cloud data, auth account and local data are all gone.
  deleted,

  /// Nothing was attempted: a sync or wipe held the device.
  busy,

  /// Nothing was deleted.
  failed,

  /// The cloud data was deleted but the auth account survived — almost always
  /// because Firebase wants a recent sign-in before it will delete an account.
  /// Signing in again and retrying is what clears it.
  accountSurvived,

  /// The cloud side is gone and the local copy is not. The app is no longer
  /// signed in to anything meaningful, so the local rows are all that is left.
  localDataSurvived,

  /// Both halves survived: the cloud tree is gone, but the auth account and
  /// the copy on this device are both still there. It has its own outcome
  /// rather than collapsing into either one, because each of the two needs a
  /// different action from the user and neither may be left unsaid.
  accountAndLocalDataSurvived,
}

Future<void> _deleteFirebaseAccount() async {
  await FirebaseAuth.instance.currentUser?.delete();
}

class SyncNotifier extends StateNotifier<SyncState> {
  /// Set for the duration of a local wipe so an interrupted one (crash, kill,
  /// failed delete) can be finished before anything is ever pushed again.
  ///
  /// Public for the same reason as [SyncService.localDataOwnerKey]: startup
  /// seeds the read-only lock from it before `runApp`, so the device an owed
  /// wipe holds is locked on the very first frame rather than a beat later.
  static const pendingWipeKey = 'pendingLocalDataWipe';

  final Ref _ref;
  final SyncQueue _queue;
  final SyncService _syncService;
  bool _syncing = false;
  bool _wiping = false;

  /// True while a sync that started *before* a wipe is still running. It can
  /// still be inserting rows and downloading photos behind the delete, so the
  /// device is not provably clean and the pending-wipe flag has to outlive it.
  /// Every site that clears the flag has to honour this, not just the wipe
  /// that noticed it.
  bool _staleSyncInFlight = false;

  /// Set when a sync stands down because a push already holds [_syncing], and
  /// carries the mode that was asked for.
  ///
  /// Without it the sign-in sync is simply dropped: a drain only empties the
  /// queue — it never pulls, never runs pushAllLocal and never writes a
  /// watermark — yet it would report the device idle and freshly synced. The
  /// mode travels with the debt because the tile's long-press is the only
  /// re-upload-everything affordance in the app, and it races a drain
  /// scheduled 500ms after any edit.
  bool _syncOwed = false;
  bool _owedSyncForcesFull = false;
  Timer? _processTimer;
  Future<void>? _wipeInFlight;

  /// Deletes the Firebase account itself.
  ///
  /// The one dependency of this class that was not injected, which left the
  /// branch where the deletion *succeeds* unreachable from any test: building
  /// `FirebaseAuth.instance` needs auth platform channels the test harness
  /// does not provide, so every test saw the requires-recent-login side only.
  /// Production always passes nothing and gets Firebase.
  final Future<void> Function() _deleteAuthAccount;

  SyncNotifier(
    this._ref,
    this._queue,
    this._syncService, {
    Future<void> Function()? deleteAuthAccount,
  }) : _deleteAuthAccount = deleteAuthAccount ?? _deleteFirebaseAccount,
       super(const SyncState()) {
    _ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.isSignedIn && prev?.uid != next.uid) {
        _onAuthChanged(next.uid!);
      } else if (!next.isSignedIn) {
        state = const SyncState(status: SyncStatus.disabled);
        // Signed out or local-only: finish a wipe that never completed, so the
        // app does not sit on the previous account's pieces.
        unawaited(_finishInterruptedWipe());
      }
    }, fireImmediately: true);
    unawaited(_refreshPersistedDeviceState());
  }

  /// Re-reads everything the read-only lock is derived from, so the providers
  /// the router watches agree with what is actually on disk.
  Future<void> _refreshPersistedDeviceState() async {
    _publishLocalDataOwner(await _syncService.getLocalDataOwner());
    _publishDeviceContested(await _syncService.getDeviceContested());
    final prefs = await SharedPreferences.getInstance();
    _publishPendingWipe(prefs.getBool(pendingWipeKey) == true);
    if (!mounted) return;
    _ref.read(accountDeletionOwedProvider.notifier).state = prefs.getString(
      SyncService.accountDeletionOwedKey,
    );
  }

  Future<void> _onAuthChanged(String uid) async {
    // Before this uid can push anything, make sure no earlier account's data
    // is still lying around from a wipe that was cut short.
    await _finishInterruptedWipe();
    state = state.copyWith(status: SyncStatus.idle);
    await _refreshPendingCount();
    await syncNow();
  }

  Future<void> _refreshPendingCount() async {
    final count = await _queue.pendingCount;
    state = state.copyWith(pendingCount: count);
  }

  void scheduleProcessQueue() {
    _processTimer?.cancel();
    _processTimer = Timer(const Duration(milliseconds: 500), () {
      _pushQueue();
    });
  }

  Future<void> _pushQueue() async {
    if (_syncing || _wiping) return;
    final auth = _ref.read(authProvider);
    if (!auth.isSignedIn || auth.uid == null) return;

    _syncing = true;
    try {
      if (await _claimOrBlock(auth.uid!)) return;
      await _processQueueInternal(auth.uid!);
      await _refreshPendingCount();
      if (state.status != SyncStatus.error && !_syncOwed) {
        // Only a completed sync may claim the device is backed up. A drain
        // empties the queue but never pulls, so saying "backed up" while a
        // full sync is still owed would name a backup that has not happened.
        state = state.copyWith(
          status: SyncStatus.idle,
          lastSyncedAt: DateTime.now(),
        );
      }
    } catch (e) {
      debugPrint('SyncNotifier: push failed: $e');
      await _refreshPendingCount();
      state = state.copyWith(
        status: SyncStatus.error,
        errorMessage: e.toString(),
      );
    } finally {
      _staleSyncInFlight = false;
      _syncing = false;
    }
    await _payOwedSync();
  }

  /// Runs a sync that stood down earlier, in the mode it asked for.
  Future<void> _payOwedSync() async {
    if (!_syncOwed || _wiping) return;
    _syncOwed = false;
    final forced = _owedSyncForcesFull;
    _owedSyncForcesFull = false;
    await syncNow(forceFullSync: forced);
  }

  Future<void> syncNow({bool forceFullSync = false}) async {
    final auth = _ref.read(authProvider);
    if (!auth.isSignedIn || auth.uid == null) {
      state = const SyncState(status: SyncStatus.disabled);
      return;
    }
    if (_syncing || _wiping) {
      // Stand down, but remember the debt so the sync is not lost. A forced
      // request must be replayed as forced, never quietly downgraded.
      _syncOwed = true;
      _owedSyncForcesFull = _owedSyncForcesFull || forceFullSync;
      return;
    }
    _syncing = true;

    final uid = auth.uid!;
    state = state.copyWith(status: SyncStatus.syncing);

    try {
      if (await _claimOrBlock(uid)) return;

      final lastPulled = forceFullSync
          ? null
          : await _syncService.getLastPulledAt(uid);

      if (lastPulled == null) {
        // First sync on this device (or forced) — push local data first, then pull
        await _syncService.pushAllLocal(uid);
        await _syncService.pullAll(uid);
      } else {
        // Incremental: process push queue, then pull changes
        await _processQueueInternal(uid);
        await _syncService.pullChangedSince(uid, lastPulled);
      }

      // Retry uploading photos that have local files but no cloudUrl
      await _syncService.retryMissingUploads(uid);

      await _queue.clear();
      state = SyncState(
        status: SyncStatus.idle,
        pendingCount: 0,
        lastSyncedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('SyncNotifier: sync failed: $e');
      await _refreshPendingCount();
      state = state.copyWith(
        status: SyncStatus.error,
        errorMessage: e.toString(),
      );
    } finally {
      _staleSyncInFlight = false;
      _syncing = false;
    }
    await _payOwedSync();
  }

  Future<void> _processQueueInternal(String uid) async {
    final entries = await _queue.getAll();
    for (final entry in entries) {
      // Photo file uploads are best-effort: try once, always remove.
      // retryMissingUploads() catches any failures on the next full sync.
      if (entry.operation == SyncOperation.pushPhotoFile) {
        try {
          await _processEntry(uid, entry);
        } catch (e) {
          debugPrint(
            'SyncNotifier: photo file upload failed (best-effort): $e',
          );
        }
        await _queue.remove(entry);
        continue;
      }

      var success = false;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          await _processEntry(uid, entry);
          success = true;
          break;
        } catch (e) {
          debugPrint('SyncNotifier: retry $attempt for ${entry.operation}: $e');
          if (attempt < 2) {
            await Future.delayed(Duration(seconds: 1 << attempt));
          }
        }
      }
      if (success) {
        await _queue.remove(entry);
      }
    }
  }

  Future<void> _processEntry(String uid, SyncQueueEntry entry) async {
    switch (entry.operation) {
      case SyncOperation.pushPiece:
        await _syncService.pushPiece(uid, entry.entityId);
      case SyncOperation.pushPhoto:
        await _syncService.pushPhoto(uid, entry.entityId);
      case SyncOperation.pushPhotoFile:
        await _syncService.uploadPhotoFile(uid, entry.entityId);
      case SyncOperation.pushClay:
        await _syncService.pushClay(uid, entry.entityId);
      case SyncOperation.pushGlaze:
        await _syncService.pushGlaze(uid, entry.entityId);
      case SyncOperation.pushTag:
        await _syncService.pushTag(uid, entry.entityId);
      case SyncOperation.pushPieceGlazes:
        await _syncService.pushPieceGlazes(uid, entry.entityId);
      case SyncOperation.pushPieceTags:
        await _syncService.pushPieceTags(uid, entry.entityId);
      case SyncOperation.deletePiece:
        await _syncService.pushPieceDeletion(uid, entry.entityId);
      case SyncOperation.deletePhoto:
        await _syncService.pushDeletion(uid, 'photos', entry.entityId);
      case SyncOperation.deleteMaterial:
        final collection = entry.extraData ?? 'clays';
        await _syncService.pushDeletion(uid, collection, entry.entityId);
    }
  }

  /// Signs the account out of this device and destroys its local data.
  ///
  /// Sign-out is destructive by design. Whatever survives it is uploaded into
  /// the *next* account's cloud tree by `pushAllLocal` on that account's first
  /// sync, so "sign out" and "wipe" cannot be separated. Callers must warn the
  /// user first — see `SettingsScreen._confirmSignOut`.
  ///
  /// [endSession] drops the Firebase/Google session and runs *before* the
  /// wipe: if the process dies in between, the device comes back signed out
  /// with the pending-wipe flag set, and the next sign-in finishes the wipe
  /// before it pushes anything.
  Future<void> signOutAndWipeLocalData(
    Future<void> Function() endSession,
  ) async {
    _processTimer?.cancel();
    _wiping = true;
    try {
      // The flag goes down first, before anything else can fail or be killed.
      // It has to cover dropping the session and the drain below, not just the
      // delete: a process killed anywhere past this line comes back with the
      // wipe still owed, and nothing may push until it is done.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(pendingWipeKey, true);

      try {
        await endSession();
      } catch (e) {
        debugPrint('SyncNotifier: ending the session failed: $e');
      }

      // Let an in-flight sync unwind — its session is gone, so it fails fast —
      // rather than letting its writes land after the tables are emptied.
      for (var i = 0; i < 50 && _syncing; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      // A sync that outlived the wait can still be inserting rows and writing
      // photo files behind the delete, so the device is not provably clean.
      // Wipe anyway, but keep the flag: nothing may clear it until that sync
      // is gone and a later wipe has run clean.
      if (_syncing) _staleSyncInFlight = true;

      await _wipeLocalData();
      state = const SyncState(status: SyncStatus.disabled, pendingCount: 0);
    } catch (e) {
      await _publishOwedWipe();
      rethrow;
    } finally {
      _wiping = false;
    }
  }

  /// Ends the session of an account that does not own this device, without
  /// touching the data.
  ///
  /// Sign-out is destructive because the local pottery is *yours* — that is
  /// ruling 1. On a device standing refused for another account, none of it
  /// is, so wiping here would destroy the owner's work on their behalf. This
  /// is the "sign in as the owner" way out of the read-only lock: drop the
  /// session, keep everything, and let the owner sign in.
  Future<void> endForeignSession(Future<void> Function() endSession) async {
    _processTimer?.cancel();
    try {
      await endSession();
    } catch (e) {
      debugPrint('SyncNotifier: ending the foreign session failed: $e');
    }
    state = const SyncState(status: SyncStatus.disabled);
  }

  /// Erases what this device still holds, at the user's explicit request.
  ///
  /// This is the deliberate way out of both locked states, and it destroys
  /// data, so it must only ever be reached from a confirmation the user
  /// answered — `DeviceLockedScreen._eraseDevice`, the single surface that
  /// owns it. Both states lock the router, so Settings is not reachable on a
  /// device in either one.
  /// A destructive action the user has already confirmed never ends in
  /// silence, so this reports what happened rather than returning void.
  Future<EraseLocalDataResult> eraseLocalDataNow() async {
    if (_syncing || _wiping) {
      debugPrint('SyncNotifier: explicit erase refused, the device is busy');
      return EraseLocalDataResult.busy;
    }
    _processTimer?.cancel();
    _wiping = true;
    try {
      await _wipeLocalData();
      state = const SyncState(status: SyncStatus.idle, pendingCount: 0);
    } on LocalPhotoWipeException catch (e) {
      await _recordFailedErase(e);
      return EraseLocalDataResult.photosSurvived;
    } catch (e) {
      await _recordFailedErase(e);
      return EraseLocalDataResult.failed;
    } finally {
      _wiping = false;
    }
    // The device is clean and unclaimed now, so the signed-in account can take
    // it over and back up normally.
    await syncNow();
    return EraseLocalDataResult.erased;
  }

  /// Leaves a failed erase owed and visible: the lock stays up and the sync
  /// status carries the error, whichever part of the wipe it was that failed.
  Future<void> _recordFailedErase(Object error) async {
    debugPrint('SyncNotifier: explicit erase failed: $error');
    await _publishOwedWipe();
    state = state.copyWith(
      status: SyncStatus.error,
      errorMessage: error.toString(),
    );
  }

  /// Deletes every local store, flagged so an interruption is recoverable.
  ///
  /// The single place the pending-wipe flag is ever cleared. A wipe running
  /// alongside [_staleSyncInFlight] deletes as usual but leaves the flag set,
  /// because that sync can write more rows after this delete has passed them;
  /// the wipe that runs once it has unwound is the one allowed to clear it.
  Future<void> _wipeLocalData() async {
    final staleSync = _staleSyncInFlight;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(pendingWipeKey, true);
    await _queue.clear();
    await _syncService.deleteLocalData();
    // deleteLocalData clears the stamp and the refusal, so nobody owns this
    // device now and there is nothing left here to be refused over.
    _publishLocalDataOwner(null);
    _publishDeviceContested(false);
    if (!staleSync) await prefs.remove(pendingWipeKey);
    await _publishOwedWipe();
  }

  /// Publishes whether a wipe is *owed* — outstanding with nothing currently
  /// attempting it — which is what the read-only lock is about.
  ///
  /// Only ever called once a wipe attempt has settled. The flag on disk goes
  /// down *before* the delete, so a process killed mid-wipe comes back owing
  /// one; the lock must not follow it there, because a wipe in flight is the
  /// user's confirmed action still running, and locking then redirects the
  /// router away from the screen that owes them the result. A launch that
  /// finds the flag already set is the owed case, and `main` seeds it.
  Future<void> _publishOwedWipe() async {
    final prefs = await SharedPreferences.getInstance();
    _publishPendingWipe(prefs.getBool(pendingWipeKey) == true);
  }

  /// Claims this device for [uid], or refuses it — the one boundary every
  /// push path goes through.
  ///
  /// Both checks and the ownership claim live here together on purpose: an
  /// earlier version claimed the device in [syncNow] only, so a debounced
  /// [_pushQueue] that won the race uploaded for an account without ever
  /// stamping it, and the next account inherited an unowned device. The
  /// invariant is that a device which has pushed for an account is stamped
  /// with it, whichever path did the pushing.
  Future<bool> _claimOrBlock(String uid) async {
    if (await _blockedByPendingWipe()) return true;
    final foreign = await _blockedByForeignLocalData(uid);
    if (foreign.blocked) return true;
    // Allowed to sync, so this account owns what is on the device from here
    // on. Claiming it before the push matters: if the process dies mid-sync,
    // the stamp is already correct.
    //
    // Only when it is not already ours, though. This runs on every debounced
    // push — 500ms after any edit — and the platform stores rewrite the whole
    // backing file per write, so an unguarded claim meant a disk write per
    // sync for a value that changes at most once per account.
    if (foreign.owner != uid) {
      await _syncService.setLocalDataOwner(uid);
      _publishLocalDataOwner(uid);
    }
    return false;
  }

  /// Mirrors the persisted stamp into [localDataOwnerProvider], which the lock
  /// reads synchronously.
  ///
  /// All three publishers are reached from work that is deliberately not
  /// awaited — the constructor's refresh, a resumed wipe, a debounced push —
  /// so any of them can land after the container holding these providers has
  /// gone. Writing to a disposed container throws, which would surface as the
  /// sync failing rather than as what it is: nobody left to tell.
  void _publishLocalDataOwner(String? uid) {
    if (!mounted) return;
    _ref.read(localDataOwnerProvider.notifier).state = uid;
  }

  /// Mirrors the persisted refusal into [deviceContestedProvider].
  void _publishDeviceContested(bool contested) {
    if (!mounted) return;
    _ref.read(deviceContestedProvider.notifier).state = contested;
  }

  /// Mirrors the persisted pending-wipe flag into [pendingLocalWipeProvider].
  void _publishPendingWipe(bool pending) {
    if (!mounted) return;
    _ref.read(pendingLocalWipeProvider.notifier).state = pending;
  }

  /// Records that [uid]'s account survived the deletion [uid] confirmed.
  ///
  /// The slot holds one uid. Claiming it for the account in front of the user
  /// can displace another account's outstanding deletion, which is the honest
  /// limit of a single record — but only the account being displaced could
  /// have put it there, and it is the one now asking.
  Future<void> _recordAccountDeletionOwed(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SyncService.accountDeletionOwedKey, uid);
    if (!mounted) return;
    _ref.read(accountDeletionOwedProvider.notifier).state = uid;
  }

  /// Releases the record, and only when it is [uid]'s own.
  ///
  /// There is deliberately no way to ask for the record to be cleared without
  /// saying whose it is. A deletion that finally goes through settles the
  /// account it deleted and nothing else: another account's outstanding
  /// deletion is not this one's to forget, and forgetting it would leave the
  /// account standing with nothing anywhere recording that it is.
  Future<void> _clearAccountDeletionOwedFor(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(SyncService.accountDeletionOwedKey) != uid) return;
    await prefs.remove(SyncService.accountDeletionOwedKey);
    if (!mounted) return;
    _ref.read(accountDeletionOwedProvider.notifier).state = null;
  }

  /// Whether this device's data belongs to an account other than [uid].
  ///
  /// This is what the captain's ruling for the *involuntary* sign-out path
  /// buys: `AuthNotifier._init` drops the session when `reload()` fails or
  /// times out — a revoked token, but just as easily an offline launch — and
  /// deliberately destroys nothing, because the user never asked to lose
  /// anything. The stamp left behind is what stops the next account pushing
  /// the previous one's pieces into its own cloud tree. The way out is to
  /// sign back in as the owner, or to erase the device on purpose.
  /// Returns the stamp it read alongside the decision, so the caller can tell
  /// "nobody owns this device" from "we already do" without a second read.
  Future<({bool blocked, String? owner})> _blockedByForeignLocalData(
    String uid,
  ) async {
    final owner = await _syncService.getLocalDataOwner();
    _publishLocalDataOwner(owner);
    if (owner == null || owner == uid) {
      return (blocked: false, owner: owner);
    }
    debugPrint('SyncNotifier: sync blocked, local data belongs to $owner');
    state = state.copyWith(status: SyncStatus.blocked);
    return (blocked: true, owner: owner);
  }

  /// Whether an owed local wipe has to stop this device from pushing.
  ///
  /// Every push path goes through here, not just sign-in, because the manual
  /// "Sync Now" button reaches [syncNow] and the debounce reaches [_pushQueue]
  /// without one. While the flag is set the rows on this device may still be
  /// the signed-out account's, and pushing them would put them in the current
  /// account's cloud tree. The owed wipe is deliberately *not* retried here:
  /// a delete on the push path would fire on the debounce after any edit and
  /// destroy the current account's work. It is retried at an auth transition,
  /// from [retryOwedWipe] when the lock screen opens on it, and from the
  /// confirmed [eraseLocalDataNow] — nowhere else.
  Future<bool> _blockedByPendingWipe() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(pendingWipeKey) != true) return false;
    debugPrint('SyncNotifier: sync blocked, a local data wipe is still owed');
    state = state.copyWith(status: SyncStatus.blocked);
    return true;
  }

  /// Retries a wipe the user confirmed and did not get, without asking again.
  ///
  /// `DeviceLockedScreen` calls this when it opens for
  /// [DeviceLockReason.pendingWipe], which is the only place the owed wipe can
  /// still be reached: the flag locks the router on the first frame, so the
  /// shell never mounts and the auth transition that used to carry the retry
  /// never runs. A transient failure — a photo file briefly locked — therefore
  /// heals on its own again, and the erase is still there when it does not.
  /// This is a mount, not the push path: no delete ever fires behind an edit.
  Future<void> retryOwedWipe() => _finishInterruptedWipe();

  /// Re-runs a wipe that was started but never confirmed complete.
  ///
  /// Cheap in the normal case: one preference read and nothing else.
  Future<void> _finishInterruptedWipe() {
    // An explicit sign-out wipe already owns the flag; a second pass would
    // race its delete and could clear the flag before it is finished.
    if (_wiping) return Future<void>.value();
    return _wipeInFlight ??= _finishInterruptedWipeOnce().whenComplete(() {
      _wipeInFlight = null;
    });
  }

  Future<void> _finishInterruptedWipeOnce() async {
    final prefs = await SharedPreferences.getInstance();
    // Re-check `_wiping` here, not only on the way in: a wipe can start while
    // this is still waiting on preferences, and it raises the flag it owns
    // only after its own first await.
    if (_wiping || prefs.getBool(pendingWipeKey) != true) return;
    debugPrint('SyncNotifier: finishing an interrupted local data wipe');
    try {
      await _wipeLocalData();
    } catch (e) {
      // Leave the flag set: [_blockedByPendingWipe] then refuses every push
      // until a later attempt succeeds, rather than uploading what survived.
      debugPrint('SyncNotifier: resumed wipe failed, still pending: $e');
      await _publishOwedWipe();
    }
  }

  Future<DeleteAllDataResult> deleteAllData() async {
    if (_syncing || _wiping) {
      debugPrint('SyncNotifier: account deletion refused, the device is busy');
      return DeleteAllDataResult.busy;
    }
    _syncing = true;
    // This owns the wipe too, so a resumed one does not run alongside it and
    // clear the flag out from under the delete below.
    _wiping = true;
    state = state.copyWith(status: SyncStatus.syncing);

    // Declared outside the try so the outer catch can still say what actually
    // happened. Inside it, every unexpected throw past the cloud delete came
    // back as "nothing was deleted" — the same lie as reporting a live account
    // deleted, only mirrored, and just as impossible for the user to act on.
    var cloudDeleted = false;
    var accountSurvived = false;
    var localWiped = false;
    var sessionEnded = false;

    try {
      final auth = _ref.read(authProvider);

      // Delete cloud data and account only if signed in
      if (auth.isSignedIn && auth.uid != null) {
        await _syncService.deleteCloudData(auth.uid!);
        cloudDeleted = true;

        // A failure here is almost always 'requires-recent-login'. It must not
        // be swallowed: telling someone their account is deleted when it still
        // exists is the one thing this report exists to prevent.
        try {
          await _deleteAuthAccount();
        } catch (e) {
          debugPrint('SyncNotifier: Firebase account deletion failed: $e');
          accountSurvived = true;
        }
        // Persisted before anything else can redirect the user away from the
        // message about to be shown. A confirmed deletion that half-failed is
        // not reported once and forgotten — and a deletion that finally went
        // through is what settles it, for the account it deleted.
        if (accountSurvived) {
          await _recordAccountDeletionOwed(auth.uid!);
        } else {
          await _clearAccountDeletionOwedFor(auth.uid!);
        }
      }

      // Always delete local data. Past this point the cloud side is already
      // gone, so a failure here is partial, not "nothing was deleted".
      try {
        await _wipeLocalData();
        localWiped = true;
      } catch (e) {
        debugPrint('SyncNotifier: deleteAllData local wipe failed: $e');
        await _publishOwedWipe();
        state = state.copyWith(
          status: SyncStatus.error,
          errorMessage: e.toString(),
        );
        if (cloudDeleted) {
          // Never report the account gone when it is not: a live account
          // described as deleted is the one thing the caller can act on and
          // will not, because it has been told there is nothing left to do.
          // And when it *is* gone, the session goes with it — see
          // [_endDeletedAccountSession] — while a surviving account keeps its
          // session, which is what lets the lock screen say it survived.
          if (!accountSurvived) {
            await _endDeletedAccountSession();
            sessionEnded = true;
          }
          return accountSurvived
              ? DeleteAllDataResult.accountAndLocalDataSurvived
              : DeleteAllDataResult.localDataSurvived;
        }
        rethrow;
      }

      // Sign out locally
      await _ref.read(authProvider.notifier).signOut();
      sessionEnded = true;
      state = const SyncState(status: SyncStatus.disabled, pendingCount: 0);
      return accountSurvived
          ? DeleteAllDataResult.accountSurvived
          : DeleteAllDataResult.deleted;
    } catch (e) {
      debugPrint('SyncNotifier: deleteAllData failed: $e');
      state = state.copyWith(
        status: SyncStatus.error,
        errorMessage: e.toString(),
      );
      // Only "nothing was deleted" when nothing was. Past the cloud delete the
      // outcome is partial, and which part survived depends on how far it got:
      // a throw while recording the owed deletion leaves the local library
      // standing, while one from the closing sign-out leaves it already gone.
      if (!cloudDeleted) return DeleteAllDataResult.failed;
      if (!accountSurvived && !sessionEnded) await _endDeletedAccountSession();
      if (!localWiped) {
        return accountSurvived
            ? DeleteAllDataResult.accountAndLocalDataSurvived
            : DeleteAllDataResult.localDataSurvived;
      }
      return accountSurvived
          ? DeleteAllDataResult.accountSurvived
          : DeleteAllDataResult.deleted;
    } finally {
      // Clear the stale-sync marker too: leaving it set would make the next
      // wipe keep an already-satisfied flag, and refuse the next sign-in once
      // for no reason.
      _staleSyncInFlight = false;
      _wiping = false;
      _syncing = false;
    }
  }

  /// Ends the local session once Firebase has deleted the account behind it.
  ///
  /// `User.delete()` signs the SDK out as it goes, so from that point the
  /// app's own session names a user that no longer exists. Left standing, it
  /// puts the album back on screen once an owed wipe finally succeeds, and the
  /// first push from there stamps the device for the dead uid — a stamp no
  /// account can ever match again, which locks the next sign-in out for good.
  /// With no session there is no push, so the stamp is never written.
  ///
  /// Guarded so a failure here cannot change what the caller is told about
  /// the cloud data, the account or the local copy.
  Future<void> _endDeletedAccountSession() async {
    try {
      await _ref.read(authProvider.notifier).signOut();
    } catch (e) {
      debugPrint(
        "SyncNotifier: ending the deleted account's session failed: $e",
      );
    }
  }

  @override
  void dispose() {
    _processTimer?.cancel();
    super.dispose();
  }
}

final syncQueueProvider = Provider<SyncQueue>((ref) {
  return SyncQueue();
});

final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(databaseProvider);
  return SyncService(db, FirebaseFirestore.instance, FirebaseStorage.instance);
});

final syncTriggerProvider = Provider<SyncTrigger>((ref) {
  return SyncTrigger(
    ref.watch(syncQueueProvider),
    onEnqueue: () =>
        ref.read(syncStateProvider.notifier).scheduleProcessQueue(),
  );
});

/// The uid this device's local data belongs to, or null when it belongs to
/// nobody yet.
///
/// Synchronous on purpose. It is seeded from preferences before `runApp` and
/// kept current by [SyncNotifier], so it gives the same answer on the very
/// first frame as it does once syncing has run — which is what lets the lock
/// below be trusted at the moment the router needs it, rather than a beat
/// later. An async read here would leave the lock open during resolution, and
/// "open for a moment" is the whole failure mode this exists to prevent.
final localDataOwnerProvider = StateProvider<String?>((ref) => null);

/// Whether this device has been refused for an account and not reclaimed
/// since. Backed by [SyncService.deviceContestedKey].
///
/// Synchronous for the same reason as [localDataOwnerProvider]: it is seeded
/// from preferences before `runApp` and kept current by [SyncNotifier].
final deviceContestedProvider = StateProvider<bool>((ref) => false);

/// Whether a local wipe the user asked for is still owed. Backed by
/// [SyncNotifier.pendingWipeKey], and synchronous for the same reason.
final pendingLocalWipeProvider = StateProvider<bool>((ref) => false);

/// The uid of an account a confirmed deletion removed the cloud tree for but
/// left standing, or null when nothing is outstanding. Backed by
/// [SyncService.accountDeletionOwedKey].
final accountDeletionOwedProvider = StateProvider<String?>((ref) => null);

/// Whether the account signed in *here* is the one still waiting to be
/// deleted — the question both screens that report it actually have.
///
/// Scoped to the session because the record is about a cloud account rather
/// than this device. Erasing the device deletes no account, so the record
/// outlives the erase the user is told to do first; and the next account to
/// sign in on the same device must not be told that theirs survived a
/// deletion they never asked for.
final accountDeletionOwedForSessionProvider = Provider<bool>((ref) {
  final owed = ref.watch(accountDeletionOwedProvider);
  if (owed == null) return false;
  return owed == ref.watch(authProvider).uid;
});

/// Every provider `main()` seeds from preferences before `runApp`, in one
/// place so a test can launch the app the way the app launches itself.
///
/// These four are read synchronously by the router on the first frame — the
/// read-only lock and the outstanding-deletion notice both have to be right
/// before anything renders. Seeding them inline at the one call site made the
/// wiring unprovable: a test that supplies a provider from the same
/// preference it then asserts passes whether or not `main` ever reads it, so
/// dropping one here would silently stop a persisted fact surviving a
/// relaunch.
List<Override> deviceStateOverrides(SharedPreferences prefs) {
  return [
    localDataOwnerProvider.overrideWith(
      (ref) => prefs.getString(SyncService.localDataOwnerKey),
    ),
    deviceContestedProvider.overrideWith(
      (ref) => prefs.getBool(SyncService.deviceContestedKey) ?? false,
    ),
    pendingLocalWipeProvider.overrideWith(
      (ref) => prefs.getBool(SyncNotifier.pendingWipeKey) ?? false,
    ),
    accountDeletionOwedProvider.overrideWith(
      (ref) => prefs.getString(SyncService.accountDeletionOwedKey),
    ),
  ];
}

/// Whether some account already has a stake in what is on this device.
///
/// The router holds on this while auth is still resolving, rather than letting
/// the album mount and run the owner's query on a device that may turn out to
/// be refused. On a device nobody has claimed there is nothing to be wrong
/// about, so it passes straight through and the album keeps its head start.
final deviceStampedProvider = Provider<bool>((ref) {
  return ref.watch(localDataOwnerProvider) != null ||
      ref.watch(deviceContestedProvider) ||
      ref.watch(pendingLocalWipeProvider);
});

/// Why this device is locked read-only, or null when it is not.
///
/// Derived entirely from *persisted* state — the owner stamp, the refusal
/// marker and the pending-wipe flag — never from [SyncStatus]. Status is
/// transient, and an earlier version of this read it directly: a failed erase
/// flipped the status to `error`, the lock silently dropped, and the router
/// put a refused account on the owner's album — writable — where a delete
/// would later be pushed under the owner's name. None of the three can be
/// cleared by a status transition, by leaving the session, or by a frame
/// rendering before the first async claim.
///
/// A session-less (local-only) launch locks only on a device that has already
/// refused somebody. Both the owner opening the app offline and a refused
/// account relaunching after force-quitting the lock screen arrive with no
/// uid, so nothing derivable from the session tells them apart — and ruling 2
/// requires the first to keep working. The refusal marker is what separates
/// them.
final deviceLockReasonProvider = Provider<DeviceLockReason?>((ref) {
  // A wipe the user asked for and did not get leaves the signed-out account's
  // whole library on the device. They asked for it destroyed, so it must not
  // be browsable and editable by the next person holding the phone while the
  // wipe stays owed — the lock screen offers the erase that resolves it.
  if (ref.watch(pendingLocalWipeProvider)) return DeviceLockReason.pendingWipe;

  final auth = ref.watch(authProvider);
  if (auth.uid == null) {
    return ref.watch(deviceContestedProvider)
        ? DeviceLockReason.foreignLocalData
        : null;
  }

  final owner = ref.watch(localDataOwnerProvider);
  if (owner != null && owner != auth.uid) {
    return DeviceLockReason.foreignLocalData;
  }
  return null;
});

/// Persists the refusal marker at the moment the lock is *decided*, and drops
/// it the moment the owner is back.
///
/// It cannot live on the push path. `SyncNotifier` is only constructed once
/// something reads [syncStateProvider], which on the primary refusal — B signs
/// in, the stamp sends them straight to `/device-locked` — never happens: the
/// shell does not mount on the lock screen, on sign-in or on the holding
/// route, so no claim is ever attempted and the refusal went unrecorded. The
/// same gap swallowed the mirror case, where a process killed before the
/// owner's first claim left a stale refusal locking the owner out of their own
/// device, against ruling 2. Deriving both from the lock reason itself means
/// they happen wherever the decision does, which is everywhere it matters.
///
/// Kept alive by `routerProvider`, which is where the lock is enforced and
/// which exists for as long as the app does.
final deviceRefusalRecorderProvider = Provider<void>((ref) {
  var alive = true;
  ref.onDispose(() => alive = false);

  void record(DeviceLockReason? reason) {
    if (!alive) return;
    // A request to leave belongs to the lock that was on screen when it was
    // made. Once that lock changes or lifts, the request has been answered or
    // overtaken — leaving it set would let it speak for whatever comes next,
    // including a refusal the user has not been shown yet.
    if (ref.read(lockExitRequestedProvider) != reason) {
      ref.read(lockExitRequestedProvider.notifier).state = null;
    }
    if (reason == DeviceLockReason.foreignLocalData) {
      if (ref.read(deviceContestedProvider)) return;
      ref.read(deviceContestedProvider.notifier).state = true;
      unawaited(_writeDeviceContested(true));
      return;
    }
    // Only the owner may lift a refusal. A session-less launch cannot, or the
    // refused account would clear it simply by force-quitting and reopening.
    final uid = ref.read(authProvider).uid;
    final owner = ref.read(localDataOwnerProvider);
    if (uid == null || (owner != null && owner != uid)) return;
    if (!ref.read(deviceContestedProvider)) return;
    ref.read(deviceContestedProvider.notifier).state = false;
    unawaited(_writeDeviceContested(false));
  }

  ref.listen<DeviceLockReason?>(
    deviceLockReasonProvider,
    (_, reason) => record(reason),
  );
  // The first answer counts as much as any later one — a refusal is usually
  // already true on the frame the app starts — but a provider may not write to
  // another one while it is building, so the opening read waits a microtask.
  // Nothing is lost: the lock itself reads the stamp directly and is right on
  // that first frame; only the record of it is a beat behind.
  Future.microtask(() {
    if (!alive) return;
    record(ref.read(deviceLockReasonProvider));
  });
});

/// Writes the marker straight to preferences rather than through
/// [SyncService], whose constructor would drag the database into the router.
/// The key stays declared there, and `deleteLocalData` still clears it, so an
/// erase lifts the refusal along with everything else.
Future<void> _writeDeviceContested(bool contested) async {
  final prefs = await SharedPreferences.getInstance();
  if (contested) {
    await prefs.setBool(SyncService.deviceContestedKey, true);
  } else {
    await prefs.remove(SyncService.deviceContestedKey);
  }
}

/// Whether this device is locked read-only. See [deviceLockReasonProvider],
/// which also says which of the two situations the user is in — they need
/// different words and a different way out.
final deviceLockedProvider = Provider<bool>((ref) {
  return ref.watch(deviceLockReasonProvider) != null;
});

/// Which lock, if any, the user has asked to leave for the sign-in screen.
///
/// Deliberately in memory only. `routerProvider` watches the auth status, so
/// signing out mints a fresh `GoRouter` at its initial location and throws
/// away any navigation the lock screen had just performed — the way out has to
/// be something the *redirect* can still see afterwards, not a push that the
/// rebuild discards.
///
/// Not persisting it is the point rather than an economy: the detour lasts as
/// long as the session that asked for it, so force-quitting comes back to the
/// lock and its explanation instead of to a bare sign-in screen. It grants
/// nothing on its own — a locked device stays locked, and the redirect only
/// consults it while there is no session to write with.
///
/// It records the *reason* rather than a bare yes so that consent given for one
/// lock cannot answer for another. Only the foreign-pottery lock offers this
/// way out; the owed-wipe lock deliberately offers the erase alone, because
/// finishing the wipe is the only way out of it. Held as a flag, an earlier
/// tap on a foreign-pottery lock sent a *later* owed wipe to the sign-in screen
/// instead of the lock screen — past the only surface that retries the wipe and
/// offers that erase.
final lockExitRequestedProvider = StateProvider<DeviceLockReason?>(
  (ref) => null,
);

/// Whether continuing without an account would land on a device that already
/// holds somebody's pottery. "Skip for now" is hidden then: it is the one door
/// into a writable session that no lock covers, and leaving it open would give
/// a refused account unrestricted access to the owner's pottery without
/// erasing and without the owner ever signing back in.
///
/// It answers off [deviceStampedProvider] rather than the owner stamp alone,
/// because sign-in is reachable while the device is locked — the owner
/// returning is one of the two ways out — so the stamp is no longer the only
/// state that has to close this door. A wipe that failed *after* clearing the
/// stamp leaves an owed wipe and no owner, and on the stamp alone the button
/// would come back and walk into the very library the user confirmed for
/// destruction.
final skipSignInAllowedProvider = Provider<bool>((ref) {
  return !ref.watch(deviceStampedProvider);
});

/// The one place a material is created and queued for backup. See
/// [MaterialWriter] for why the two steps cannot be separated.
final materialWriterProvider = Provider<MaterialWriter>((ref) {
  return MaterialWriter(
    ref.watch(databaseProvider).materialsDao,
    ref.watch(syncTriggerProvider),
  );
});

final syncStateProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(
    ref,
    ref.watch(syncQueueProvider),
    ref.watch(syncServiceProvider),
  );
});
