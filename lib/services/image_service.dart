import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:uuid/uuid.dart';

typedef CompressFunction =
    Future<Uint8List> Function(
      Uint8List input, {
      int quality,
      int minWidth,
      int minHeight,
    });

class ImageResult {
  final String photoId;
  final String localPath;
  final String thumbnailPath;
  final DateTime dateTaken;

  ImageResult({
    required this.photoId,
    required this.localPath,
    required this.thumbnailPath,
    required this.dateTaken,
  });
}

typedef WriteFileFunction = Future<void> Function(String path, Uint8List bytes);

/// A photo neither re-encode could process. Its original bytes are never
/// kept instead: they carry the EXIF block, GPS position included, that the
/// re-encode exists to strip, and may not even be a JPEG.
class PhotoNotSanitizedException implements Exception {
  final Object cause;

  PhotoNotSanitizedException(this.cause);

  @override
  String toString() => 'PhotoNotSanitizedException: $cause';
}

class ImageService {
  final _picker = ImagePicker();
  final _uuid = const Uuid();
  final CompressFunction _compress;
  final WriteFileFunction _writeFile;

  ImageService({
    CompressFunction? compress,
    @visibleForTesting WriteFileFunction? writeFile,
  }) : _compress = compress ?? FlutterImageCompress.compressWithList,
       _writeFile = writeFile ?? _writeBytes;

  static Future<void> _writeBytes(String path, Uint8List bytes) =>
      File(path).writeAsBytes(bytes);

  Future<ImageResult?> pickAndProcessImage({
    required ImageSource source,
    required String pieceId,
  }) async {
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return null;

    final Uint8List rawBytes = await picked.readAsBytes();
    return processImage(bytes: rawBytes, pieceId: pieceId);
  }

  Future<List<XFile>?> pickMultipleImages() async {
    final picked = await _picker.pickMultiImage(requestFullMetadata: true);
    if (picked.isEmpty) return null;
    return picked;
  }

  /// Writes a sanitised full-size image and thumbnail for [bytes] and returns
  /// where they are. Throws [PhotoNotSanitizedException] when the photo
  /// cannot be re-encoded; on any failure nothing is left on disk.
  Future<ImageResult> processImage({
    required Uint8List bytes,
    required String pieceId,
  }) async {
    final photoId = _uuid.v4();
    final dateTaken = await _extractDateFromBytes(bytes);

    // Both re-encodes (which strip EXIF, GPS included) run before anything is
    // written, so a photo that cannot be sanitised leaves no file at all.
    final mainBytes = await _reencode(
      bytes,
      quality: 75,
      minWidth: 1500,
      minHeight: 1500,
    );
    final thumbBytes = await _reencode(
      bytes,
      quality: 60,
      minWidth: 300,
      minHeight: 300,
    );

    final appDir = await getApplicationDocumentsDirectory();
    final photoDir = Directory(p.join(appDir.path, 'photos', pieceId));
    await photoDir.create(recursive: true);

    final result = ImageResult(
      photoId: photoId,
      localPath: p.join(photoDir.path, '$photoId.jpg'),
      thumbnailPath: p.join(photoDir.path, '${photoId}_thumb.jpg'),
      dateTaken: dateTaken,
    );
    try {
      await _writeFile(result.localPath, mainBytes);
      await _writeFile(result.thumbnailPath, thumbBytes);
    } catch (_) {
      await discardFiles(result);
      rethrow;
    }
    return result;
  }

  /// Deletes both of [result]'s files, for a photo no row will ever adopt.
  /// Best effort: it runs while another error is already propagating, which
  /// is the one the caller needs to see.
  Future<void> discardFiles(ImageResult result) async {
    for (final path in [result.localPath, result.thumbnailPath]) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('ImageService: could not discard $path: $e');
      }
    }
  }

  /// Re-encodes [bytes] as a JPEG, which strips EXIF metadata (including
  /// GPS). Falls back to a full-quality re-encode at the encoder's default
  /// size if the sized one fails, and throws [PhotoNotSanitizedException] if
  /// that fails too — see the exception for why the original is never used
  /// instead.
  Future<Uint8List> _reencode(
    Uint8List bytes, {
    required int quality,
    required int minWidth,
    required int minHeight,
  }) async {
    try {
      return _nonEmpty(
        await _compress(
          bytes,
          quality: quality,
          minWidth: minWidth,
          minHeight: minHeight,
        ),
      );
    } catch (_) {}

    try {
      return _nonEmpty(await _compress(bytes, quality: 100));
    } catch (e) {
      throw PhotoNotSanitizedException(e);
    }
  }

  static Uint8List _nonEmpty(Uint8List encoded) {
    if (encoded.isEmpty) throw StateError('the re-encode produced no bytes');
    return encoded;
  }

  Future<DateTime> _extractDateFromBytes(Uint8List bytes) async {
    try {
      final tags = await readExifFromBytes(bytes);
      final dateTag =
          tags['EXIF DateTimeOriginal']?.toString() ??
          tags['Image DateTime']?.toString();
      if (dateTag != null && dateTag.length >= 19) {
        final datePart = dateTag.substring(0, 10).replaceAll(':', '-');
        final timePart = dateTag.substring(10);
        return DateTime.parse('$datePart$timePart');
      }
    } catch (_) {}
    return DateTime.now();
  }

  Future<void> deletePhotos(String pieceId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final photoDir = Directory(p.join(appDir.path, 'photos', pieceId));
    if (await photoDir.exists()) {
      await photoDir.delete(recursive: true);
    }
  }

  Future<void> deletePhotoFiles(String pieceId, String photoId) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = p.join(appDir.path, 'photos', pieceId);
    final main = File(p.join(dir, '$photoId.jpg'));
    final thumb = File(p.join(dir, '${photoId}_thumb.jpg'));
    if (await main.exists()) await main.delete();
    if (await thumb.exists()) await thumb.delete();
  }
}
