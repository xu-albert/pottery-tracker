import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pottery_tracker/features/create_piece/screens/create_piece_screen.dart';
import 'package:pottery_tracker/l10n/app_localizations.dart';
import 'package:pottery_tracker/providers/image_service_provider.dart';
import 'package:pottery_tracker/providers/piece_writer_provider.dart';
import 'package:pottery_tracker/services/image_service.dart';
import 'package:pottery_tracker/services/piece_writer.dart';

/// The real service, refusing the way it does for a photo it cannot strip:
/// every re-encode fails. Only the picker is replaced, because it opens the
/// system photo library.
class _RefusingImageService extends ImageService {
  _RefusingImageService(this._picked)
    : super(
        compress:
            (
              input, {
              int quality = 95,
              int minWidth = 1920,
              int minHeight = 1080,
            }) async => throw Exception('cannot decode this photo'),
      );

  final List<XFile> _picked;

  @override
  Future<List<XFile>?> pickMultipleImages() async => _picked;
}

class _CountingPieceWriter extends Fake implements PieceWriter {
  int creates = 0;

  @override
  Future<String> createPiece({
    required String pieceId,
    required List<ImageResult> photos,
  }) async {
    creates++;
    return pieceId;
  }
}

void main() {
  testWidgets('a photo refused for the data it could not strip is reported, '
      'and no piece is created from it', (tester) async {
    final writer = _CountingPieceWriter();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Album')),
        ),
        GoRoute(path: '/create', builder: (_, _) => const CreatePieceScreen()),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageServiceProvider.overrideWithValue(
            _RefusingImageService([
              XFile.fromData(Uint8List.fromList([1, 2, 3])),
            ]),
          ),
          pieceWriterProvider.overrideWithValue(writer),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
        ),
      ),
    );
    router.push('/create');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Photo Library'));
    await tester.pumpAndSettle();

    expect(find.text('1 photo(s) could not be added'), findsOneWidget);
    expect(writer.creates, 0);
    expect(find.text('Album'), findsOneWidget);
  });
}
