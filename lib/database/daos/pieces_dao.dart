import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/pieces_table.dart';
import '../tables/photos_table.dart';

part 'pieces_dao.g.dart';

@DriftAccessor(tables: [Pieces, Photos])
class PiecesDao extends DatabaseAccessor<AppDatabase> with _$PiecesDaoMixin {
  PiecesDao(super.db);

  Future<void> insertPiece(PiecesCompanion piece) =>
      into(pieces).insert(piece);

  Future<void> updatePiece(PiecesCompanion piece) =>
      (update(pieces)..where((p) => p.id.equals(piece.id.value)))
          .write(piece);

  Future<void> deletePiece(String id) =>
      (delete(pieces)..where((p) => p.id.equals(id))).go();

  Future<Piece?> getPieceById(String id) =>
      (select(pieces)..where((p) => p.id.equals(id))).getSingleOrNull();

  Stream<List<PieceWithCover>> watchAllPieces({
    String? searchQuery,
    bool finishedOnly = false,
  }) {
    final pieceQuery = select(pieces).join([
      leftOuterJoin(photos, photos.id.equalsExp(pieces.coverPhotoId)),
    ]);

    if (searchQuery != null && searchQuery.isNotEmpty) {
      final q = '%$searchQuery%';
      pieceQuery.where(
        pieces.title.like(q) |
            pieces.clayType.like(q) |
            pieces.glazes.like(q) |
            pieces.notes.like(q),
      );
    }

    if (finishedOnly) {
      pieceQuery.where(pieces.stage.equals('glazed'));
    }

    pieceQuery.orderBy([OrderingTerm.desc(pieces.updatedAt)]);

    return pieceQuery.watch().map((rows) => rows.map((row) {
          return PieceWithCover(
            piece: row.readTable(pieces),
            coverPhoto: row.readTableOrNull(photos),
          );
        }).toList());
  }
}

class PieceWithCover {
  final Piece piece;
  final Photo? coverPhoto;

  PieceWithCover({required this.piece, this.coverPhoto});
}
