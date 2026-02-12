import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'tables/pieces_table.dart';
import 'tables/photos_table.dart';
import 'daos/pieces_dao.dart';
import 'daos/photos_dao.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Pieces, Photos], daos: [PiecesDao, PhotosDao])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await migrator.addColumn(pieces, pieces.isArchived);
          }
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'pottery_tracker');
  }
}
