import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;

import '../database/database.dart';

/// Canonical photo paths relative to the app's documents directory, and
/// runtime resolution of both relative paths and legacy absolute paths whose
/// sandbox container UUID changed (iOS updates, restores, reinstalls).
class PhotoPaths {
  /// The current app documents directory path, or null in widget tests that
  /// supply raw fixture paths without mounting a documents directory.
  final String? documentsPath;

  const PhotoPaths(String this.documentsPath);

  /// Resolves paths verbatim without rebasing onto a documents directory.
  /// Used as the default provider value for isolated widget tests.
  const PhotoPaths.passthrough() : documentsPath = null;

  /// Canonical relative path for a photo's full-size JPEG inside `Documents/`.
  static String relativeMainPath(String pieceId, String photoId) =>
      'photos/$pieceId/$photoId.jpg';

  /// Canonical relative path for a photo's thumbnail JPEG inside `Documents/`.
  static String relativeThumbnailPath(String pieceId, String photoId) =>
      'photos/$pieceId/${photoId}_thumb.jpg';

  /// Extracts a `photos/...` relative suffix from [storedPath] when it is
  /// already relative under `photos/` or is an absolute path containing a
  /// `/photos/` directory segment. Returns null for unrelated paths (such as
  /// ad-hoc temp paths in tests) or paths containing `..` segments.
  static String? extractRelativePath(String storedPath) {
    if (storedPath.isEmpty) return null;
    final normalized = storedPath.replaceAll('\\', '/');
    String? candidate;
    if (normalized.startsWith('photos/')) {
      candidate = normalized;
    } else {
      const marker = '/photos/';
      final index = normalized.lastIndexOf(marker);
      if (index != -1) {
        candidate = normalized.substring(index + 1);
      }
    }
    if (candidate == null) return null;
    final segments = candidate.split('/');
    if (segments.length < 2 || segments.any((s) => s.isEmpty || s == '..')) {
      return null;
    }
    return candidate;
  }

  File _joinDocuments(String relative) =>
      File(p.joinAll([documentsPath!, ...relative.split('/')]));

  /// Full-size photo file at its canonical location inside [documentsPath].
  File mainFile(String pieceId, String photoId) =>
      _joinDocuments(relativeMainPath(pieceId, photoId));

  /// Thumbnail photo file at its canonical location inside [documentsPath].
  File thumbnailFile(String pieceId, String photoId) =>
      _joinDocuments(relativeThumbnailPath(pieceId, photoId));

  /// Resolves the full-size image file for [photo].
  File resolveMainFile(Photo photo) => resolveStoredPath(
    photo.localPath,
    canonicalRelative: relativeMainPath(photo.pieceId, photo.id),
  );

  /// Resolves the thumbnail file for [photo], or discovers a canonical
  /// `_thumb.jpg` on disk when [photo.thumbnailPath] is null.
  File? resolveThumbnailFile(Photo photo) {
    final stored = photo.thumbnailPath;
    if (stored != null) {
      return resolveStoredPath(
        stored,
        canonicalRelative: relativeThumbnailPath(photo.pieceId, photo.id),
      );
    }
    if (documentsPath == null) return null;
    final canonical = thumbnailFile(photo.pieceId, photo.id);
    return canonical.existsSync() ? canonical : null;
  }

  /// Resolves the best local file to display in thumbnails and galleries:
  /// prefers the thumbnail when it exists on disk and falls back to the
  /// full-size photo so a missing or stale thumbnail never hides a photo
  /// whose main file is present.
  File resolveDisplayFile(Photo photo) {
    final thumb = resolveThumbnailFile(photo);
    if (thumb != null && thumb.existsSync()) return thumb;
    return resolveMainFile(photo);
  }

