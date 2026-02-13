import 'package:drift/drift.dart';

class PieceGlazes extends Table {
  TextColumn get id => text()();
  TextColumn get pieceId => text()();
  TextColumn get glazeOptionId => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
