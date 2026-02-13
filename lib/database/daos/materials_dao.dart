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
          ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
        .watch();
  }

  Future<List<ClayOption>> getAllClays() {
    return (select(clayOptions)
          ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
        .get();
  }

  Future<int> getNextSortOrder() async {
    final result = await (selectOnly(clayOptions)
          ..addColumns([clayOptions.sortOrder.max()]))
        .getSingleOrNull();
    final maxOrder = result?.read(clayOptions.sortOrder.max());
    return (maxOrder ?? -1) + 1;
  }

  Future<ClayOption> findOrCreateClay(String name) async {
    final trimmed = name.trim();
    final existing = await (select(clayOptions)
          ..where((c) => c.name.lower().equals(trimmed.toLowerCase())))
        .getSingleOrNull();
    if (existing != null) return existing;

    final nextOrder = await getNextSortOrder();
    final id = const Uuid().v4();
    final companion = ClayOptionsCompanion.insert(
      id: id,
      name: trimmed,
      sortOrder: Value(nextOrder),
      createdAt: DateTime.now(),
    );
    await into(clayOptions).insert(companion);
    return (select(clayOptions)
          ..where((c) => c.id.equals(id)))
        .getSingle();
  }

  Future<void> updateClayName(String id, String newName) {
    return (update(clayOptions)..where((c) => c.id.equals(id)))
        .write(ClayOptionsCompanion(name: Value(newName.trim())));
  }

  Future<void> deleteClay(String id) {
    return (delete(clayOptions)..where((c) => c.id.equals(id))).go();
  }

  Future<void> updateSortOrders(List<({String id, int sortOrder})> updates) {
    return batch((b) {
      for (final entry in updates) {
        b.update(
          clayOptions,
          ClayOptionsCompanion(sortOrder: Value(entry.sortOrder)),
          where: (c) => c.id.equals(entry.id),
        );
      }
    });
  }
}
