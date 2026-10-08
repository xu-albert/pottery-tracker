import '../database/daos/materials_dao.dart';
import '../database/database.dart';
import 'sync_trigger.dart';

/// Finds or creates a material, and enqueues a sync for exactly the ones it
/// created; renames a clay, and enqueues everything the rename rewrote;
/// saves a new custom order, and enqueues exactly the materials it moved.
///
/// `MaterialsDao.findOrCreate*` returns an existing row untouched, so a caller
/// that enqueues unconditionally reports a write that never happened and
/// queues a no-op push — picking a clay from the dropdown is enough to
/// trigger it.
///
/// Every caller goes through here so the rule lives at one boundary rather
/// than being restated at each call site, where a new one would silently miss
/// it.
class MaterialWriter {
  final MaterialsDao _dao;
  final SyncTrigger _trigger;

  const MaterialWriter(this._dao, this._trigger);

  Future<ClayOption> clay(String name) async {
    final (clay, created) = await _dao.findOrCreateClay(name);
    if (created) await _trigger.afterClayWrite(clay.id);
    return clay;
  }

  Future<GlazeOption> glaze(String name) async {
    final (glaze, created) = await _dao.findOrCreateGlaze(name);
    if (created) await _trigger.afterGlazeWrite(glaze.id);
    return glaze;
  }

  Future<TagOption> tag(String name) async {
    final (tag, created) = await _dao.findOrCreateTag(name);
    if (created) await _trigger.afterTagWrite(tag.id);
    return tag;
  }

  /// Renames a clay, and queues the clay and every piece the rename rewrote:
  /// a piece's `clayType` is pushed content, and a pull replaces a piece with
  /// nothing queued by the cloud's copy, which would put the old name back.
  ///
  /// Each piece is queued for its `clayType` alone. This device may not have
  /// pulled another device's edit to the rest of the piece, and a rename must
  /// not send its older copy over it. A piece also queued for an edit of its
  /// own still pushes whole.
  Future<void> renameClay(String id, String newName) async {
    final renamed = await _dao.updateClayName(id, newName);
    await _trigger.afterClayWrite(id);
    for (final pieceId in renamed) {
      await _trigger.afterPieceWrite(
        pieceId,
        changedFields: const ['clayType'],
      );
    }
  }

  /// Saves the order the user dragged a Manage screen into, and queues
  /// exactly the clays whose position changed: `sortOrder` is pushed
  /// content, so a move that is never queued stays on this device, and the
  /// other devices keep their order.
  ///
  /// [orderedIds] is the whole list, top first. Positions are rewritten as
  /// 0..n-1, so rows that shared a position (as a pull can leave them) get
  /// distinct ones on the first reorder.
  Future<void> reorderClays(List<String> orderedIds) async {
    final moved = _moved(orderedIds, {
      for (final clay in await _dao.getAllClays()) clay.id: clay.sortOrder,
    });
    if (moved.isEmpty) return;
    await _dao.updateSortOrders(moved);
    for (final entry in moved) {
      await _trigger.afterClayWrite(entry.id);
    }
  }

  /// [reorderClays] for glazes.
  Future<void> reorderGlazes(List<String> orderedIds) async {
    final moved = _moved(orderedIds, {
      for (final glaze in await _dao.getAllGlazes()) glaze.id: glaze.sortOrder,
    });
    if (moved.isEmpty) return;
    await _dao.updateGlazeSortOrders(moved);
    for (final entry in moved) {
      await _trigger.afterGlazeWrite(entry.id);
    }
  }

  /// [reorderClays] for tags.
  Future<void> reorderTags(List<String> orderedIds) async {
    final moved = _moved(orderedIds, {
      for (final tag in await _dao.getAllTags()) tag.id: tag.sortOrder,
    });
    if (moved.isEmpty) return;
    await _dao.updateTagSortOrders(moved);
    for (final entry in moved) {
      await _trigger.afterTagWrite(entry.id);
    }
  }

  /// The rows of [orderedIds] whose index differs from their stored
  /// position. An id no longer stored — deleted while the list was on
  /// screen — is skipped rather than written back.
  static List<({String id, int sortOrder})> _moved(
    List<String> orderedIds,
    Map<String, int> stored,
  ) => [
    for (var i = 0; i < orderedIds.length; i++)
      if (stored.containsKey(orderedIds[i]) && stored[orderedIds[i]] != i)
        (id: orderedIds[i], sortOrder: i),
  ];
}
