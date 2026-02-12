import 'package:drift/drift.dart';

class Pieces extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().nullable()();
  TextColumn get stage => text().nullable()();
  TextColumn get clayType => text().nullable()();
  TextColumn get glazes => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get coverPhotoId => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
