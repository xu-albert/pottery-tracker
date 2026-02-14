import 'package:drift/drift.dart';

class PieceTags extends Table {
  TextColumn get id => text()();
  TextColumn get pieceId => text()();
  TextColumn get tagOptionId => text()();

  @override
  Set<Column> get primaryKey => {id};
}
