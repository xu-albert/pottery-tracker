import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_colors.dart';
import '../database.dart';
import '../tables/clay_options_table.dart';
import '../tables/glaze_options_table.dart';
import '../tables/piece_glazes_table.dart';
import '../tables/tag_options_table.dart';
import '../tables/piece_tags_table.dart';
import '../tables/pieces_table.dart';
import '../tables/deleted_junctions_table.dart';

part 'materials_dao.g.dart';

@DriftAccessor(
  tables: [
    ClayOptions,
    GlazeOptions,
    PieceGlazes,
    TagOptions,
    PieceTags,
    Pieces,
    DeletedJunctions,
  ],
)
class MaterialsDao extends DatabaseAccessor<AppDatabase>
    with _$MaterialsDaoMixin {
  MaterialsDao(super.db);

  // ── Clay methods ──

  Stream<List<ClayOption>> watchAllClays() {
    return (select(
      clayOptions,
    )..orderBy([(c) => OrderingTerm.asc(c.sortOrder)])).watch();
  }

  Future<List<ClayOption>> getAllClays() {
    return (select(
      clayOptions,
    )..orderBy([(c) => OrderingTerm.asc(c.sortOrder)])).get();
  }

  Future<int> getNextSortOrder() async {
    final result = await (selectOnly(
      clayOptions,
    )..addColumns([clayOptions.sortOrder.max()])).getSingleOrNull();
    final maxOrder = result?.read(clayOptions.sortOrder.max());
    return (maxOrder ?? -1) + 1;
  }

  Future<ClayOption> findOrCreateClay(String name) async {
    final trimmed = name.trim();
    final existing =
        await (select(clayOptions)
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
    return (select(clayOptions)..where((c) => c.id.equals(id))).getSingle();
  }

  Future<void> updateClayName(String id, String newName) async {
    final trimmed = newName.trim();
    // Get the old name first
    final old = await (select(
      clayOptions,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    if (old == null) return;

    // Update the clay option
    await (update(clayOptions)..where((c) => c.id.equals(id))).write(
      ClayOptionsCompanion(name: Value(trimmed)),
    );

    // Propagate rename to all pieces using this clay
    await customUpdate(
      'UPDATE pieces SET clay_type = ?, updated_at = ? WHERE clay_type = ?',
      variables: [
        Variable.withString(trimmed),
        Variable.withDateTime(DateTime.now()),
        Variable.withString(old.name),
      ],
      updates: {pieces},
    );
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

  // ── Glaze library methods ──

  Stream<List<GlazeOption>> watchAllGlazes() {
    return (select(
      glazeOptions,
    )..orderBy([(g) => OrderingTerm.asc(g.sortOrder)])).watch();
  }

  Future<List<GlazeOption>> getAllGlazes() {
    return (select(
      glazeOptions,
    )..orderBy([(g) => OrderingTerm.asc(g.sortOrder)])).get();
  }

  Future<int> getNextGlazeSortOrder() async {
    final result = await (selectOnly(
      glazeOptions,
    )..addColumns([glazeOptions.sortOrder.max()])).getSingleOrNull();
    final maxOrder = result?.read(glazeOptions.sortOrder.max());
    return (maxOrder ?? -1) + 1;
  }

  Future<GlazeOption> findOrCreateGlaze(String name) async {
    final trimmed = name.trim();
    final existing =
        await (select(glazeOptions)
              ..where((g) => g.name.lower().equals(trimmed.toLowerCase())))
            .getSingleOrNull();
    if (existing != null) return existing;

    final nextOrder = await getNextGlazeSortOrder();
    final id = const Uuid().v4();
    final companion = GlazeOptionsCompanion.insert(
      id: id,
      name: trimmed,
      sortOrder: Value(nextOrder),
      createdAt: DateTime.now(),
    );
    await into(glazeOptions).insert(companion);
    return (select(glazeOptions)..where((g) => g.id.equals(id))).getSingle();
  }

  Future<void> updateGlazeName(String id, String newName) async {
    final trimmed = newName.trim();

    // Update the glaze option
    await (update(glazeOptions)..where((g) => g.id.equals(id))).write(
      GlazeOptionsCompanion(name: Value(trimmed)),
    );

    // Rebuild denormalized glazes column for all affected pieces
    final junctionRows = await (select(
      pieceGlazes,
    )..where((pg) => pg.glazeOptionId.equals(id))).get();
    final affectedPieceIds = junctionRows.map((r) => r.pieceId).toSet();
    for (final pieceId in affectedPieceIds) {
      await _rebuildDenormalizedGlazesForPiece(pieceId);
    }
  }

  Future<void> deleteGlaze(String id) async {
    // Find affected pieces before deleting
    final junctionRows = await (select(
      pieceGlazes,
    )..where((pg) => pg.glazeOptionId.equals(id))).get();
    final affectedPieceIds = junctionRows.map((r) => r.pieceId).toSet();

    // Delete junction rows and the glaze option
    await (delete(
      pieceGlazes,
    )..where((pg) => pg.glazeOptionId.equals(id))).go();
    await (delete(glazeOptions)..where((g) => g.id.equals(id))).go();

    // Rebuild denormalized column for affected pieces
    for (final pieceId in affectedPieceIds) {
      await _rebuildDenormalizedGlazesForPiece(pieceId);
    }
  }

  Future<void> updateGlazeSortOrders(
    List<({String id, int sortOrder})> updates,
  ) {
    return batch((b) {
      for (final entry in updates) {
        b.update(
          glazeOptions,
          GlazeOptionsCompanion(sortOrder: Value(entry.sortOrder)),
          where: (g) => g.id.equals(entry.id),
        );
      }
    });
  }

  // ── Piece-glaze junction methods ──

  Future<List<GlazeOption>> getGlazesForPiece(String pieceId) async {
    final query =
        select(pieceGlazes).join([
            innerJoin(
              glazeOptions,
              glazeOptions.id.equalsExp(pieceGlazes.glazeOptionId),
            ),
          ])
          ..where(pieceGlazes.pieceId.equals(pieceId))
          ..orderBy([OrderingTerm.asc(pieceGlazes.sortOrder)]);

    final rows = await query.get();
    return rows.map((row) => row.readTable(glazeOptions)).toList();
  }

  Stream<List<GlazeOption>> watchGlazesForPiece(String pieceId) {
    final query =
        select(pieceGlazes).join([
            innerJoin(
              glazeOptions,
              glazeOptions.id.equalsExp(pieceGlazes.glazeOptionId),
            ),
          ])
          ..where(pieceGlazes.pieceId.equals(pieceId))
          ..orderBy([OrderingTerm.asc(pieceGlazes.sortOrder)]);

    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(glazeOptions)).toList(),
    );
  }

  Future<void> setGlazesForPiece(
    String pieceId,
    List<String> glazeOptionIds,
  ) async {
    // Find existing junction rows to detect removals
    final existing = await (select(pieceGlazes)
          ..where((pg) => pg.pieceId.equals(pieceId)))
        .get();
    final existingIds = existing.map((e) => e.glazeOptionId).toSet();
    final newIds = glazeOptionIds.toSet();
    final removedIds = existingIds.difference(newIds);

    // Record removed glazes in DeletedJunctions for sync
    for (final optionId in removedIds) {
      await into(deletedJunctions).insert(
        DeletedJunctionsCompanion.insert(
          id: const Uuid().v4(),
          junctionType: 'pieceGlazes',
          pieceId: pieceId,
          optionId: optionId,
          deletedAt: DateTime.now(),
        ),
      );
    }

    // Delete existing junction rows
    await (delete(pieceGlazes)..where((pg) => pg.pieceId.equals(pieceId))).go();

    // Insert new junction rows
    for (var i = 0; i < glazeOptionIds.length; i++) {
      await into(pieceGlazes).insert(
        PieceGlazesCompanion.insert(
          id: const Uuid().v4(),
          pieceId: pieceId,
          glazeOptionId: glazeOptionIds[i],
          sortOrder: Value(i),
        ),
      );
    }

    // Rebuild denormalized column
    await _rebuildDenormalizedGlazesForPiece(pieceId);
  }

  // ── Tag library methods ──

  Stream<List<TagOption>> watchAllTags() {
    return (select(
      tagOptions,
    )..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).watch();
  }

  Future<List<TagOption>> getAllTags() {
    return (select(
      tagOptions,
    )..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).get();
  }

  Future<int> getNextTagSortOrder() async {
    final result = await (selectOnly(
      tagOptions,
    )..addColumns([tagOptions.sortOrder.max()])).getSingleOrNull();
    final maxOrder = result?.read(tagOptions.sortOrder.max());
    return (maxOrder ?? -1) + 1;
  }

  Future<TagOption> findOrCreateTag(String name) async {
    final trimmed = name.trim();
    final existing =
        await (select(tagOptions)
              ..where((t) => t.name.lower().equals(trimmed.toLowerCase())))
            .getSingleOrNull();
    if (existing != null) return existing;

    final nextOrder = await getNextTagSortOrder();
    final id = const Uuid().v4();
    final defaultColor = TagColorPresets.defaultHexForIndex(nextOrder);
    final companion = TagOptionsCompanion.insert(
      id: id,
      name: trimmed,
      color: Value(defaultColor),
      sortOrder: Value(nextOrder),
      createdAt: DateTime.now(),
    );
    await into(tagOptions).insert(companion);
    return (select(tagOptions)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> updateTagName(String id, String newName) async {
    final trimmed = newName.trim();

    await (update(tagOptions)..where((t) => t.id.equals(id))).write(
      TagOptionsCompanion(name: Value(trimmed)),
    );

    // Rebuild denormalized tags column for all affected pieces
    final junctionRows = await (select(
      pieceTags,
    )..where((pt) => pt.tagOptionId.equals(id))).get();
    final affectedPieceIds = junctionRows.map((r) => r.pieceId).toSet();
    for (final pieceId in affectedPieceIds) {
      await _rebuildDenormalizedTagsForPiece(pieceId);
    }
  }

  Future<void> updateTagColor(String id, String colorHex) async {
    await (update(tagOptions)..where((t) => t.id.equals(id))).write(
      TagOptionsCompanion(color: Value(colorHex)),
    );
  }

  Future<void> deleteTag(String id) async {
    final junctionRows = await (select(
      pieceTags,
    )..where((pt) => pt.tagOptionId.equals(id))).get();
    final affectedPieceIds = junctionRows.map((r) => r.pieceId).toSet();

    await (delete(pieceTags)..where((pt) => pt.tagOptionId.equals(id))).go();
    await (delete(tagOptions)..where((t) => t.id.equals(id))).go();

    for (final pieceId in affectedPieceIds) {
      await _rebuildDenormalizedTagsForPiece(pieceId);
    }
  }

  Future<void> updateTagSortOrders(List<({String id, int sortOrder})> updates) {
    return batch((b) {
      for (final entry in updates) {
        b.update(
          tagOptions,
          TagOptionsCompanion(sortOrder: Value(entry.sortOrder)),
          where: (t) => t.id.equals(entry.id),
        );
      }
    });
  }

  // ── Piece-tag junction methods ──

  Future<List<TagOption>> getTagsForPiece(String pieceId) async {
    final query =
        select(pieceTags).join([
            innerJoin(
              tagOptions,
              tagOptions.id.equalsExp(pieceTags.tagOptionId),
            ),
          ])
          ..where(pieceTags.pieceId.equals(pieceId))
          ..orderBy([OrderingTerm.asc(tagOptions.sortOrder)]);

    final rows = await query.get();
    return rows.map((row) => row.readTable(tagOptions)).toList();
  }

  Stream<List<TagOption>> watchTagsForPiece(String pieceId) {
    final query =
        select(pieceTags).join([
            innerJoin(
              tagOptions,
              tagOptions.id.equalsExp(pieceTags.tagOptionId),
            ),
          ])
          ..where(pieceTags.pieceId.equals(pieceId))
          ..orderBy([OrderingTerm.asc(tagOptions.sortOrder)]);

    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(tagOptions)).toList(),
    );
  }

  Future<void> setTagsForPiece(
    String pieceId,
    List<String> tagOptionIds,
  ) async {
    // Find existing junction rows to detect removals
    final existing = await (select(pieceTags)
          ..where((pt) => pt.pieceId.equals(pieceId)))
        .get();
    final existingIds = existing.map((e) => e.tagOptionId).toSet();
    final newIds = tagOptionIds.toSet();
    final removedIds = existingIds.difference(newIds);

    // Record removed tags in DeletedJunctions for sync
    for (final optionId in removedIds) {
      await into(deletedJunctions).insert(
        DeletedJunctionsCompanion.insert(
          id: const Uuid().v4(),
          junctionType: 'pieceTags',
          pieceId: pieceId,
          optionId: optionId,
          deletedAt: DateTime.now(),
        ),
      );
    }

    await (delete(pieceTags)..where((pt) => pt.pieceId.equals(pieceId))).go();

    for (var i = 0; i < tagOptionIds.length; i++) {
      await into(pieceTags).insert(
        PieceTagsCompanion.insert(
          id: const Uuid().v4(),
          pieceId: pieceId,
          tagOptionId: tagOptionIds[i],
        ),
      );
    }

    await _rebuildDenormalizedTagsForPiece(pieceId);
  }

  // ── Deleted junctions methods ──

  Future<List<DeletedJunction>> getDeletedJunctions({
    required String junctionType,
    required String pieceId,
  }) {
    return (select(deletedJunctions)
          ..where(
            (d) =>
                d.junctionType.equals(junctionType) &
                d.pieceId.equals(pieceId),
          ))
        .get();
  }

  Future<void> cleanupDeletedJunctions(List<String> ids) async {
    if (ids.isEmpty) return;
    await (delete(deletedJunctions)..where((d) => d.id.isIn(ids))).go();
  }

  Future<void> cleanupDeletedJunctionsForPiece({
    required String junctionType,
    required String pieceId,
  }) {
    return (delete(deletedJunctions)
          ..where(
            (d) =>
                d.junctionType.equals(junctionType) &
                d.pieceId.equals(pieceId),
          ))
        .go();
  }

  // ── Private helpers ──

  Future<void> _rebuildDenormalizedTagsForPiece(String pieceId) async {
    final tagList = await getTagsForPiece(pieceId);
    final denormalized = tagList.isEmpty
        ? null
        : tagList.map((t) => t.name).join(', ');
    await customUpdate(
      'UPDATE pieces SET tags = ?, updated_at = ? WHERE id = ?',
      variables: [
        denormalized != null
            ? Variable.withString(denormalized)
            : const Variable(null),
        Variable.withDateTime(DateTime.now()),
        Variable.withString(pieceId),
      ],
      updates: {pieces},
    );
  }

  Future<void> _rebuildDenormalizedGlazesForPiece(String pieceId) async {
    final glazeList = await getGlazesForPiece(pieceId);
    final denormalized = glazeList.isEmpty
        ? null
        : glazeList.map((g) => g.name).join(', ');
    await customUpdate(
      'UPDATE pieces SET glazes = ?, updated_at = ? WHERE id = ?',
      variables: [
        denormalized != null
            ? Variable.withString(denormalized)
            : const Variable(null),
        Variable.withDateTime(DateTime.now()),
        Variable.withString(pieceId),
      ],
      updates: {pieces},
    );
  }
}
