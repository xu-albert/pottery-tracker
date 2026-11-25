import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/services/photo_paths.dart';

import '../helpers/fixtures.dart';

void main() {
  late Directory docsDir;
  late PhotoPaths paths;

  setUp(() {
    docsDir = Directory.systemTemp.createTempSync('photo_paths_test_');
    paths = PhotoPaths(docsDir.path);
  });

  tearDown(() {
    if (docsDir.existsSync()) {
      docsDir.deleteSync(recursive: true);
    }
  });

  group('extractRelativePath', () {
    test('returns already-relative photos paths as-is', () {
      expect(
        PhotoPaths.extractRelativePath('photos/p1/ph1.jpg'),
        'photos/p1/ph1.jpg',
      );
      expect(
        PhotoPaths.extractRelativePath('photos/p1/ph1_thumb.jpg'),
        'photos/p1/ph1_thumb.jpg',
      );
    });

    test('strips legacy iOS and Android container prefixes', () {
      expect(
        PhotoPaths.extractRelativePath(
          '/var/mobile/Containers/Data/Application/OLD-UUID-1234/Documents/photos/p1/ph1.jpg',
        ),
        'photos/p1/ph1.jpg',
      );
      expect(
        PhotoPaths.extractRelativePath(
          '/data/user/0/com.albertxu.potterytracker/app_flutter/photos/p1/ph1_thumb.jpg',
        ),
        'photos/p1/ph1_thumb.jpg',
      );
    });

    test('rejects traversal segments and unrelated paths', () {
      expect(PhotoPaths.extractRelativePath(''), isNull);
      expect(PhotoPaths.extractRelativePath('/tmp/other/photo.jpg'), isNull);
      expect(PhotoPaths.extractRelativePath('photos/../secret.db'), isNull);
      expect(
        PhotoPaths.extractRelativePath('/var/app/photos/p1/../escape.jpg'),
        isNull,
      );
    });
  });

  group('PhotoPaths resolution', () {
    test('resolves relative paths inside current documents directory', () {
      final photo = makePhoto(
        id: 'ph1',
        pieceId: 'p1',
        localPath: 'photos/p1/ph1.jpg',
        thumbnailPath: 'photos/p1/ph1_thumb.jpg',
      );

      expect(
        paths.resolveMainFile(photo).path,
        p.join(docsDir.path, 'photos', 'p1', 'ph1.jpg'),
      );
      expect(
        paths.resolveThumbnailFile(photo)!.path,
        p.join(docsDir.path, 'photos', 'p1', 'ph1_thumb.jpg'),
      );
    });

    test(
      'rebases legacy absolute iOS container paths to the current container',
      () {
        final mainFile = File(p.join(docsDir.path, 'photos', 'p1', 'ph1.jpg'))
          ..createSync(recursive: true)
          ..writeAsBytesSync([1, 2, 3]);
        final thumbFile = File(
          p.join(docsDir.path, 'photos', 'p1', 'ph1_thumb.jpg'),
        )..writeAsBytesSync([4, 5]);

        final photo = makePhoto(
          id: 'ph1',
          pieceId: 'p1',
          localPath:
              '/var/mobile/Containers/Data/Application/OLD-UUID/Documents/photos/p1/ph1.jpg',
          thumbnailPath:
              '/var/mobile/Containers/Data/Application/OLD-UUID/Documents/photos/p1/ph1_thumb.jpg',
        );

        expect(paths.resolveMainFile(photo).path, mainFile.path);
        expect(paths.resolveDisplayFile(photo).path, thumbFile.path);
      },
    );

    test(
      'resolveDisplayFile falls back to main photo when thumbnail is missing',
      () {
        final mainFile = File(p.join(docsDir.path, 'photos', 'p1', 'ph1.jpg'))
          ..createSync(recursive: true)
          ..writeAsBytesSync([1, 2, 3]);

        final photo = makePhoto(
          id: 'ph1',
          pieceId: 'p1',
          localPath:
              '/var/mobile/Containers/Data/Application/OLD-UUID/Documents/photos/p1/ph1.jpg',
          thumbnailPath:
              '/var/mobile/Containers/Data/Application/OLD-UUID/Documents/photos/p1/ph1_thumb.jpg',
        );

        expect(paths.resolveDisplayFile(photo).path, mainFile.path);
      },
    );

    test(
      'discovers canonical thumbnail on disk when thumbnailPath is null',
      () {
        final thumbFile =
            File(p.join(docsDir.path, 'photos', 'p1', 'ph1_thumb.jpg'))
              ..createSync(recursive: true)
              ..writeAsBytesSync([4, 5]);

        final photo = makePhoto(
          id: 'ph1',
          pieceId: 'p1',
          localPath: 'photos/p1/ph1.jpg',
          thumbnailPath: null,
        );

        expect(paths.resolveDisplayFile(photo).path, thumbFile.path);
      },
    );

    test(
      'preserves existing unrelated absolute paths (such as temp files)',
      () {
        final tempDir = Directory.systemTemp.createTempSync('unrelated_photo_');
        addTearDown(() => tempDir.deleteSync(recursive: true));
        final tempFile = File(p.join(tempDir.path, 'custom.jpg'))
          ..writeAsBytesSync([9]);

        final photo = makePhoto(
          id: 'ph1',
          pieceId: 'p1',
          localPath: tempFile.path,
          thumbnailPath: null,
        );

        expect(paths.resolveMainFile(photo).path, tempFile.path);
      },
    );

    test('empty storedPath resolves to canonical path, never documentsDir', () {
      final photo = makePhoto(
        id: 'ph1',
        pieceId: 'p1',
        localPath: '',
        thumbnailPath: '',
      );

      final main = paths.resolveMainFile(photo);
      expect(main.path, p.join(docsDir.path, 'photos', 'p1', 'ph1.jpg'));
      expect(main.existsSync(), isFalse);
      final thumb = paths.resolveThumbnailFile(photo)!;
      expect(thumb.path, p.join(docsDir.path, 'photos', 'p1', 'ph1_thumb.jpg'));
      expect(thumb.existsSync(), isFalse);
    });
  });

  group('repairStoredPhotoPaths', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('rewrites legacy iOS container paths to relative paths, clears missing '
        'thumbnails, discovers present thumbnails, and is idempotent', () async {
      final now = DateTime(2026);
      await db.piecesDao.insertPiece(
        PiecesCompanion.insert(id: 'p1', createdAt: now, updatedAt: now),
      );

      // ph1: both main and thumb survived in the new container.
      File(p.join(docsDir.path, 'photos', 'p1', 'ph1.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1]);
      File(
        p.join(docsDir.path, 'photos', 'p1', 'ph1_thumb.jpg'),
      ).writeAsBytesSync([2]);
      await db.photosDao.insertPhoto(
        PhotosCompanion(
          id: const Value('ph1'),
          pieceId: const Value('p1'),
          localPath: const Value(
            '/var/mobile/Containers/Data/Application/OLD-UUID/Documents/photos/p1/ph1.jpg',
          ),
          thumbnailPath: const Value(
            '/var/mobile/Containers/Data/Application/OLD-UUID/Documents/photos/p1/ph1_thumb.jpg',
          ),
          dateTaken: Value(now),
          createdAt: Value(now),
        ),
      );

      // ph2: main survived, thumb is missing.
      File(
        p.join(docsDir.path, 'photos', 'p1', 'ph2.jpg'),
      ).writeAsBytesSync([3]);
      await db.photosDao.insertPhoto(
        PhotosCompanion(
          id: const Value('ph2'),
          pieceId: const Value('p1'),
          localPath: const Value(
            '/var/mobile/Containers/Data/Application/OLD-UUID/Documents/photos/p1/ph2.jpg',
          ),
          thumbnailPath: const Value(
            '/var/mobile/Containers/Data/Application/OLD-UUID/Documents/photos/p1/ph2_thumb.jpg',
          ),
          dateTaken: Value(now),
          createdAt: Value(now),
        ),
      );

      // ph3: already relative localPath with null thumbnailPath, while a
      // canonical thumb exists on disk.
      File(
        p.join(docsDir.path, 'photos', 'p1', 'ph3_thumb.jpg'),
      ).writeAsBytesSync([4]);
      await db.photosDao.insertPhoto(
        PhotosCompanion(
          id: const Value('ph3'),
          pieceId: const Value('p1'),
          localPath: const Value('photos/p1/ph3.jpg'),
          thumbnailPath: const Value(null),
          dateTaken: Value(now),
          createdAt: Value(now),
        ),
      );

      final firstPass = await repairStoredPhotoPaths(db, paths);
      expect(firstPass, 3);

      final ph1 = (await db.photosDao.getPhotoById('ph1'))!;
      expect(ph1.localPath, 'photos/p1/ph1.jpg');
      expect(ph1.thumbnailPath, 'photos/p1/ph1_thumb.jpg');

      final ph2 = (await db.photosDao.getPhotoById('ph2'))!;
      expect(ph2.localPath, 'photos/p1/ph2.jpg');
      expect(ph2.thumbnailPath, isNull);

      final ph3 = (await db.photosDao.getPhotoById('ph3'))!;
      expect(ph3.localPath, 'photos/p1/ph3.jpg');
      expect(ph3.thumbnailPath, 'photos/p1/ph3_thumb.jpg');

      // Second pass finds nothing left to rewrite.
      expect(await repairStoredPhotoPaths(db, paths), 0);
    });
  });
}
