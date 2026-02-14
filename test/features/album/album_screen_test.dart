import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/daos/pieces_dao.dart';
import 'package:pottery_tracker/features/album/screens/album_screen.dart';
import 'package:pottery_tracker/l10n/app_localizations.dart';
import 'package:pottery_tracker/providers/pieces_provider.dart';
import 'package:pottery_tracker/providers/database_provider.dart';
import 'package:pottery_tracker/providers/materials_provider.dart';
import 'package:pottery_tracker/providers/photos_provider.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/mock_providers.dart';
import '../../helpers/test_helpers.dart';

void main() {
  group('AlbumScreen', () {
    testWidgets('shows loading indicator while data loads', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            filteredPiecesProvider.overrideWith(
              (ref) => Stream<List<PieceWithCover>>.empty(),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en')],
            home: const Scaffold(body: AlbumScreen()),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows empty state when no pieces', (tester) async {
      await pumpApp(
        tester,
        const AlbumScreen(),
        overrides: [
          filteredPiecesProvider.overrideWith(
            (ref) => Stream.value(<PieceWithCover>[]),
          ),
        ],
      );

      expect(find.text('No pieces yet'), findsOneWidget);
    });

    testWidgets('renders pieces when data available', (tester) async {
      final mockPiecesDao = MockPiecesDao();
      await pumpApp(
        tester,
        const AlbumScreen(),
        overrides: [
          filteredPiecesProvider.overrideWith(
            (ref) => Stream.value([
              makePieceWithCover(
                  piece: makePiece(id: 'p1', title: 'My Bowl')),
              makePieceWithCover(
                  piece: makePiece(id: 'p2', title: 'My Cup')),
            ]),
          ),
          piecesDaoProvider.overrideWithValue(mockPiecesDao),
          tagColorMapProvider.overrideWithValue(<String, Color>{}),
          photosForPieceProvider('p1')
              .overrideWith((ref) => Stream.value([])),
          photosForPieceProvider('p2')
              .overrideWith((ref) => Stream.value([])),
        ],
      );

      expect(find.text('My Bowl'), findsOneWidget);
      expect(find.text('My Cup'), findsOneWidget);
    });

    testWidgets('shows error message on error', (tester) async {
      await pumpApp(
        tester,
        const AlbumScreen(),
        overrides: [
          filteredPiecesProvider.overrideWith(
            (ref) => Stream<List<PieceWithCover>>.error('Something broke'),
          ),
        ],
      );

      expect(find.textContaining('Error'), findsOneWidget);
    });
  });
}
