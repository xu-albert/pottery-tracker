// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'materials_dao.dart';

// ignore_for_file: type=lint
mixin _$MaterialsDaoMixin on DatabaseAccessor<AppDatabase> {
  $ClayOptionsTable get clayOptions => attachedDatabase.clayOptions;
  $GlazeOptionsTable get glazeOptions => attachedDatabase.glazeOptions;
  $PieceGlazesTable get pieceGlazes => attachedDatabase.pieceGlazes;
  $TagOptionsTable get tagOptions => attachedDatabase.tagOptions;
  $PieceTagsTable get pieceTags => attachedDatabase.pieceTags;
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
  $$TagOptionsTableTableManager get tagOptions =>
      $$TagOptionsTableTableManager(_db.attachedDatabase, _db.tagOptions);
  $$PieceTagsTableTableManager get pieceTags =>
      $$PieceTagsTableTableManager(_db.attachedDatabase, _db.pieceTags);
  $$PiecesTableTableManager get pieces =>
      $$PiecesTableTableManager(_db.attachedDatabase, _db.pieces);
}
