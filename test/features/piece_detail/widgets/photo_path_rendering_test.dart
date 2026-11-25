import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/features/album/widgets/archive_thumbnail.dart';
import 'package:pottery_tracker/features/album/widgets/piece_row.dart';
import 'package:pottery_tracker/features/piece_detail/widgets/photo_fullscreen.dart';
import 'package:pottery_tracker/features/piece_detail/widgets/photo_gallery.dart';
import 'package:pottery_tracker/features/piece_detail/widgets/photo_reorder.dart';
import 'package:pottery_tracker/providers/materials_provider.dart';
import 'package:pottery_tracker/providers/photo_paths_provider.dart';
import 'package:pottery_tracker/providers/photos_provider.dart';
import 'package:pottery_tracker/services/photo_paths.dart';

import '../../../helpers/fixtures.dart';
import '../../../helpers/test_helpers.dart';

// Minimal valid 1x1 PNG so Image.file decodes cleanly in widget tests.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

FileImage _unwrapFileImage(ImageProvider provider) => switch (provider) {
  ResizeImage(:final imageProvider) => imageProvider as FileImage,
  final FileImage fileImage => fileImage,
  _ => throw StateError('Unexpected ImageProvider: ${provider.runtimeType}'),
};

void main() {
  late Directory docsDir;
  late PhotoPaths photoPaths;

  setUp(() {
    docsDir = Directory.systemTemp.createTempSync('photo_widget_docs_');
    photoPaths = PhotoPaths(docsDir.path);
  });

  tearDown(() {
    if (docsDir.existsSync()) {
      docsDir.deleteSync(recursive: true);
    }
  });

  File writePhoto(String relative) {
    final file = File(p.joinAll([docsDir.path, ...relative.split('/')]))
      ..createSync(recursive: true)
      ..writeAsBytesSync(_pngBytes);
    return file;
  }

  group('container-relocated photo rendering', () {
    testWidgets(
      'ArchiveThumbnail renders a photo stored under an old iOS container UUID',
      (tester) async {
        final thumb = writePhoto('photos/p1/ph1_thumb.jpg');
        final photo = makePhoto(
          id: 'ph1',
          pieceId: 'p1',
          localPath:
              '/var/mobile/Containers/Data/Application/OLD-UUID/Documents/photos/p1/ph1.jpg',
          thumbnailPath:
              '/var/mobile/Containers/Data/Application/OLD-UUID/Documents/photos/p1/ph1_thumb.jpg',
        );

        await pumpApp(
          tester,
          SizedBox(
            width: 120,
            height: 120,
            child: ArchiveThumbnail(
              piece: makePieceWithCover(
                piece: makePiece(id: 'p1', title: 'Bowl'),
                coverPhoto: photo,
              ),
              onTap: () {},
            ),
          ),
          overrides: [photoPathsProvider.overrideWithValue(photoPaths)],
        );

        final image = tester.widget<Image>(find.byType(Image));
        expect(_unwrapFileImage(image.image).file.path, thumb.path);
        expect(find.byIcon(Icons.image_outlined), findsNothing);
      },
    );

    testWidgets(
      'PieceRow falls back to main photo when thumbnail is missing on disk',
      (tester) async {
        final main = writePhoto('photos/p1/ph1.jpg');
        final photo = makePhoto(
          id: 'ph1',
          pieceId: 'p1',
          localPath:
              '/var/mobile/Containers/Data/Application/OLD-UUID/Documents/photos/p1/ph1.jpg',
          thumbnailPath:
              '/var/mobile/Containers/Data/Application/OLD-UUID/Documents/photos/p1/ph1_thumb.jpg',
        );

        await pumpApp(
          tester,
          PieceRow(
            piece: makePieceWithCover(
              piece: makePiece(id: 'p1', title: 'Mug'),
              coverPhoto: photo,
            ),
            onTap: () {},
          ),
          overrides: [
            photoPathsProvider.overrideWithValue(photoPaths),
            tagColorMapProvider.overrideWithValue(<String, Color>{}),
            photosForPieceProvider(
              'p1',
            ).overrideWith((ref) => Stream.value(<Photo>[photo])),
          ],
        );

        final image = tester.widget<Image>(find.byType(Image));
        expect(_unwrapFileImage(image.image).file.path, main.path);
        expect(find.byIcon(Icons.image_outlined), findsNothing);
      },
    );

    testWidgets(
      'PhotoGallery renders relocated photo and shows broken_image until a '
      'missing file arrives on disk, then renders once rebuilt',
      (tester) async {
        final photo = makePhoto(
          id: 'ph1',
          pieceId: 'p1',
          localPath: 'photos/p1/ph1.jpg',
          thumbnailPath: null,
        );

        await pumpApp(
          tester,
          PhotoGallery(photos: [photo]),
          overrides: [photoPathsProvider.overrideWithValue(photoPaths)],
        );

        expect(find.byIcon(Icons.broken_image), findsOneWidget);
        expect(find.byType(Image), findsNothing);

        // Simulate _downloadPhoto landing the file on disk and Drift re-emitting.
        final main = writePhoto('photos/p1/ph1.jpg');
        await pumpApp(
          tester,
          PhotoGallery(photos: [photo]),
          overrides: [photoPathsProvider.overrideWithValue(photoPaths)],
        );

        final image = tester.widget<Image>(find.byType(Image));
        expect((image.image as FileImage).file.path, main.path);
        expect(find.byIcon(Icons.broken_image), findsNothing);
      },
    );

    testWidgets(
      'PhotoReorderScreen resolves relocated photo paths from photoPathsProvider',
      (tester) async {
        final thumb = writePhoto('photos/p1/ph1_thumb.jpg');
        final photo = makePhoto(
          id: 'ph1',
          pieceId: 'p1',
          localPath:
              '/var/mobile/Containers/Data/Application/OLD-UUID/Documents/photos/p1/ph1.jpg',
          thumbnailPath:
              '/var/mobile/Containers/Data/Application/OLD-UUID/Documents/photos/p1/ph1_thumb.jpg',
        );

        await pumpApp(
          tester,
          PhotoReorderScreen(photos: [photo]),
          overrides: [photoPathsProvider.overrideWithValue(photoPaths)],
        );

        final image = tester.widget<Image>(find.byType(Image));
        expect((image.image as FileImage).file.path, thumb.path);
        expect(find.byIcon(Icons.broken_image), findsNothing);
      },
    );

    testWidgets(
      'PhotoFullscreen shows broken_image fallback instead of crashing when a '
      'file is missing',
      (tester) async {
        await pumpApp(
          tester,
          PhotoFullscreen(photoPath: p.join(docsDir.path, 'missing.jpg')),
        );

        expect(find.byIcon(Icons.broken_image), findsOneWidget);
        expect(find.byType(Image), findsNothing);
      },
    );
  });
}
