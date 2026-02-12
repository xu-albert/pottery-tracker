// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photos_dao.dart';

// ignore_for_file: type=lint
mixin _$PhotosDaoMixin on DatabaseAccessor<AppDatabase> {
  $PiecesTable get pieces => attachedDatabase.pieces;
  $PhotosTable get photos => attachedDatabase.photos;
  PhotosDaoManager get managers => PhotosDaoManager(this);
}

class PhotosDaoManager {
  final _$PhotosDaoMixin _db;
  PhotosDaoManager(this._db);
  $$PiecesTableTableManager get pieces =>
      $$PiecesTableTableManager(_db.attachedDatabase, _db.pieces);
  $$PhotosTableTableManager get photos =>
      $$PhotosTableTableManager(_db.attachedDatabase, _db.photos);
}
