import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;

import '../database/daos/photos_dao.dart';
import '../database/daos/pieces_dao.dart';
import '../database/database.dart';
import '../models/piece_stage.dart';
import '../models/untitled_title.dart';
import 'image_service.dart';
import 'sync_trigger.dart';

/// Every local write to a piece or its photos, paired with the sync-queue
/// entry that write must produce.
///
/// Screens call this instead of assembling drift companions themselves, so
/// a write path cannot forget to enqueue (see the offline-first note in
/// AGENTS.md). Haptics, analytics and navigation stay with the caller.
class PieceWriter {
  final PiecesDao _pieces;
  final PhotosDao _photos;
  final ImageService _images;
  final SyncTrigger _sync;
  final DateTime Function() _now;

  PieceWriter({
    required PiecesDao piecesDao,
    required PhotosDao photosDao,
    required ImageService imageService,
    required SyncTrigger syncTrigger,
    DateTime Function()? now,
  }) : _pieces = piecesDao,
       _photos = photosDao,
       _images = imageService,
       _sync = syncTrigger,
       _now = now ?? DateTime.now;

  /// Creates a piece from its first batch of processed photos and returns
  /// the generated title. The last photo becomes the cover.
  Future<String> createPiece({
    required String pieceId,
    required List<ImageResult> photos,
  }) async {
    final now = _now();
    late final String title;

    // One transaction, so a failed read or insert leaves no partial piece
    // behind, and the files go with it: nothing else would ever reference
    // them.
    await _adoptOrDiscard(photos, () async {
      await _pieces.transaction(() async {
        title = nextUntitledTitle(await _pieces.getUntitledPieceTitles());
        await _pieces.insertPiece(
          PiecesCompanion(
            id: Value(pieceId),
            title: Value(title),
            coverPhotoId: Value(photos.last.photoId),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        for (var i = 0; i < photos.length; i++) {
          await _photos.insertPhoto(_photoRow(pieceId, photos[i], i, now));
        }
      });
    });

    await _sync.afterPieceWrite(pieceId);
    for (final photo in photos) {
      await _sync.afterPhotoWrite(photo.photoId, includeFile: true);
    }
    return title;
  }

  /// Adds one processed photo to an existing piece.
  Future<void> addPhoto({
    required String pieceId,
    required ImageResult photo,
    required int sortOrder,
  }) async {
    await _adoptOrDiscard([
      photo,
    ], () => _photos.insertPhoto(_photoRow(pieceId, photo, sortOrder, _now())));
    await _sync.afterPhotoWrite(photo.photoId, includeFile: true);
  }

  /// Runs [insert], which gives [photos]' files their rows. If it throws, the
  /// files are deleted before the error propagates — no row will ever point
  /// at them, so nothing would find them again.
  ///
  /// A failure to queue afterwards leaves the rows, which do reference the
  /// files, in place.
  Future<void> _adoptOrDiscard(
    List<ImageResult> photos,
    Future<void> Function() insert,
  ) async {
    try {
      await insert();
    } catch (_) {
      for (final photo in photos) {
        await _images.discardFiles(photo);
      }
      rethrow;
    }
  }

  Future<void> setCoverPhoto(String pieceId, String? photoId) async {
    await _pieces.updatePiece(
      PiecesCompanion(
        id: Value(pieceId),
        coverPhotoId: Value(photoId),
        updatedAt: Value(_now()),
      ),
    );
    await _sync.afterPieceWrite(pieceId);
  }

  /// Deletes one photo and its files. Pass the piece's current
  /// [coverPhotoId] to have the cover move to the top-sorted remaining photo
  /// when the deleted one was the cover.
  Future<void> deletePhoto({
    required String pieceId,
    required String photoId,
    String? coverPhotoId,
  }) async {
    await _photos.deletePhoto(photoId);
    // Queued before the files go: with the row already deleted, a file error
    // must not stop the cloud copy from being deleted too.
    await _sync.afterPhotoDeletion(photoId, pieceId: pieceId);
    await _cleanUp(() => _images.deletePhotoFiles(pieceId, photoId));

    if (coverPhotoId == photoId) {
      final remaining = await _photos.getPhotosForPiece(pieceId);
      await setCoverPhoto(
        pieceId,
        remaining.isNotEmpty ? remaining.first.id : null,
      );
    }
  }

  /// Stores [orderedIds] as the new display order, first photo on top.
  Future<void> reorderPhotos(List<String> orderedIds) async {
    final updates = <({String id, int sortOrder})>[
      for (var i = 0; i < orderedIds.length; i++)
        (id: orderedIds[i], sortOrder: orderedIds.length - 1 - i),
    ];
    await _photos.updateSortOrders(updates);
    for (final update in updates) {
      await _sync.afterPhotoWrite(update.id);
    }
  }

  /// Deletes a piece, all of its photo rows and their files.
  Future<void> deletePiece(String pieceId) async {
    final photos = await _photos.getPhotosForPiece(pieceId);
    final photoIds = photos.map((p) => p.id).toList();

    await _photos.deletePhotosForPiece(pieceId);
    await _pieces.deletePiece(pieceId);
    // Queued before the files go, as in [deletePhoto].
    await _sync.afterPieceDeletion(pieceId, photoIds);
    await _cleanUp(() => _images.deletePhotos(pieceId));
  }

  /// Deletes files whose rows are already gone. The deletion the user asked
  /// for has happened and is queued by then, so a file that will not delete
  /// is reported to the log rather than as a failed deletion.
  static Future<void> _cleanUp(Future<void> Function() deleteFiles) async {
    try {
      await deleteFiles();
    } catch (e) {
      debugPrint('PieceWriter: photo files left behind after a deletion: $e');
    }
  }

  Future<void> setArchived(String pieceId, bool archived) async {
    await _pieces.updatePiece(
      PiecesCompanion(
        id: Value(pieceId),
        isArchived: Value(archived),
        updatedAt: Value(_now()),
      ),
    );
    await _sync.afterPieceWrite(pieceId);
  }

  /// Writes only the fields given. Empty strings are stored as null;
  /// [clearStage] nulls the stage regardless of [stage].
  Future<void> updateFields(
    String pieceId, {
    String? title,
    PieceStage? stage,
    bool clearStage = false,
    String? clayType,
    String? notes,
  }) async {
    await _pieces.updatePiece(
      PiecesCompanion(
        id: Value(pieceId),
        title: _textOrAbsent(title),
        stage: clearStage
            ? const Value(null)
            : stage != null
            ? Value(stage.name)
            : const Value.absent(),
        clayType: _textOrAbsent(clayType),
        notes: _textOrAbsent(notes),
        updatedAt: Value(_now()),
      ),
    );
    await _sync.afterPieceWrite(pieceId);
  }

  Future<void> setDisplayDate(String pieceId, DateTime date) async {
    await _pieces.updatePiece(
      PiecesCompanion(
        id: Value(pieceId),
        displayDate: Value(date),
        updatedAt: Value(_now()),
      ),
    );
    await _sync.afterPieceWrite(pieceId);
  }

  Future<void> setPhotoDate(String photoId, DateTime date) async {
    await _photos.updatePhoto(
      PhotosCompanion(id: Value(photoId), dateTaken: Value(date)),
    );
    await _sync.afterPhotoWrite(photoId);
  }

  static Value<String?> _textOrAbsent(String? text) =>
      text != null ? Value(text.isEmpty ? null : text) : const Value.absent();

  static PhotosCompanion _photoRow(
    String pieceId,
    ImageResult photo,
    int sortOrder,
    DateTime createdAt,
  ) {
    return PhotosCompanion(
      id: Value(photo.photoId),
      pieceId: Value(pieceId),
      localPath: Value(photo.localPath),
      thumbnailPath: Value(photo.thumbnailPath),
      dateTaken: Value(photo.dateTaken),
      createdAt: Value(createdAt),
      sortOrder: Value(sortOrder),
    );
  }
}
