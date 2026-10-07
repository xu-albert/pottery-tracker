import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pottery_tracker/services/image_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  List<String> photoFiles() {
    final photos = Directory(p.join(tempDir.path, 'photos'));
    if (!photos.existsSync()) return [];
    return photos
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path)
        .toList();
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('image_service_test_');

    // Mock path_provider to return our temp directory
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('re-encode fallback chain', () {
    test('happy path: compress succeeds, output is compressed bytes', () async {
      final inputBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final compressedBytes = Uint8List.fromList([10, 20]);

      final service = ImageService(
        compress:
            (
              input, {
              int quality = 95,
              int minWidth = 1920,
              int minHeight = 1080,
            }) async {
              return compressedBytes;
            },
      );

      final result = await service.processImage(
        bytes: inputBytes,
        pieceId: 'test-piece',
      );

      // Verify the main image file contains compressed bytes
      final mainFile = File(result.localPath);
      expect(await mainFile.readAsBytes(), equals(compressedBytes));

      // Verify the thumbnail file contains compressed bytes
      final thumbFile = File(result.thumbnailPath);
      expect(await thumbFile.readAsBytes(), equals(compressedBytes));
    });

    test('first compress fails, strip-only re-encode succeeds', () async {
      final inputBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final strippedBytes = Uint8List.fromList([99, 98]);
      var callCount = 0;

      final service = ImageService(
        compress:
            (
              input, {
              int quality = 95,
              int minWidth = 1920,
              int minHeight = 1080,
            }) async {
              callCount++;
              // Odd calls fail (first attempt with resize), even calls succeed (strip-only)
              if (callCount.isOdd) {
                throw Exception('Compression failed');
              }
              return strippedBytes;
            },
      );

      final result = await service.processImage(
        bytes: inputBytes,
        pieceId: 'test-piece',
      );

      // Both main and thumb should have the stripped bytes from the fallback
      final mainFile = File(result.localPath);
      expect(await mainFile.readAsBytes(), equals(strippedBytes));

      final thumbFile = File(result.thumbnailPath);
      expect(await thumbFile.readAsBytes(), equals(strippedBytes));

      // Should have called compress 4 times: 2 per image (fail + fallback) x 2 images
      expect(callCount, 4);
    });

    test('both compresses fail: the photo is refused and never kept raw, '
        'since the original carries its EXIF location', () async {
      final inputBytes = Uint8List.fromList([1, 2, 3, 4, 5]);

      final service = ImageService(
        compress:
            (
              input, {
              int quality = 95,
              int minWidth = 1920,
              int minHeight = 1080,
            }) async {
              throw Exception('Compression always fails');
            },
      );

      await expectLater(
        service.processImage(bytes: inputBytes, pieceId: 'test-piece'),
        throwsA(isA<PhotoNotSanitizedException>()),
      );
      expect(photoFiles(), isEmpty);
    });

    test('an empty re-encode is a failure, not a photo', () async {
      final service = ImageService(
        compress:
            (
              input, {
              int quality = 95,
              int minWidth = 1920,
              int minHeight = 1080,
            }) async => Uint8List(0),
      );

      await expectLater(
        service.processImage(
          bytes: Uint8List.fromList([1, 2, 3]),
          pieceId: 'test-piece',
        ),
        throwsA(isA<PhotoNotSanitizedException>()),
      );
      expect(photoFiles(), isEmpty);
    });

    test('a thumbnail that cannot be re-encoded leaves no full-size file '
        'behind either', () async {
      final service = ImageService(
        compress:
            (
              input, {
              int quality = 95,
              int minWidth = 1920,
              int minHeight = 1080,
            }) async {
              // The thumbnail's sized attempt and its fallback both fail.
              if (minWidth == 300 || quality == 100) {
                throw Exception('thumbnail failed');
              }
              return Uint8List.fromList([7, 7]);
            },
      );

      await expectLater(
        service.processImage(
          bytes: Uint8List.fromList([1, 2, 3]),
          pieceId: 'test-piece',
        ),
        throwsA(isA<PhotoNotSanitizedException>()),
      );
      expect(photoFiles(), isEmpty);
    });

    test('a thumbnail write that fails deletes the full-size file it '
        'already wrote', () async {
      final written = <String>[];
      final service = ImageService(
        compress:
            (
              input, {
              int quality = 95,
              int minWidth = 1920,
              int minHeight = 1080,
            }) async => Uint8List.fromList([7, 7]),
        writeFile: (path, bytes) async {
          if (path.endsWith('_thumb.jpg')) {
            throw const FileSystemException('disk full');
          }
          await File(path).writeAsBytes(bytes);
          written.add(path);
        },
      );

      await expectLater(
        service.processImage(
          bytes: Uint8List.fromList([1, 2, 3]),
          pieceId: 'test-piece',
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(written, hasLength(1), reason: 'the main file was written');
      expect(photoFiles(), isEmpty);
    });

    test('processImage creates files in correct directory structure', () async {
      final inputBytes = Uint8List.fromList([1, 2, 3]);

      final service = ImageService(
        compress:
            (
              input, {
              int quality = 95,
              int minWidth = 1920,
              int minHeight = 1080,
            }) async {
              return input; // passthrough
            },
      );

      final result = await service.processImage(
        bytes: inputBytes,
        pieceId: 'my-piece-id',
      );

      // Verify paths are under photos/my-piece-id/
      expect(result.localPath, contains(p.join('photos', 'my-piece-id')));
      expect(result.thumbnailPath, contains(p.join('photos', 'my-piece-id')));
      expect(result.thumbnailPath, contains('_thumb.jpg'));

      // Verify files actually exist
      expect(File(result.localPath).existsSync(), isTrue);
      expect(File(result.thumbnailPath).existsSync(), isTrue);
    });
  });

  test(
    'discardFiles removes both files and tolerates one already gone',
    () async {
      final dir = Directory(p.join(tempDir.path, 'photos', 'p'))
        ..createSync(recursive: true);
      final main = File(p.join(dir.path, 'x.jpg'))..writeAsBytesSync([1]);
      final result = ImageResult(
        photoId: 'x',
        localPath: main.path,
        thumbnailPath: p.join(dir.path, 'x_thumb.jpg'),
        dateTaken: DateTime(2024),
      );

      await ImageService().discardFiles(result);

      expect(photoFiles(), isEmpty);
    },
  );
}
