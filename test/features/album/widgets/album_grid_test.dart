import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/features/album/widgets/album_grid.dart';
import 'package:pottery_tracker/features/album/widgets/archive_thumbnail.dart';
import 'package:pottery_tracker/features/album/widgets/piece_row.dart';
import 'package:pottery_tracker/providers/analytics_provider.dart';
import 'package:pottery_tracker/providers/database_provider.dart';
import 'package:pottery_tracker/providers/materials_provider.dart';
import 'package:pottery_tracker/providers/photos_provider.dart';
import 'package:pottery_tracker/providers/pieces_provider.dart';
import 'package:pottery_tracker/providers/sync_provider.dart';

import '../../../helpers/fixtures.dart';
import '../../../helpers/mock_providers.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  late MockPiecesDao mockPiecesDao;
  late MockFirebaseAnalytics mockAnalytics;
  late MockSyncTrigger mockSyncTrigger;

  setUpAll(() {
    registerFallbackValue(
      PiecesCompanion(
        id: const Value(''),
        isArchived: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    );
  });

  setUp(() {
    mockPiecesDao = MockPiecesDao();
    when(() => mockPiecesDao.updatePiece(any())).thenAnswer((_) async {});
    mockAnalytics = MockFirebaseAnalytics();
    when(
      () => mockAnalytics.logEvent(
        name: any(named: 'name'),
        parameters: any(named: 'parameters'),
      ),
    ).thenAnswer((_) async {});
    mockSyncTrigger = MockSyncTrigger();
    when(
      () => mockSyncTrigger.afterPieceWrite(any()),
    ).thenAnswer((_) async {});
  });

  group('AlbumGrid - Active view', () {
    testWidgets('renders list items (PieceRow)', (tester) async {
      final pieces = [
        makePieceWithCover(
          piece: makePiece(id: 'p1', title: 'Bowl'),
        ),
        makePieceWithCover(
          piece: makePiece(id: 'p2', title: 'Mug'),
        ),
      ];

      await pumpApp(
        tester,
        AlbumGrid(pieces: pieces, viewMode: ViewMode.list, isArchived: false),
        overrides: [
          piecesDaoProvider.overrideWithValue(mockPiecesDao),
          analyticsProvider.overrideWithValue(mockAnalytics),
          syncTriggerProvider.overrideWithValue(mockSyncTrigger),
          tagColorMapProvider.overrideWithValue(<String, Color>{}),
          photosForPieceProvider(
            'p1',
          ).overrideWith((ref) => Stream.value(<Photo>[])),
          photosForPieceProvider(
            'p2',
          ).overrideWith((ref) => Stream.value(<Photo>[])),
        ],
      );

      expect(find.byType(PieceRow), findsNWidgets(2));
      expect(find.text('Bowl'), findsOneWidget);
      expect(find.text('Mug'), findsOneWidget);
    });

    testWidgets('swipe-to-archive calls dao.updatePiece and shows snackbar', (
      tester,
    ) async {
      final pieces = [
        makePieceWithCover(
          piece: makePiece(id: 'p1', title: 'My Bowl'),
        ),
      ];

      await pumpApp(
        tester,
        AlbumGrid(pieces: pieces, viewMode: ViewMode.list, isArchived: false),
        overrides: [
          piecesDaoProvider.overrideWithValue(mockPiecesDao),
          analyticsProvider.overrideWithValue(mockAnalytics),
          syncTriggerProvider.overrideWithValue(mockSyncTrigger),
          tagColorMapProvider.overrideWithValue(<String, Color>{}),
          photosForPieceProvider(
            'p1',
          ).overrideWith((ref) => Stream.value(<Photo>[])),
        ],
      );

      // Swipe the row from right to left
      await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
      await tester.pumpAndSettle();

      // Verify dao was called with isArchived: true
      final captured = verify(
        () => mockPiecesDao.updatePiece(captureAny()),
      ).captured;
      expect(captured, hasLength(1));
      final companion = captured.first as PiecesCompanion;
      expect(companion.id.value, equals('p1'));
      expect(companion.isArchived.value, isTrue);

      // Verify sync trigger was called
      verify(() => mockSyncTrigger.afterPieceWrite('p1')).called(1);

      // Verify snackbar text
      expect(find.text('My Bowl archived'), findsOneWidget);
    });

    testWidgets('undo button reverses the archive', (tester) async {
      final pieces = [
        makePieceWithCover(
          piece: makePiece(id: 'p1', title: 'My Bowl'),
        ),
      ];

      await pumpApp(
        tester,
        AlbumGrid(pieces: pieces, viewMode: ViewMode.list, isArchived: false),
        overrides: [
          piecesDaoProvider.overrideWithValue(mockPiecesDao),
          analyticsProvider.overrideWithValue(mockAnalytics),
          syncTriggerProvider.overrideWithValue(mockSyncTrigger),
          tagColorMapProvider.overrideWithValue(<String, Color>{}),
          photosForPieceProvider(
            'p1',
          ).overrideWith((ref) => Stream.value(<Photo>[])),
        ],
      );

      await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
      await tester.pumpAndSettle();

      // Tap Undo
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      // Second call should set isArchived: false
      final captured = verify(
        () => mockPiecesDao.updatePiece(captureAny()),
      ).captured;
      expect(captured, hasLength(2));
      final undoCompanion = captured.last as PiecesCompanion;
      expect(undoCompanion.id.value, equals('p1'));
      expect(undoCompanion.isArchived.value, isFalse);

      // Verify sync trigger called for both archive and undo
      verify(() => mockSyncTrigger.afterPieceWrite('p1')).called(2);
    });
  });

  group('AlbumGrid - Archive view', () {
    testWidgets('renders grid of ArchiveThumbnails', (tester) async {
      final pieces = [
        makePieceWithCover(
          piece: makePiece(id: 'a1', title: 'Archived 1', isArchived: true),
        ),
        makePieceWithCover(
          piece: makePiece(id: 'a2', title: 'Archived 2', isArchived: true),
        ),
      ];

      await pumpApp(
        tester,
        AlbumGrid(pieces: pieces, viewMode: ViewMode.grid, isArchived: true),
      );

      expect(find.byType(ArchiveThumbnail), findsNWidgets(2));
      expect(find.text('Archived 1'), findsOneWidget);
      expect(find.text('Archived 2'), findsOneWidget);
    });
  });
}
