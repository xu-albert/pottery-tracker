import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/sync_queue.dart';
import '../services/sync_service.dart';
import '../services/sync_trigger.dart';
import 'auth_provider.dart';
import 'database_provider.dart';

enum SyncStatus { idle, syncing, error, disabled }

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

class SyncNotifier extends StateNotifier<SyncState> {
  final Ref _ref;
  final SyncQueue _queue;
  final SyncService _syncService;
  bool _syncing = false;
  Timer? _processTimer;

  SyncNotifier(this._ref, this._queue, this._syncService)
    : super(const SyncState()) {
    _ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.isSignedIn && prev?.uid != next.uid) {
        _onAuthChanged(next.uid!);
      } else if (!next.isSignedIn) {
        state = const SyncState(status: SyncStatus.disabled);
      }
    }, fireImmediately: true);
  }

  Future<void> _onAuthChanged(String uid) async {
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
    if (_syncing) return;
    final auth = _ref.read(authProvider);
    if (!auth.isSignedIn || auth.uid == null) return;

    _syncing = true;
    try {
      await _processQueueInternal(auth.uid!);
      await _refreshPendingCount();
      if (state.status != SyncStatus.error) {
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
      _syncing = false;
    }
  }

  Future<void> syncNow({bool forceFullSync = false}) async {
    final auth = _ref.read(authProvider);
    if (!auth.isSignedIn || auth.uid == null) {
      state = const SyncState(status: SyncStatus.disabled);
      return;
    }
    if (_syncing) return;
    _syncing = true;

    final uid = auth.uid!;
    state = state.copyWith(status: SyncStatus.syncing);

    try {
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
      _syncing = false;
    }
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

  Future<void> deleteAllData() async {
    final auth = _ref.read(authProvider);
    if (!auth.isSignedIn || auth.uid == null) return;
    if (_syncing) return;
    _syncing = true;
    state = state.copyWith(status: SyncStatus.syncing);

    try {
      await _syncService.deleteAllData(auth.uid!);
      await _queue.clear();

      // Delete the Firebase Auth account
      try {
        await FirebaseAuth.instance.currentUser?.delete();
      } catch (e) {
        debugPrint('SyncNotifier: Firebase account deletion failed: $e');
        // If requires-recent-login, data is already deleted — sign out anyway
      }

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

final syncStateProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  return SyncNotifier(
    ref,
    ref.watch(syncQueueProvider),
    ref.watch(syncServiceProvider),
  );
});
