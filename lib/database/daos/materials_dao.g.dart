// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'materials_dao.dart';

// ignore_for_file: type=lint
mixin _$MaterialsDaoMixin on DatabaseAccessor<AppDatabase> {
  $ClayOptionsTable get clayOptions => attachedDatabase.clayOptions;
  $GlazeOptionsTable get glazeOptions => attachedDatabase.glazeOptions;
  $PieceGlazesTable get pieceGlazes => attachedDatabase.pieceGlazes;
  $PiecesTable get pieces => attachedDatabase.pieces;
  MaterialsDaoManager get managers => MaterialsDaoManager(this);
}

class MaterialsDaoManager {
  final _$MaterialsDaoMixin _db;
  MaterialsDaoManager(this._db);
  $$ClayOptionsTableTableManager get clayOptions =>
      $$ClayOptionsTableTableManager(_db.attachedDatabase, _db.clayOptions);
  $$GlazeOptionsTableTableManager get glazeOptions =>
      $$GlazeOptionsTableTableManager(_db.attachedDatabase, _db.glazeOptions);
  $$PieceGlazesTableTableManager get pieceGlazes =>
      $$PieceGlazesTableTableManager(_db.attachedDatabase, _db.pieceGlazes);
  $$PiecesTableTableManager get pieces =>
      $$PiecesTableTableManager(_db.attachedDatabase, _db.pieces);
}
