import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pottery_tracker/services/image_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

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

  group('_compressOrStrip fallback chain', () {
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

    test('both compresses fail, returns raw bytes as last resort', () async {
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

      final result = await service.processImage(
        bytes: inputBytes,
        pieceId: 'test-piece',
      );

      // Both main and thumb should contain the raw input bytes
      final mainFile = File(result.localPath);
      expect(await mainFile.readAsBytes(), equals(inputBytes));

      final thumbFile = File(result.thumbnailPath);
      expect(await thumbFile.readAsBytes(), equals(inputBytes));
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
}
