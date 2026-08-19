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
/// allowed to push yet. [SyncBlockedReason] says which of the two reasons
/// applies, because the way out differs.
enum SyncStatus { idle, syncing, error, blocked, disabled }

/// Why a device is refusing to push.
enum SyncBlockedReason {
  /// A wipe owed by an explicit sign-out has not finished. The way out is to
  /// let it finish — the user can force it from the sync tile.
  pendingWipe,

  /// The local data belongs to a different account, because a session was
  /// lost involuntarily rather than signed out of. Nothing is deleted for
  /// this, and nothing may be written either: the device is read-only until
  /// the owner signs back in or the user erases it deliberately.
  foreignLocalData,
}

class SyncState {
  final SyncStatus status;
  final int pendingCount;
  final DateTime? lastSyncedAt;
  final String? errorMessage;

  /// Set only when [status] is [SyncStatus.blocked].
  final SyncBlockedReason? blockedReason;

  const SyncState({
    this.status = SyncStatus.disabled,
    this.pendingCount = 0,
    this.lastSyncedAt,
    this.errorMessage,
    this.blockedReason,
  });

  SyncState copyWith({
    SyncStatus? status,
    int? pendingCount,
    DateTime? lastSyncedAt,
    String? errorMessage,
    SyncBlockedReason? blockedReason,
  }) {
    return SyncState(
      status: status ?? this.status,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      errorMessage: errorMessage,
      blockedReason: blockedReason,
    );
  }
}

/// What an explicit erase actually did, so the caller can tell the user.
enum EraseLocalDataResult { erased, busy, failed }

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
}

class SyncNotifier extends StateNotifier<SyncState> {
  /// Set for the duration of a local wipe so an interrupted one (crash, kill,
  /// failed delete) can be finished before anything is ever pushed again.
  @visibleForTesting
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

  SyncNotifier(this._ref, this._queue, this._syncService)
    : super(const SyncState()) {
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
    unawaited(_refreshLocalDataOwner());
  }

