import 'package:drift/drift.dart';

class DeletedJunctions extends Table {
  TextColumn get id => text()();
  TextColumn get junctionType => text()(); // 'pieceGlazes' or 'pieceTags'
  TextColumn get pieceId => text()();
  TextColumn get optionId => text()(); // glazeOptionId or tagOptionId
  DateTimeColumn get deletedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
