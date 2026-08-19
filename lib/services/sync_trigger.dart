import 'sync_queue.dart';

class SyncTrigger {
  final SyncQueue _queue;
  final void Function()? _onEnqueue;

  /// Resolves who this write belongs to, as the write happens.
  ///
  /// Attribution cannot be recovered at drain time — by then the session that
  /// wrote the row may be long gone — so every enqueue is stamped here, at the
  /// one place all of them pass through. It is asynchronous because the answer
  /// is not always the signed-in uid: on a device that stands refused for
  /// another account, a session-less write belongs to that account rather than
  /// to the owner (`SyncService.getContestedBy`).
  final Future<String?> Function() _currentUid;

  /// Called with each entry once it is queued, so bookkeeping that depends on
  /// who wrote what happens against the same attribution the entry carries.
  final Future<void> Function(SyncQueueEntry entry)? _onRowWritten;

  SyncTrigger(
    this._queue, {
    required Future<String?> Function() currentUid,
    Future<void> Function(SyncQueueEntry entry)? onRowWritten,
    void Function()? onEnqueue,
  }) : _currentUid = currentUid,
       _onRowWritten = onRowWritten,
       _onEnqueue = onEnqueue;

  Future<void> _enqueue(
    SyncOperation operation,
    String entityId, {
    String? extraData,
    List<String>? changedFields,
  }) async {
    final entry = SyncQueueEntry(
      operation: operation,
      entityId: entityId,
      extraData: extraData,
      changedFields: changedFields,
      uid: await _currentUid(),
    );
    await _queue.enqueue(entry);
    await _onRowWritten?.call(entry);
  }

  Future<void> afterPieceWrite(
    String pieceId, {
    List<String>? changedFields,
  }) async {
    await _enqueue(
      SyncOperation.pushPiece,
      pieceId,
      changedFields: changedFields,
    );
    _onEnqueue?.call();
  }

  Future<void> afterPhotoWrite(
    String photoId, {
    bool includeFile = false,
  }) async {
    await _enqueue(SyncOperation.pushPhoto, photoId);
    if (includeFile) {
      await _enqueue(SyncOperation.pushPhotoFile, photoId);
    }
    _onEnqueue?.call();
  }

  Future<void> afterClayWrite(String clayId) async {
    await _enqueue(SyncOperation.pushClay, clayId);
    _onEnqueue?.call();
  }

  Future<void> afterGlazeWrite(String glazeId) async {
    await _enqueue(SyncOperation.pushGlaze, glazeId);
    _onEnqueue?.call();
  }

  Future<void> afterTagWrite(String tagId) async {
    await _enqueue(SyncOperation.pushTag, tagId);
    _onEnqueue?.call();
  }

  Future<void> afterPieceGlazesWrite(String pieceId) async {
    await _enqueue(SyncOperation.pushPieceGlazes, pieceId);
    _onEnqueue?.call();
  }

  Future<void> afterPieceTagsWrite(String pieceId) async {
    await _enqueue(SyncOperation.pushPieceTags, pieceId);
    _onEnqueue?.call();
  }

  Future<void> afterPieceDeletion(String pieceId, List<String> photoIds) async {
    for (final photoId in photoIds) {
      await _enqueue(SyncOperation.deletePhoto, photoId);
    }
    await _enqueue(SyncOperation.deletePiece, pieceId);
    _onEnqueue?.call();
  }

  Future<void> afterPhotoDeletion(String photoId) async {
    await _enqueue(SyncOperation.deletePhoto, photoId);
    _onEnqueue?.call();
  }

  Future<void> afterMaterialDeletion(
    String collection,
    String materialId,
  ) async {
    await _enqueue(
      SyncOperation.deleteMaterial,
      materialId,
      extraData: collection,
    );
    _onEnqueue?.call();
  }
}
