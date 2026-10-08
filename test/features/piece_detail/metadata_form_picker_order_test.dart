import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pottery_tracker/database/daos/materials_dao.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/features/piece_detail/widgets/metadata_form.dart';
import 'package:pottery_tracker/l10n/app_localizations.dart';
import 'package:pottery_tracker/services/sync_queue.dart';
import 'package:pottery_tracker/services/sync_trigger.dart';

import '../../helpers/fixtures.dart';

class _MockMaterialsDao extends Mock implements MaterialsDao {}

class _MockSyncQueue extends Mock implements SyncQueue {}

/// The pickers list materials in the order set by dragging them in Manage
/// Clays/Glazes/Tags. Recently used ones are offered as pills under each
/// field, and do not jump the list.
void main() {
  late _MockMaterialsDao dao;
  final created = DateTime(2026);

  // The stored order, as the DAO returns it (by sortOrder), and a recent use
  // of the last one in each.
  const clayNames = ['Porcelain', 'Stoneware', 'Earthenware'];
  const glazeNames = ['Shino', 'Celadon', 'Tenmoku'];
  const tagNames = ['Sold', 'Gift', 'Test'];

  setUp(() {
    dao = _MockMaterialsDao();
    when(() => dao.getAllClays()).thenAnswer(
      (_) async => [
        for (final (i, name) in clayNames.indexed)
          ClayOption(id: name, name: name, sortOrder: i, createdAt: created),
      ],
    );
    when(() => dao.getAllGlazes()).thenAnswer(
      (_) async => [
        for (final (i, name) in glazeNames.indexed)
          GlazeOption(id: name, name: name, sortOrder: i, createdAt: created),
      ],
    );
    when(() => dao.getAllTags()).thenAnswer(
      (_) async => [
        for (final (i, name) in tagNames.indexed)
          TagOption(id: name, name: name, sortOrder: i, createdAt: created),
      ],
    );
    when(
      () => dao.getRecentClayNames(),
    ).thenAnswer((_) async => [clayNames.last]);
    when(
      () => dao.getRecentGlazeIds(),
    ).thenAnswer((_) async => [glazeNames.last]);
    when(() => dao.getRecentTagIds()).thenAnswer((_) async => [tagNames.last]);
  });

  Future<void> pumpForm(WidgetTester tester) async {
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
          body: SingleChildScrollView(
            child: MetadataForm(
              piece: makePiece(),
              materialsDao: dao,
              selectedGlazes: const [],
              selectedTags: const [],
              onUpdateField:
                  ({title, stage, clearStage = false, clayType, notes}) {},
              onUpdateGlazes: (_) async {},
              onUpdateTags: (_) async {},
              syncTrigger: SyncTrigger(_MockSyncQueue()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// [names] as the open picker sheet lists them, top first.
  List<String> listedInSheet(WidgetTester tester, List<String> names) {
    final sheet = find.byType(BottomSheet);
    final listed = [
      for (final name in names)
        if (find
            .descendant(of: sheet, matching: find.text(name))
            .evaluate()
            .isNotEmpty)
          name,
    ];
    double top(String name) => tester
        .getTopLeft(find.descendant(of: sheet, matching: find.text(name)))
        .dy;
    listed.sort((a, b) => top(a).compareTo(top(b)));
    return listed;
  }

  for (final (label, names) in [
    ('Clay', clayNames),
    ('Glazes', glazeNames),
    ('Tags', tagNames),
  ]) {
    testWidgets('the $label picker lists the stored order, with the recent '
        'one left in place', (tester) async {
      await pumpForm(tester);
      // The recent one is offered as a pill under the field.
      expect(find.text(names.last), findsOneWidget);

      await tester.tap(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(InputDecorator),
        ),
      );
      await tester.pumpAndSettle();

      expect(listedInSheet(tester, names), names);
    });
  }
}
