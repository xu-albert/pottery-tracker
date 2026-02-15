import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_colors.dart';
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

final tagColorMapProvider = Provider<Map<String, Color>>((ref) {
  final tagsAsync = ref.watch(allTagsProvider);
  return tagsAsync.when(
    data: (tags) {
      final map = <String, Color>{};
      for (final tag in tags) {
        if (tag.color != null) {
          map[tag.name] = TagColorPresets.hexToColor(tag.color!);
        }
      }
      return map;
    },
    loading: () => {},
    error: (_, _) => {},
  );
});
