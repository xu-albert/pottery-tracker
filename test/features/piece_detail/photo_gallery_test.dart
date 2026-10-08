import 'package:flutter/cupertino.dart' show CupertinoAlertDialog;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/features/piece_detail/widgets/photo_gallery.dart';
import 'package:pottery_tracker/l10n/app_localizations.dart';

import '../../helpers/fixtures.dart';

void main() {
  group('long-press delete', () {
    late List<Photo> deleted;

    setUp(() => deleted = []);

    Future<void> openDeleteConfirmation(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            // The last photo cannot be deleted, so the menu needs two.
            body: PhotoGallery(
              photos: [
                makePhoto(),
                makePhoto(id: 'photo-2'),
              ],
              onDelete: deleted.add,
            ),
          ),
        ),
      );
      await tester.longPress(find.byType(Image).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Photo'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks before deleting', (tester) async {
      await openDeleteConfirmation(tester);

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.text('Delete Photo?'), findsOneWidget);
      expect(
        find.text('This photo will be permanently deleted.'),
        findsOneWidget,
      );
      expect(deleted, isEmpty, reason: 'nothing is deleted until confirmed');
    });

    testWidgets('cancelling keeps the photo', (tester) async {
      await openDeleteConfirmation(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(deleted, isEmpty);
    });

    testWidgets('confirming deletes that photo', (tester) async {
      await openDeleteConfirmation(tester);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(deleted.map((p) => p.id), ['photo-1']);
    });
  });
}