  /// Resolves [storedPath] against [documentsPath].
  ///
  /// Relative paths always resolve inside [documentsPath]. Legacy absolute
  /// paths under a `photos/` directory are rebased onto [documentsPath] first
  /// so iOS container UUID changes never break reads; if the rebased file does
  /// not exist yet but [storedPath] itself does, [storedPath] is kept.
  /// Unrelated absolute paths check [storedPath] first and fall back to
  /// [canonicalRelative] inside [documentsPath] if that file exists on disk.
  File resolveStoredPath(
    String storedPath, {
    required String canonicalRelative,
  }) {
    final docs = documentsPath;
    if (docs == null) return File(storedPath);

    if (storedPath.isEmpty) {
      return _joinDocuments(canonicalRelative);
    }

    if (!p.isAbsolute(storedPath)) {
      return _joinDocuments(storedPath);
    }

    final extracted = extractRelativePath(storedPath);
    if (extracted != null) {
      final rebased = _joinDocuments(extracted);
      if (rebased.existsSync()) return rebased;
      final literal = File(storedPath);
      if (literal.existsSync()) return literal;
      return rebased;
    }

    final literal = File(storedPath);
    if (literal.existsSync()) return literal;
    final canonical = _joinDocuments(canonicalRelative);
    if (canonical.existsSync()) return canonical;
    return literal;
  }
}

/// Rewrites legacy absolute `photos/...` paths stored in [db] to relative
/// paths under [paths.documentsPath], so rows created before relative storage
/// survive iOS container UUID changes without losing local files.
///
/// Safe to run on every launch: already-normalized rows are skipped, and rows
/// with unrelated paths whose canonical files do not exist are left untouched.
/// Returns the number of rows updated.
Future<int> repairStoredPhotoPaths(AppDatabase db, PhotoPaths paths) async {
  if (paths.documentsPath == null) return 0;
  final allPhotos = await db.photosDao.getAllPhotos();
  final updates =
      <({String id, String localPath, Value<String?> thumbnailPath})>[];

  for (final photo in allPhotos) {
    final canonicalMain = PhotoPaths.relativeMainPath(photo.pieceId, photo.id);
    final canonicalThumb = PhotoPaths.relativeThumbnailPath(
      photo.pieceId,
      photo.id,
    );

    String nextLocal = photo.localPath;
    if (photo.localPath.isEmpty) {
      nextLocal = canonicalMain;
    } else if (p.isAbsolute(photo.localPath)) {
      final extracted = PhotoPaths.extractRelativePath(photo.localPath);
      if (extracted != null) {
        nextLocal = extracted;
      } else if (paths.mainFile(photo.pieceId, photo.id).existsSync()) {
        nextLocal = canonicalMain;
      }
    }

    String? nextThumb = photo.thumbnailPath;
    if (photo.thumbnailPath != null && photo.thumbnailPath!.isEmpty) {
      nextThumb = paths.thumbnailFile(photo.pieceId, photo.id).existsSync()
          ? canonicalThumb
          : null;
    } else if (photo.thumbnailPath != null &&
        p.isAbsolute(photo.thumbnailPath!)) {
      final extracted = PhotoPaths.extractRelativePath(photo.thumbnailPath!);
      if (extracted != null) {
        final rebased = paths.resolveStoredPath(
          extracted,
          canonicalRelative: canonicalThumb,
        );
        nextThumb = rebased.existsSync() ? extracted : null;
      } else if (paths.thumbnailFile(photo.pieceId, photo.id).existsSync()) {
        nextThumb = canonicalThumb;
      }
    } else if (photo.thumbnailPath == null &&
        paths.thumbnailFile(photo.pieceId, photo.id).existsSync()) {
      nextThumb = canonicalThumb;
    }

    if (nextLocal != photo.localPath || nextThumb != photo.thumbnailPath) {
      updates.add((
        id: photo.id,
        localPath: nextLocal,
        thumbnailPath: Value(nextThumb),
      ));
    }
  }

  if (updates.isNotEmpty) {
    await db.photosDao.updatePaths(updates);
  }
  return updates.length;
}
