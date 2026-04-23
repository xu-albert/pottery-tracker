import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/database/daos/pieces_dao.dart';

Piece makePiece({
  String id = 'piece-1',
  String? title = 'Test Piece',
  String? stage,
  String? clayType,
  String? glazes,
  String? tags,
  String? notes,
  String? coverPhotoId,
  bool isArchived = false,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final now = DateTime(2025, 1, 1);
  return Piece(
    id: id,
    title: title,
    stage: stage,
    clayType: clayType,
    glazes: glazes,
    tags: tags,
    notes: notes,
    coverPhotoId: coverPhotoId,
    isArchived: isArchived,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
  );
}

Photo makePhoto({
  String id = 'photo-1',
  String pieceId = 'piece-1',
  String localPath = '/tmp/test_photo.jpg',
  String? thumbnailPath = '/tmp/test_photo_thumb.jpg',
  String? cloudUrl,
  DateTime? dateTaken,
  DateTime? createdAt,
  int sortOrder = 0,
}) {
  final now = DateTime(2025, 1, 1);
  return Photo(
    id: id,
    pieceId: pieceId,
    localPath: localPath,
    thumbnailPath: thumbnailPath,
    cloudUrl: cloudUrl,
    dateTaken: dateTaken ?? now,
    createdAt: createdAt ?? now,
    sortOrder: sortOrder,
  );
}

PieceWithCover makePieceWithCover({Piece? piece, Photo? coverPhoto}) {
  return PieceWithCover(piece: piece ?? makePiece(), coverPhoto: coverPhoto);
}
