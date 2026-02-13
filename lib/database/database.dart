import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';
import 'tables/pieces_table.dart';
import 'tables/photos_table.dart';
import 'tables/clay_options_table.dart';
import 'daos/pieces_dao.dart';
import 'daos/photos_dao.dart';
import 'daos/materials_dao.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [Pieces, Photos, ClayOptions],
  daos: [PiecesDao, PhotosDao, MaterialsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

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
              await into(clayOptions).insert(ClayOptionsCompanion.insert(
                id: const Uuid().v4(),
                name: name,
                createdAt: DateTime.now(),
              ));
            }
          }
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'pottery_tracker');
  }
}
