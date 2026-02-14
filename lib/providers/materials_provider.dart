import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import '../database/daos/materials_dao.dart';
import 'database_provider.dart';

final materialsDaoProvider = Provider<MaterialsDao>((ref) {
  return ref.watch(databaseProvider).materialsDao;
});

final allClaysProvider = StreamProvider<List<ClayOption>>((ref) {
  return ref.watch(materialsDaoProvider).watchAllClays();
});

final allGlazesProvider = StreamProvider<List<GlazeOption>>((ref) {
  return ref.watch(materialsDaoProvider).watchAllGlazes();
});

final glazesForPieceProvider =
    StreamProvider.family<List<GlazeOption>, String>((ref, pieceId) {
  return ref.watch(materialsDaoProvider).watchGlazesForPiece(pieceId);
});

final allTagsProvider = StreamProvider<List<TagOption>>((ref) {
  return ref.watch(materialsDaoProvider).watchAllTags();
});

final tagsForPieceProvider =
    StreamProvider.family<List<TagOption>, String>((ref, pieceId) {
  return ref.watch(materialsDaoProvider).watchTagsForPiece(pieceId);
});