  Future<void> _refreshLocalDataOwner() async {
    _publishLocalDataOwner(await _syncService.getLocalDataOwner());
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
  /// This is the deliberate way out of both blocked states, and it destroys
  /// data, so it must only ever be reached from a confirmation the user
  /// answered. There is one per state: an owed wipe is erased from the sync
  /// tile (`SettingsScreen._confirmEraseLocalData`), and a device holding
  /// another account's pottery from the lock screen
  /// (`DeviceLockedScreen._eraseDevice`) — Settings is not reachable at all
  /// while that lock holds.
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
    } catch (e) {
      debugPrint('SyncNotifier: explicit erase failed: $e');
      state = state.copyWith(
        status: SyncStatus.error,
        errorMessage: e.toString(),
      );
      return EraseLocalDataResult.failed;
    } finally {
      _wiping = false;
    }
    // The device is clean and unclaimed now, so the signed-in account can take
    // it over and back up normally.
    await syncNow();
    return EraseLocalDataResult.erased;
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
    // deleteLocalData clears the stamp, so nobody owns this device now.
    _publishLocalDataOwner(null);
    if (!staleSync) await prefs.remove(pendingWipeKey);
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
    if (await _blockedByForeignLocalData(uid)) return true;
    // Allowed to sync, so this account owns what is on the device from here
    // on. Claiming it before the push matters: if the process dies mid-sync,
    // the stamp is already correct.
    await _syncService.setLocalDataOwner(uid);
    _publishLocalDataOwner(uid);
    return false;
  }

  /// Mirrors the persisted stamp into [localDataOwnerProvider], which the lock
  /// reads synchronously.
  void _publishLocalDataOwner(String? uid) {
    _ref.read(localDataOwnerProvider.notifier).state = uid;
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
  Future<bool> _blockedByForeignLocalData(String uid) async {
    final owner = await _syncService.getLocalDataOwner();
    _publishLocalDataOwner(owner);
    if (owner == null || owner == uid) return false;
    debugPrint('SyncNotifier: sync blocked, local data belongs to $owner');
    state = state.copyWith(
      status: SyncStatus.blocked,
      blockedReason: SyncBlockedReason.foreignLocalData,
    );
    return true;
  }

  /// Whether an owed local wipe has to stop this device from pushing.
  ///
  /// Every push path goes through here, not just sign-in, because the manual
  /// "Sync Now" button reaches [syncNow] and the debounce reaches [_pushQueue]
  /// without one. While the flag is set the rows on this device may still be
  /// the signed-out account's, and pushing them would put them in the current
  /// account's cloud tree. The owed wipe is deliberately *not* retried here:
  /// a delete on the push path would fire on the debounce after any edit and
  /// destroy the current account's work. It is retried at an auth transition
  /// and from the confirmed [eraseLocalDataNow], nowhere else.
  Future<bool> _blockedByPendingWipe() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(pendingWipeKey) != true) return false;
    debugPrint('SyncNotifier: sync blocked, a local data wipe is still owed');
    state = state.copyWith(
      status: SyncStatus.blocked,
      blockedReason: SyncBlockedReason.pendingWipe,
    );
    return true;
  }

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

    try {
      final auth = _ref.read(authProvider);

      // Delete cloud data and account only if signed in
      var cloudDeleted = false;
      var accountSurvived = false;
      if (auth.isSignedIn && auth.uid != null) {
        await _syncService.deleteCloudData(auth.uid!);
        cloudDeleted = true;

        // A failure here is almost always 'requires-recent-login'. It must not
        // be swallowed: telling someone their account is deleted when it still
        // exists is the one thing this report exists to prevent.
        try {
          await FirebaseAuth.instance.currentUser?.delete();
        } catch (e) {
          debugPrint('SyncNotifier: Firebase account deletion failed: $e');
          accountSurvived = true;
        }
      }

      // Always delete local data. Past this point the cloud side is already
      // gone, so a failure here is partial, not "nothing was deleted".
      try {
        await _wipeLocalData();
      } catch (e) {
        debugPrint('SyncNotifier: deleteAllData local wipe failed: $e');
        state = state.copyWith(
          status: SyncStatus.error,
          errorMessage: e.toString(),
        );
        if (cloudDeleted) return DeleteAllDataResult.localDataSurvived;
        rethrow;
      }

      // Sign out locally
      await _ref.read(authProvider.notifier).signOut();
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
      return DeleteAllDataResult.failed;
    } finally {
      // Clear the stale-sync marker too: leaving it set would make the next
      // wipe keep an already-satisfied flag, and refuse the next sign-in once
      // for no reason.
      _staleSyncInFlight = false;
      _wiping = false;
      _syncing = false;
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

/// Whether this device is locked read-only because its data is not the
/// signed-in account's to touch.
///
/// Derived from the *persisted* owner stamp against the current session, never
/// from [SyncStatus]. Status is transient, and an earlier version of this
/// provider read it directly: a failed erase flipped the status to `error`,
/// the lock silently dropped, and the router put a refused account on the
/// owner's album — writable — where a delete would later be pushed under the
/// owner's name. The stamp cannot be cleared by a status transition, by
/// leaving the session, or by a frame rendering before the first async claim.
///
/// A session-less (local-only) launch never locks: on a stamped device that is
/// the owner opening the app offline, which ruling 2 requires to keep working.
/// The other way to reach a session-less state — "Skip for now" — is closed on
/// a stamped device instead, so a refused account cannot use it as a way in.
final deviceLockedProvider = Provider<bool>((ref) {
  // A wipe the user asked for and did not get leaves the signed-out account's
  // whole library on the device. They asked for it destroyed, so it must not
  // be browsable and editable by the next person holding the phone while the
  // wipe stays owed — the lock screen offers the erase that resolves it.
  final sync = ref.watch(syncStateProvider);
  if (sync.status == SyncStatus.blocked &&
      sync.blockedReason == SyncBlockedReason.pendingWipe) {
    return true;
  }

  final owner = ref.watch(localDataOwnerProvider);
  if (owner == null) return false;

  final auth = ref.watch(authProvider);
  // Session-less: the owner opening the app offline, not a refused account.
  if (auth.uid == null) return false;
  return auth.uid != owner;
});

/// Whether continuing without an account would land on a device that already
/// belongs to someone else. "Skip for now" is hidden then: it is the one door
/// into a writable session that the owner stamp cannot see, and leaving it
/// open would give a refused account unrestricted access to the owner's
/// pottery without erasing and without the owner ever signing back in.
final skipSignInAllowedProvider = Provider<bool>((ref) {
  return ref.watch(localDataOwnerProvider) == null;
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
