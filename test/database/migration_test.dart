import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:sqlite3/sqlite3.dart';

/// The checked-in DDL for the historical schema versions.
///
/// The fixtures live in the repository rather than being reconstructed from
/// `git show`, so a shallow CI clone still runs these tests.
final _fixtureDir = Directory('test/database/fixtures');

/// The schema versions a device can still be sitting on, read from the
/// fixture directory so a newly checked-in fixture is walked without anyone
/// having to remember a second list.
final _historicalVersions = () {
  final fileName = RegExp(r'^schema_v(\d+)\.sql$');
  return _fixtureDir
      .listSync()
      .map((entity) => fileName.firstMatch(entity.uri.pathSegments.last))
      .whereType<RegExpMatch>()
      .map((match) => int.parse(match.group(1)!))
      .toList()
    ..sort();
}();

String _fixtureSql(int version) =>
    File('${_fixtureDir.path}/schema_v$version.sql').readAsStringSync();

/// Opens an in-memory database seeded with [version]'s schema, then hands it to
/// [AppDatabase] so the real [MigrationStrategy] upgrades it on first query.
Database _seed(int version) {
  final raw = sqlite3.openInMemory();
  raw.execute(_fixtureSql(version));
  raw.userVersion = version;
  return raw;
}

AppDatabase _openAt(int version) =>
    AppDatabase.forTesting(NativeDatabase.opened(_seed(version)));

/// Column names of [table], in `pragma table_info` order.
Future<List<String>> _columnsOf(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return rows.map((r) => r.read<String>('name')).toList();
}

Future<Set<String>> _tablesOf(AppDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      )
      .get();
  return rows.map((r) => r.read<String>('name')).toSet();
}

void main() {
  // `schemaVersion` is a plain getter, so this never opens the executor.
  final currentVersion = AppDatabase.forTesting(
    NativeDatabase.memory(),
  ).schemaVersion;

  // What a device that installed the current version fresh ends up with. Every
  // upgrade path has to arrive at the same place.
  late Set<String> currentTables;
  late Map<String, Set<String>> currentColumns;

  setUpAll(() async {
    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    currentTables = await _tablesOf(fresh);
    currentColumns = {
      for (final table in currentTables)
        table: (await _columnsOf(fresh, table)).toSet(),
    };
    await fresh.close();
  });

  test('every schema version below the current one has a fixture', () {
    expect(
      _historicalVersions,
      List.generate(currentVersion - 1, (i) => i + 1),
      reason:
          '${_fixtureDir.path} must hold exactly schema_v1.sql through '
          'schema_v${currentVersion - 1}.sql — bumping schemaVersion means '
          'checking in a fixture for the version it replaced, and every '
          'fixture there is walked to the current schema',
    );
  });

  for (final version in _historicalVersions) {
    test(
      'upgrading from schema version $version lands on the current schema',
      () async {
        final db = _openAt(version);
        addTearDown(db.close);

        // The first query is what drives onUpgrade. Before the `color` guard
        // this threw `duplicate column name: color` for versions 1 through 5.
        await db.customSelect('SELECT 1').get();

        expect(await _tablesOf(db), currentTables);
        for (final table in currentTables) {
          expect(
            (await _columnsOf(db, table)).toSet(),
            currentColumns[table],
            reason: 'table $table differs from a fresh install',
          );
        }
      },
    );
  }

  test('a version 1 piece survives the whole upgrade', () async {
    final raw = _seed(1);
    raw.execute(
      'INSERT INTO pieces (id, title, clay_type, glazes, created_at, updated_at) '
      "VALUES ('p1', 'First bowl', 'Stoneware', 'Celadon, Tenmoku', 0, 0)",
    );
    raw.execute(
      'INSERT INTO pieces (id, title, clay_type, created_at, updated_at) '
      "VALUES ('p2', 'Tall vase', 'Porcelain', 0, 0)",
    );
    raw.execute(
      'INSERT INTO pieces (id, title, clay_type, created_at, updated_at) '
      "VALUES ('p3', 'Plate', 'Brown', 0, 0)",
    );
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final piece = await db.piecesDao.getPieceById('p1');
    expect(piece, isNotNull);
    expect(piece!.title, 'First bowl');
    expect(piece.isArchived, isFalse);
    expect(piece.displayDate, isNull);

    // The version 3 and 5 steps backfill the clay and glaze libraries from the
    // free-text columns they replaced, and the version 4 step numbers the
    // clays alphabetically — a database that skipped straight past 3 has to
    // land on the same numbering a device upgrading from 3 gets, or the clay
    // library reads back in storage order.
    final clays = await db.materialsDao.getAllClays();
    expect(clays.map((c) => c.name), ['Brown', 'Porcelain', 'Stoneware']);
    expect(clays.map((c) => c.sortOrder), [0, 1, 2]);
    final glazes = await db.select(db.glazeOptions).get();
    expect(glazes.map((g) => g.name), containsAll(['Celadon', 'Tenmoku']));
    expect(await db.select(db.pieceGlazes).get(), hasLength(2));
  });

  test('the migrated database is writable through the DAOs', () async {
    final db = _openAt(5);
    addTearDown(db.close);

    await db.piecesDao.insertPiece(
      PiecesCompanion(
        id: const Value('p2'),
        title: const Value('Mug'),
        displayDate: Value(DateTime(2026, 1, 1)),
        createdAt: Value(DateTime(2026, 1, 1)),
        updatedAt: Value(DateTime(2026, 1, 1)),
      ),
    );
    final (tag, created) = await db.materialsDao.findOrCreateTag('kiln 3');
    expect(created, isTrue);
    await db.materialsDao.updateTagColor(tag.id, '#FF8800');

    final tags = await db.select(db.tagOptions).get();
    expect(tags.single.color, '#FF8800');
    expect((await db.piecesDao.getPieceById('p2'))!.title, 'Mug');
  });
}
