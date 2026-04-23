import 'sync_queue.dart';

class SyncTrigger {
  final SyncQueue _queue;
  final void Function()? _onEnqueue;

  SyncTrigger(this._queue, {void Function()? onEnqueue})
    : _onEnqueue = onEnqueue;

  Future<void> afterPieceWrite(
    String pieceId, {
    List<String>? changedFields,
  }) async {
    await _queue.enqueue(
      SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: pieceId,
        changedFields: changedFields,
      ),
    );
    _onEnqueue?.call();
  }

  Future<void> afterPhotoWrite(
    String photoId, {
    bool includeFile = false,
  }) async {
    await _queue.enqueue(
      SyncQueueEntry(operation: SyncOperation.pushPhoto, entityId: photoId),
    );
    if (includeFile) {
      await _queue.enqueue(
        SyncQueueEntry(
          operation: SyncOperation.pushPhotoFile,
          entityId: photoId,
        ),
      );
    }
    _onEnqueue?.call();
  }

  Future<void> afterClayWrite(String clayId) async {
    await _queue.enqueue(
      SyncQueueEntry(operation: SyncOperation.pushClay, entityId: clayId),
    );
    _onEnqueue?.call();
  }

  Future<void> afterGlazeWrite(String glazeId) async {
    await _queue.enqueue(
      SyncQueueEntry(operation: SyncOperation.pushGlaze, entityId: glazeId),
    );
    _onEnqueue?.call();
  }

  Future<void> afterTagWrite(String tagId) async {
    await _queue.enqueue(
      SyncQueueEntry(operation: SyncOperation.pushTag, entityId: tagId),
    );
    _onEnqueue?.call();
  }

  Future<void> afterPieceGlazesWrite(String pieceId) async {
    await _queue.enqueue(
      SyncQueueEntry(
        operation: SyncOperation.pushPieceGlazes,
        entityId: pieceId,
      ),
    );
    _onEnqueue?.call();
  }

  Future<void> afterPieceTagsWrite(String pieceId) async {
    await _queue.enqueue(
      SyncQueueEntry(operation: SyncOperation.pushPieceTags, entityId: pieceId),
    );
    _onEnqueue?.call();
  }

  Future<void> afterPieceDeletion(String pieceId, List<String> photoIds) async {
    for (final photoId in photoIds) {
      await _queue.enqueue(
        SyncQueueEntry(operation: SyncOperation.deletePhoto, entityId: photoId),
      );
    }
    await _queue.enqueue(
      SyncQueueEntry(operation: SyncOperation.deletePiece, entityId: pieceId),
    );
    _onEnqueue?.call();
  }

  Future<void> afterPhotoDeletion(String photoId) async {
    await _queue.enqueue(
      SyncQueueEntry(operation: SyncOperation.deletePhoto, entityId: photoId),
    );
    _onEnqueue?.call();
  }

  Future<void> afterMaterialDeletion(
    String collection,
    String materialId,
  ) async {
    await _queue.enqueue(
      SyncQueueEntry(
        operation: SyncOperation.deleteMaterial,
        entityId: materialId,
        extraData: collection,
      ),
    );
    _onEnqueue?.call();
  }
}
