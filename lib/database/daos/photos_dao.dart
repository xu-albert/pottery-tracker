import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/photos_table.dart';

part 'photos_dao.g.dart';

@DriftAccessor(tables: [Photos])
class PhotosDao extends DatabaseAccessor<AppDatabase> with _$PhotosDaoMixin {
  PhotosDao(super.db);

  Future<void> insertPhoto(PhotosCompanion photo) => into(photos).insert(photo);

  Future<void> updatePhoto(PhotosCompanion photo) =>
      (update(photos)..where((p) => p.id.equals(photo.id.value))).write(photo);

  Future<void> deletePhoto(String id) =>
      (delete(photos)..where((p) => p.id.equals(id))).go();

  Future<Photo?> getPhotoById(String id) =>
      (select(photos)..where((p) => p.id.equals(id))).getSingleOrNull();

  Stream<List<Photo>> watchPhotosForPiece(String pieceId) {
    return (select(photos)
          ..where((p) => p.pieceId.equals(pieceId))
          ..orderBy([(p) => OrderingTerm.desc(p.sortOrder)]))
        .watch();
  }

  Future<List<Photo>> getPhotosForPiece(String pieceId) {
    return (select(photos)
          ..where((p) => p.pieceId.equals(pieceId))
          ..orderBy([(p) => OrderingTerm.desc(p.sortOrder)]))
        .get();
  }

  Future<int> getNextSortOrder(String pieceId) async {
    final result =
        await (selectOnly(photos)
              ..addColumns([photos.sortOrder.max()])
              ..where(photos.pieceId.equals(pieceId)))
            .getSingleOrNull();
    final maxOrder = result?.read(photos.sortOrder.max());
    return (maxOrder ?? -1) + 1;
  }

  Future<void> deletePhotosForPiece(String pieceId) =>
      (delete(photos)..where((p) => p.pieceId.equals(pieceId))).go();

  Future<void> updateSortOrders(List<({String id, int sortOrder})> updates) {
    return batch((b) {
      for (final entry in updates) {
        b.update(
          photos,
          PhotosCompanion(sortOrder: Value(entry.sortOrder)),
          where: (p) => p.id.equals(entry.id),
        );
      }
    });
  }
}
