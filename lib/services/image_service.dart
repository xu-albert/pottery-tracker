import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:exif/exif.dart';
import 'package:uuid/uuid.dart';

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

class ImageService {
  final _picker = ImagePicker();
  final _uuid = const Uuid();

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
    final picked = await _picker.pickMultiImage(
      requestFullMetadata: false,
    );
    if (picked.isEmpty) return null;
    return picked;
  }

  Future<ImageResult> processImage({
    required Uint8List bytes,
    required String pieceId,
  }) async {
    final photoId = _uuid.v4();
    final dateTaken = _extractDateFromBytes(bytes);

    final appDir = await getApplicationDocumentsDirectory();
    final photoDir = Directory(p.join(appDir.path, 'photos', pieceId));
    await photoDir.create(recursive: true);

    final mainPath = p.join(photoDir.path, '$photoId.jpg');
    final thumbPath = p.join(photoDir.path, '${photoId}_thumb.jpg');

    // Save main image: try compressing, fall back to raw bytes
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        quality: 75,
        minWidth: 1500,
        minHeight: 1500,
      );
      await File(mainPath).writeAsBytes(compressed);
    } catch (_) {
      await File(mainPath).writeAsBytes(bytes);
    }

    // Save thumbnail: try compressing small, fall back to main
    try {
      final thumb = await FlutterImageCompress.compressWithList(
        bytes,
        quality: 60,
        minWidth: 300,
        minHeight: 300,
      );
      await File(thumbPath).writeAsBytes(thumb);
    } catch (_) {
      await File(thumbPath).writeAsBytes(bytes);
    }

    return ImageResult(
      photoId: photoId,
      localPath: mainPath,
      thumbnailPath: thumbPath,
      dateTaken: dateTaken,
    );
  }

  DateTime _extractDateFromBytes(Uint8List bytes) {
    try {
      final tags = readExifFromBytes(bytes) as Map<String, IfdTag>;
      final dateTag = tags['EXIF DateTimeOriginal']?.toString() ??
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
