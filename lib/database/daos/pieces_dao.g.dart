// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pieces_dao.dart';

// ignore_for_file: type=lint
mixin _$PiecesDaoMixin on DatabaseAccessor<AppDatabase> {
  $PiecesTable get pieces => attachedDatabase.pieces;
  $PhotosTable get photos => attachedDatabase.photos;
  PiecesDaoManager get managers => PiecesDaoManager(this);
}

class PiecesDaoManager {
  final _$PiecesDaoMixin _db;
  PiecesDaoManager(this._db);
  $$PiecesTableTableManager get pieces =>
      $$PiecesTableTableManager(_db.attachedDatabase, _db.pieces);
  $$PhotosTableTableManager get photos =>
      $$PhotosTableTableManager(_db.attachedDatabase, _db.photos);
}
