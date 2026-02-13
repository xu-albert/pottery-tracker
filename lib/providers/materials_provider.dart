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
