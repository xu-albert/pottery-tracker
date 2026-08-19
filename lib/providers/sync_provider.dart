import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  /// this: the way out is to sign back in as the owner, or to erase the
  /// device deliberately.
  foreignLocalData,
}

/// What an explicit, user-confirmed erase actually did.
///
/// The user has already answered a destructive confirmation by the time this
/// is produced, so every outcome has to be reportable — silently doing nothing
/// leaves them believing the device was erased when it was not.
enum EraseLocalDataResult {
  /// The device was erased.
  erased,

  /// Nothing was erased: a sync or another wipe held the device.
  busy,

  /// The erase ran and failed. `SyncState.errorMessage` says why.
  failed,
}

class SyncState {
  final SyncStatus status;
  final int pendingCount;
  final DateTime? lastSyncedAt;
  final String? errorMessage;

  /// Set only when [status] is [SyncStatus.blocked].
  final SyncBlockedReason? blockedReason;

  /// How many rows are being withheld from the backup because a session this
  /// device refused wrote them.
  ///
  /// Deliberately not folded into [pendingCount]: those rows are on their way
  /// up, these are refused, and a device with withheld rows is never fully
  /// backed up no matter how empty the queue is.
  final int withheldCount;

  const SyncState({
    this.status = SyncStatus.disabled,
    this.pendingCount = 0,
    this.lastSyncedAt,
    this.errorMessage,
    this.blockedReason,
    this.withheldCount = 0,
  });

  SyncState copyWith({
    SyncStatus? status,
    int? pendingCount,
    DateTime? lastSyncedAt,
    String? errorMessage,
    SyncBlockedReason? blockedReason,
    int? withheldCount,
  }) {
    return SyncState(
      status: status ?? this.status,
      pendingCount: pendingCount ?? this.pendingCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      errorMessage: errorMessage,
      blockedReason: blockedReason,
      withheldCount: withheldCount ?? this.withheldCount,
    );
  }
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

  /// True only while [_pushQueue] holds [_syncing].
  ///
  /// A drain is not a substitute for a full sync — it pushes queued rows and
  /// never pulls — so a [syncNow] that stands down for one has to be
  /// remembered rather than dropped.
  bool _drainingQueue = false;

  /// Set when a [syncNow] bowed out because a drain held the device. The drain
  /// runs it on its way out, so a sign-in's pull is never lost to the 500ms
  /// debounce happening to fire first.
  bool _fullSyncOwed = false;

