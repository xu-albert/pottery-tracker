import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import '../database/daos/pieces_dao.dart';
import '../database/daos/photos_dao.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final piecesDaoProvider = Provider<PiecesDao>((ref) {
  return ref.watch(databaseProvider).piecesDao;
});

final photosDaoProvider = Provider<PhotosDao>((ref) {
  return ref.watch(databaseProvider).photosDao;
});
