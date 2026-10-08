import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/features/settings/screens/manage_clays_screen.dart';
import 'package:pottery_tracker/features/settings/screens/manage_glazes_screen.dart';
import 'package:pottery_tracker/features/settings/screens/manage_tags_screen.dart';
import 'package:pottery_tracker/l10n/app_localizations.dart';
import 'package:pottery_tracker/providers/materials_provider.dart';
import 'package:pottery_tracker/providers/sync_provider.dart';
import 'package:pottery_tracker/services/material_writer.dart';

/// Records the order each drop saves, as `kind: id, id, ...`. What a save
/// writes and queues is `material_writer_test.dart`'s, against a real
/// database and queue.
class _RecordingWriter implements MaterialWriter {
  final saved = <String>[];

  @override
  Future<void> reorderClays(List<String> orderedIds) async =>
      saved.add('clays: ${orderedIds.join(', ')}');

  @override
  Future<void> reorderGlazes(List<String> orderedIds) async =>
      saved.add('glazes: ${orderedIds.join(', ')}');

  @override
  Future<void> reorderTags(List<String> orderedIds) async =>
      saved.add('tags: ${orderedIds.join(', ')}');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} not used in this test',
  );
}

final _created = DateTime(2026);

List<ClayOption> _clays(List<String> names) => [
  for (var i = 0; i < names.length; i++)
    ClayOption(id: names[i], name: names[i], sortOrder: i, createdAt: _created),
];

void main() {
  late _RecordingWriter writer;

  setUp(() => writer = _RecordingWriter());

  /// The stream stands in for the database's: a test pushes what it would
  /// deliver after a write.
  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    StreamController<List<ClayOption>>? clays,
    List<GlazeOption> glazes = const [],
    List<TagOption> tags = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          materialWriterProvider.overrideWithValue(writer),
          if (clays != null)
            allClaysProvider.overrideWith((ref) => clays.stream),
          allGlazesProvider.overrideWith((ref) => Stream.value(glazes)),
          allTagsProvider.overrideWith((ref) => Stream.value(tags)),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: screen,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Drags the row named [name] by its handle, [rows] rows down (negative
  /// for up), pumping frames between moves as a finger would.
  Future<void> dragRow(WidgetTester tester, String name, int rows) async {
    final card = find.ancestor(
      of: find.text(name),
      matching: find.byType(Card),
    );
    final handle = find.descendant(
      of: card,
      matching: find.byIcon(Icons.drag_handle),
    );
    final rowHeight = tester.getSize(card).height;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, rows * rowHeight * 1.15 / 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    // The drop animation; the list itself has nothing else animating.
    await tester.pump(const Duration(seconds: 1));
  }

  /// [names] as they appear on screen, top first.
  List<String> shown(WidgetTester tester, Iterable<String> names) {
    final visible = [
      for (final name in names)
        if (find.text(name).evaluate().isNotEmpty) name,
    ];
    visible.sort(
      (a, b) => tester
          .getTopLeft(find.text(a))
          .dy
          .compareTo(tester.getTopLeft(find.text(b)).dy),
    );
    return visible;
  }

  const names = ['Stoneware', 'Porcelain', 'Earthenware'];

  group('Manage Clays', () {
    testWidgets('lists clays in their stored order, each with a handle', (
      tester,
    ) async {
      final clays = StreamController<List<ClayOption>>();
      addTearDown(clays.close);
      await pumpScreen(tester, const ManageClaysScreen(), clays: clays);
      clays.add(_clays(names));
      await tester.pump();

      expect(shown(tester, names), names);
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));
    });

    testWidgets('a drop saves the whole new order and shows it before the '
        'save comes back', (tester) async {
      final clays = StreamController<List<ClayOption>>();
      addTearDown(clays.close);
      await pumpScreen(tester, const ManageClaysScreen(), clays: clays);
      clays.add(_clays(names));
      await tester.pump();

      await dragRow(tester, 'Earthenware', -2);

      expect(writer.saved, ['clays: Earthenware, Stoneware, Porcelain']);
      expect(
        shown(tester, names),
        ['Earthenware', 'Stoneware', 'Porcelain'],
        reason: 'the row must not snap back while the write is in flight',
      );

      // The database then delivers the saved order, and later some other
      // order (a pull from another device): the stream's word wins.
      clays.add(_clays(['Earthenware', 'Stoneware', 'Porcelain']));
      await tester.pump();
      expect(shown(tester, names), ['Earthenware', 'Stoneware', 'Porcelain']);
      clays.add(_clays(['Porcelain', 'Earthenware', 'Stoneware']));
      await tester.pump();
      expect(shown(tester, names), ['Porcelain', 'Earthenware', 'Stoneware']);
    });

    testWidgets('a second drop before the first is saved builds on it', (
      tester,
    ) async {
      final clays = StreamController<List<ClayOption>>();
      addTearDown(clays.close);
      await pumpScreen(tester, const ManageClaysScreen(), clays: clays);
      clays.add(_clays(names));
      await tester.pump();

      await dragRow(tester, 'Earthenware', -2);
      await dragRow(tester, 'Porcelain', -1);

      expect(writer.saved.last, 'clays: Earthenware, Porcelain, Stoneware');
    });

    testWidgets('a search hides the handles, and clearing it brings them '
        'back', (tester) async {
      final clays = StreamController<List<ClayOption>>();
      addTearDown(clays.close);
      await pumpScreen(tester, const ManageClaysScreen(), clays: clays);
      clays.add(_clays(names));
      await tester.pump();

      await tester.enterText(find.byType(EditableText), 'porc');
      await tester.pump();
      expect(shown(tester, names), ['Porcelain']);
      expect(
        find.byIcon(Icons.drag_handle),
        findsNothing,
        reason: 'a drag in a filtered subset has no place in the whole list',
      );

      await tester.enterText(find.byType(EditableText), '');
      await tester.pump();
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));
    });
  });

  testWidgets('Manage Glazes saves a drop the same way', (tester) async {
    await pumpScreen(
      tester,
      const ManageGlazesScreen(),
      glazes: [
        for (final (i, name) in ['Celadon', 'Tenmoku'].indexed)
          GlazeOption(id: name, name: name, sortOrder: i, createdAt: _created),
      ],
    );

    await dragRow(tester, 'Tenmoku', -1);

    expect(writer.saved, ['glazes: Tenmoku, Celadon']);
    expect(shown(tester, ['Celadon', 'Tenmoku']), ['Tenmoku', 'Celadon']);
  });

  testWidgets('Manage Tags saves a drop the same way', (tester) async {
    await pumpScreen(
      tester,
      const ManageTagsScreen(),
      tags: [
        for (final (i, name) in ['Gift', 'Sold'].indexed)
          TagOption(id: name, name: name, sortOrder: i, createdAt: _created),
      ],
    );

    await dragRow(tester, 'Gift', 1);

    expect(writer.saved, ['tags: Sold, Gift']);
    expect(shown(tester, ['Gift', 'Sold']), ['Sold', 'Gift']);
  });
}