  /// Whether what is owed is a *forced* full sync — the sync tile's long
  /// press, which is the only "re-upload everything" affordance there is, and
  /// which races a drain scheduled 500ms after any edit. Replaying it as an
  /// ordinary sync would quietly do something other than what was asked for,
  /// so once a forced sync is owed it stays forced no matter what else queues
  /// up behind it.
  bool _owedSyncForced = false;
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
  }

  Future<void> _onAuthChanged(String uid) async {
    // Before this uid can push anything, make sure no earlier account's data
    // is still lying around from a wipe that was cut short.
    await _finishInterruptedWipe();
    state = state.copyWith(status: SyncStatus.idle);
    await _refreshCounts();
    await syncNow();
  }

  Future<void> _refreshCounts() async {
    final count = await _queue.pendingCount;
    final withheld = await _syncService.getForeignRowIds();
    state = state.copyWith(pendingCount: count, withheldCount: withheld.length);
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
    _drainingQueue = true;
    try {
      if (await _claimOrBlock(auth.uid!)) return;
      await _processQueueInternal(auth.uid!);
      await _refreshCounts();
      // Only the queue has been drained here. While a full sync is still owed
      // nothing has been pulled, so reporting "backed up" would name a backup
      // that has not happened — leave the final word to the owed sync below.
      if (state.status != SyncStatus.error && !_fullSyncOwed) {
        state = state.copyWith(
          status: SyncStatus.idle,
          lastSyncedAt: DateTime.now(),
        );
      }
    } catch (e) {
      debugPrint('SyncNotifier: push failed: $e');
      await _refreshCounts();
      state = state.copyWith(
        status: SyncStatus.error,
        errorMessage: e.toString(),
      );
    } finally {
      _staleSyncInFlight = false;
      _drainingQueue = false;
      _syncing = false;
      if (_fullSyncOwed) await syncNow(forceFullSync: _owedSyncForced);
    }
  }

  Future<void> syncNow({bool forceFullSync = false}) async {
    final auth = _ref.read(authProvider);
    if (!auth.isSignedIn || auth.uid == null) {
      state = const SyncState(status: SyncStatus.disabled);
      return;
    }
    if (_syncing || _wiping) {
      if (_drainingQueue) {
        _fullSyncOwed = true;
        if (forceFullSync) _owedSyncForced = true;
      }
      return;
    }
    _syncing = true;
    // Committed to running now, so whatever was owed is about to be paid.
    _fullSyncOwed = false;
    _owedSyncForced = false;

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
        withheldCount: (await _syncService.getForeignRowIds()).length,
        lastSyncedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('SyncNotifier: sync failed: $e');
      await _refreshCounts();
      state = state.copyWith(
        status: SyncStatus.error,
        errorMessage: e.toString(),
      );
    } finally {
      _staleSyncInFlight = false;
      _syncing = false;
    }
  }

  Future<void> _processQueueInternal(String uid) async {
    final entries = await _queue.getAll();
    final foreignRows = await _syncService.getForeignRowIds();
    for (final entry in entries) {
      // Work from a session this device refused, or work on a row such a
      // session has touched. Neither may reach [uid]'s cloud tree: the first
      // is plainly not theirs, and the second is a row whose current contents
      // were written by somebody else. Dropping the entry — the row itself
      // stays on the device — is what stops it being resurrected into a later
      // drain, and [SyncService.rememberForeignRowIds] has already recorded
      // the ids so the full-push branch withholds them too.
      if ((entry.uid != null && entry.uid != uid) ||
          foreignRows.contains(entry.entityId)) {
        debugPrint(
          'SyncNotifier: withholding ${entry.operation} for ${entry.entityId} '
          '— written by ${entry.uid ?? 'another account'}',
        );
        await _queue.remove(entry);
        continue;
      }

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

  /// Erases what this device still holds, at the user's explicit request.
  ///
  /// This is the deliberate way out of both blocked states, and it destroys
  /// data, so it must only ever be reached from a confirmation the user
  /// answered — see `SettingsScreen._confirmEraseLocalData`.
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
    if (!staleSync) await prefs.remove(pendingWipeKey);
  }

  /// Whether this device is refused for [uid] — and, when it is not, the one
  /// place that claims the device for it.
  ///
  /// Both push paths go through here, so the invariant "a device that has
  /// pushed for uid X is stamped X" holds structurally rather than by the
  /// caller remembering to stamp. Splitting the checks from the claim is what
  /// left a hole: the debounced [_pushQueue] can win the race against the
  /// sign-in [syncNow] — which then returns on `_syncing` and never runs its
  /// stamp — so the device would upload for an account it was not marked as
  /// owning, and a later involuntary sign-out would let the next account push
  /// those same rows into its own cloud tree.
  ///
  /// Claiming before the push also means a process that dies mid-push comes
  /// back with the stamp already correct.
  Future<bool> _claimOrBlock(String uid) async {
    if (await _blockedByPendingWipe()) return true;
    if (await _blockedByForeignLocalData(uid)) {
      // Refused, but still the account at the keyboard. From here a write made
      // with no session is this account's rather than the owner's, and it
      // stays that way across relaunches — which is exactly when the session
      // goes away. Only the foreign-owner refusal contests the device: an owed
      // wipe refuses the owner too, and everything is about to be deleted.
      await _syncService.setContestedBy(uid);
      return true;
    }
    await _syncService.setLocalDataOwner(uid);
    await _recordForeignRows(uid);
    // The owner has the device back. Writes made from now on are theirs again;
    // entries already stamped keep the attribution they were given.
    await _syncService.clearContestedBy();
    return false;
  }

  /// Notes a write that has just been queued, so the record of which rows are
  /// not the owner's stays true as the owner keeps working.
  ///
  /// A row is withheld because its contents were written by an account this
  /// device refused. Once the owner writes that row itself the justification
  /// is gone, so the row is released — here, at the moment of the write, which
  /// is the only point that can tell an owner's write *after* reclaiming the
  /// device from one made before losing it. Queue order cannot: an entry keeps
  /// its first position when a later write merges into it.
  ///
  /// Nobody but the owner can release a row: a refused account's writes are
  /// stamped with its own uid, and on a contested device so are its
  /// session-less ones.
  Future<void> noteLocalWrite(SyncQueueEntry entry) async {
    final writer = entry.uid;
    if (writer == null) return;
    if (await _syncService.getLocalDataOwner() != writer) return;
    await _syncService.releaseForeignRowId(entry.entityId);
  }

  /// Records every row this device holds that a session other than [uid]
  /// wrote, before either push path gets to run.
  ///
  /// The sync queue is the record of every local write — no DAO write reaches
  /// the device without one — so its entries are what makes a mixed device
  /// knowable at all. They are persisted through [SyncService] because a
  /// successful sync clears the queue, and because `pushAllLocal` reads the
  /// database rather than the queue and needs the same list.
  Future<void> _recordForeignRows(String uid) async {
    final foreign = (await _queue.getAll())
        .where((e) => e.uid != null && e.uid != uid)
        .map((e) => e.entityId)
        .toSet();
    if (foreign.isEmpty) return;
    await _syncService.rememberForeignRowIds(foreign);
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
  /// account's cloud tree. Retries the wipe first, so a transient failure
  /// heals on the next sync attempt instead of wedging the device.
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

  Future<void> deleteAllData() async {
    if (_syncing || _wiping) return;
    _syncing = true;
    // This owns the wipe too, so a resumed one does not run alongside it and
    // clear the flag out from under the delete below.
    _wiping = true;
    state = state.copyWith(status: SyncStatus.syncing);

    try {
      final auth = _ref.read(authProvider);

      // Delete cloud data and account only if signed in
      if (auth.isSignedIn && auth.uid != null) {
        await _syncService.deleteCloudData(auth.uid!);

        // Delete the Firebase Auth account
        try {
          await FirebaseAuth.instance.currentUser?.delete();
        } catch (e) {
          debugPrint('SyncNotifier: Firebase account deletion failed: $e');
        }
      }

      // Always delete local data
      await _wipeLocalData();

      // Sign out locally
      await _ref.read(authProvider.notifier).signOut();
      state = const SyncState(status: SyncStatus.disabled, pendingCount: 0);
    } catch (e) {
      debugPrint('SyncNotifier: deleteAllData failed: $e');
      state = state.copyWith(
        status: SyncStatus.error,
        errorMessage: e.toString(),
      );
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
    currentUid: () async {
      final uid = ref.read(authProvider).uid;
      if (uid != null) return uid;
      // No session. Session-less writes belong to whoever owns the device,
      // unless somebody has been refused here — then they are that account's.
      return ref.read(syncServiceProvider).getContestedBy();
    },
    onRowWritten: (entry) =>
        ref.read(syncStateProvider.notifier).noteLocalWrite(entry),
    onEnqueue: () =>
        ref.read(syncStateProvider.notifier).scheduleProcessQueue(),
  );
});

final syncStateProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(
    ref,
    ref.watch(syncQueueProvider),
    ref.watch(syncServiceProvider),
  );
});
