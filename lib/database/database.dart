import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:uuid/uuid.dart';

import 'sqlcipher_guard.dart';
import 'tables/pieces_table.dart';
import 'tables/photos_table.dart';
import 'tables/clay_options_table.dart';
import 'tables/glaze_options_table.dart';
import 'tables/piece_glazes_table.dart';
import 'tables/tag_options_table.dart';
import 'tables/piece_tags_table.dart';
import 'tables/deleted_junctions_table.dart';
import 'daos/pieces_dao.dart';
import 'daos/photos_dao.dart';
import 'daos/materials_dao.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Pieces,
    Photos,
    ClayOptions,
    GlazeOptions,
    PieceGlazes,
    TagOptions,
    PieceTags,
    DeletedJunctions,
  ],
  daos: [PiecesDao, PhotosDao, MaterialsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.forTesting(super.executor);

  /// The database file's name inside the app's documents directory.
  static const fileName = 'pottery_tracker.db';

  /// Points `package:sqlite3` at the SQLCipher build instead of the system or
  /// bundled sqlite3, on the platforms that ship one.
  ///
  /// Idempotent, and called before anything opens a database — the main one
  /// or the transfer backup — because the override has to be in place before
  /// `sqlite3` is first touched in the process.
  static void useSqlCipherLibrary() {
    if (Platform.isAndroid) {
      sqlite_open.open.overrideFor(
        sqlite_open.OperatingSystem.android,
        openCipherOnAndroid,
      );
    } else if (Platform.isIOS) {
      sqlite_open.open.overrideFor(
        sqlite_open.OperatingSystem.iOS,
        () => DynamicLibrary.open('SQLCipher.framework/SQLCipher'),
      );
    }
  }

  /// Opens [file] as a SQLCipher database keyed with [key].
  ///
  /// Which key, and whether this device may open this file at all, is decided
  /// by `LocalDatabaseBootstrap` before this is called. The `setup` callback
  /// is the one place `configureSqlCipher` guards the real database; it is
  /// exercised only on a device, never by `flutter test`, so it must not be
  /// refactored away without a device run.
  static Future<AppDatabase> open(File file, String key) async {
    useSqlCipherLibrary();

    final executor = NativeDatabase(
      file,
      setup: (rawDb) => configureSqlCipher(rawDb, key),
    );

    return AppDatabase(executor);
  }

  /// Re-encrypts the open database under [key], in place.
  ///
  /// Quoted and, on failure, redacted the way `configureSqlCipher` handles
  /// `PRAGMA key`: sqlite3 cannot bind a pragma value, so the key is a
  /// literal in the statement, and sqlite3 quotes the statement in its
  /// error — which is logged, shown and reported — so that error never
  /// leaves here as it came.
  Future<void> rekey(String key) async {
    try {
      await customStatement('PRAGMA rekey = ${sqlKeyLiteral(key)}');
    } on SqliteException catch (error) {
      throw keyingFailure(error, key);
    }
  }

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(pieces, pieces.isArchived);
      }
      if (from < 3) {
        await migrator.createTable(clayOptions);
        // Migrate existing clayType values into the clay_options library
        final rows = await customSelect(
          'SELECT DISTINCT clay_type FROM pieces WHERE clay_type IS NOT NULL AND clay_type != \'\'',
        ).get();
        for (final row in rows) {
          final name = row.read<String>('clay_type');
          await into(clayOptions).insert(
            ClayOptionsCompanion.insert(
              id: const Uuid().v4(),
              name: name,
              createdAt: DateTime.now(),
            ),
          );
        }
      }
      if (from < 4) {
        // Only a database already at 3 has a clay_options without `sort_order`;
        // below 3 the step above creates the table from the current definition,
        // which already has it. The backfill runs either way, so both paths
        // reach 4 numbered alphabetically.
        if (from >= 3) {
          await migrator.addColumn(clayOptions, clayOptions.sortOrder);
        }
        // Backfill existing clays with sort orders in alphabetical order
        final existing = await customSelect(
          'SELECT id FROM clay_options ORDER BY name ASC',
        ).get();
        for (var i = 0; i < existing.length; i++) {
          await customUpdate(
            'UPDATE clay_options SET sort_order = ? WHERE id = ?',
            variables: [
              Variable.withInt(i),
              Variable.withString(existing[i].read<String>('id')),
            ],
            updates: {clayOptions},
          );
        }
      }
      if (from < 5) {
        await migrator.createTable(glazeOptions);
        await migrator.createTable(pieceGlazes);

        // Migrate existing free-text glazes into the glaze library + junction table
        final piecesWithGlazes = await customSelect(
          'SELECT id, glazes FROM pieces WHERE glazes IS NOT NULL AND glazes != \'\'',
        ).get();

        // Collect all unique glaze names (case-insensitive dedup)
        final seenLower = <String, String>{}; // lowercase → canonical name
        final glazeIdMap =
            <String, String>{}; // canonical name → glaze option id
        var sortOrder = 0;

        for (final row in piecesWithGlazes) {
          final glazesText = row.read<String>('glazes');
          final names = glazesText
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty);
          for (final name in names) {
            final lower = name.toLowerCase();
            if (!seenLower.containsKey(lower)) {
              seenLower[lower] = name;
              final glazeId = const Uuid().v4();
              glazeIdMap[name] = glazeId;
              await customInsert(
                'INSERT INTO glaze_options (id, name, sort_order, created_at) VALUES (?, ?, ?, ?)',
                variables: [
                  Variable.withString(glazeId),
                  Variable.withString(name),
                  Variable.withInt(sortOrder),
                  Variable.withDateTime(DateTime.now()),
                ],
                updates: {glazeOptions},
              );
              sortOrder++;
            }
          }
        }

        // Create junction rows
        for (final row in piecesWithGlazes) {
          final pieceId = row.read<String>('id');
          final glazesText = row.read<String>('glazes');
          final names = glazesText
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          for (var i = 0; i < names.length; i++) {
            final canonical = seenLower[names[i].toLowerCase()]!;
            final glazeOptionId = glazeIdMap[canonical]!;
            await customInsert(
              'INSERT INTO piece_glazes (id, piece_id, glaze_option_id, sort_order) VALUES (?, ?, ?, ?)',
              variables: [
                Variable.withString(const Uuid().v4()),
                Variable.withString(pieceId),
                Variable.withString(glazeOptionId),
                Variable.withInt(i),
              ],
              updates: {pieceGlazes},
            );
          }
        }
      }
      if (from < 6) {
        await migrator.createTable(tagOptions);
        await migrator.createTable(pieceTags);
        await migrator.addColumn(pieces, pieces.tags);
      }
      // Only a database already sitting at 6 has a tag_options built by a v6
      // binary, whose Dart definition had no `color`; below 6 the step above
      // creates the table from the current definition, `color` included —
      // same shape as the clay sort_order step.
      if (from >= 6 && from < 7) {
        await migrator.addColumn(tagOptions, tagOptions.color);
      }
      if (from < 8) {
        await migrator.createTable(deletedJunctions);
      }
      if (from < 9) {
        await migrator.addColumn(pieces, pieces.displayDate);
      }
    },
  );
}
