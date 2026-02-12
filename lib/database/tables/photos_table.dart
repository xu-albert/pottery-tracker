import 'package:drift/drift.dart';
import 'pieces_table.dart';

class Photos extends Table {
  TextColumn get id => text()();
  TextColumn get pieceId => text().references(Pieces, #id)();
  TextColumn get localPath => text()();
  TextColumn get thumbnailPath => text().nullable()();
  TextColumn get cloudUrl => text().nullable()();
  DateTimeColumn get dateTaken => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
