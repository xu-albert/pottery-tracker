import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/features/album/widgets/archive_thumbnail.dart';

import '../../../helpers/fixtures.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  group('ArchiveThumbnail', () {
    testWidgets('renders title overlay', (tester) async {
      await pumpApp(
        tester,
        SizedBox(
          width: 100,
          height: 100,
          child: ArchiveThumbnail(
            piece: makePieceWithCover(piece: makePiece(title: 'My Vase')),
            onTap: () {},
          ),
        ),
      );

      expect(find.text('My Vase'), findsOneWidget);
    });

    testWidgets('shows placeholder icon when no cover photo', (tester) async {
      await pumpApp(
        tester,
        SizedBox(
          width: 100,
          height: 100,
          child: ArchiveThumbnail(
            piece: makePieceWithCover(
              piece: makePiece(title: 'No Photo Piece'),
            ),
            onTap: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });

    testWidgets('shows "Untitled Piece" when title is null', (tester) async {
      await pumpApp(
        tester,
        SizedBox(
          width: 100,
          height: 100,
          child: ArchiveThumbnail(
            piece: makePieceWithCover(piece: makePiece(title: null)),
            onTap: () {},
          ),
        ),
      );

      expect(find.text('Untitled Piece'), findsOneWidget);
    });

    testWidgets('gradient container is present', (tester) async {
      await pumpApp(
        tester,
        SizedBox(
          width: 100,
          height: 100,
          child: ArchiveThumbnail(piece: makePieceWithCover(), onTap: () {}),
        ),
      );

      final containers = tester.widgetList<Container>(find.byType(Container));
      final hasGradient = containers.any((c) {
        final decoration = c.decoration;
        if (decoration is BoxDecoration) {
          return decoration.gradient is LinearGradient;
        }
        return false;
      });
      expect(hasGradient, isTrue);
    });

    testWidgets('onTap callback fires', (tester) async {
      var tapped = false;
      await pumpApp(
        tester,
        SizedBox(
          width: 100,
          height: 100,
          child: ArchiveThumbnail(
            piece: makePieceWithCover(),
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.byType(ArchiveThumbnail));
      expect(tapped, isTrue);
    });
  });
}
