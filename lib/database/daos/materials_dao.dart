import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database.dart';
import '../tables/clay_options_table.dart';

part 'materials_dao.g.dart';

@DriftAccessor(tables: [ClayOptions])
class MaterialsDao extends DatabaseAccessor<AppDatabase>
    with _$MaterialsDaoMixin {
  MaterialsDao(super.db);

  Stream<List<ClayOption>> watchAllClays() {
    return (select(clayOptions)
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .watch();
  }

  Future<List<ClayOption>> getAllClays() {
    return (select(clayOptions)
          ..orderBy([(c) => OrderingTerm.asc(c.name)]))
        .get();
  }

  Future<ClayOption> findOrCreateClay(String name) async {
    final trimmed = name.trim();
    final existing = await (select(clayOptions)
          ..where((c) => c.name.lower().equals(trimmed.toLowerCase())))
        .getSingleOrNull();
    if (existing != null) return existing;

    final companion = ClayOptionsCompanion.insert(
      id: const Uuid().v4(),
      name: trimmed,
      createdAt: DateTime.now(),
    );
    await into(clayOptions).insert(companion);
    return (select(clayOptions)
          ..where((c) => c.id.equals(companion.id.value)))
        .getSingle();
  }

  Future<void> updateClayName(String id, String newName) {
    return (update(clayOptions)..where((c) => c.id.equals(id)))
        .write(ClayOptionsCompanion(name: Value(newName.trim())));
  }

  Future<void> deleteClay(String id) {
    return (delete(clayOptions)..where((c) => c.id.equals(id))).go();
  }
}
