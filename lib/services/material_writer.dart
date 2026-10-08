import '../database/daos/materials_dao.dart';
import '../database/database.dart';
import 'sync_trigger.dart';

/// Finds or creates a material, and enqueues a sync for exactly the ones it
/// created; renames a clay, and enqueues everything the rename rewrote;
/// saves a new custom order, and enqueues every material in it.
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

  /// Saves the order the user dragged a Manage screen into, and queues every
  /// clay in it: `sortOrder` is pushed content, and queuing the whole list
  /// makes the last push win for the order as a whole, so a device that has
  /// not pulled another device's reorder cannot mix the two.
  ///
  /// [orderedIds] is the whole list, top first. Positions are rewritten as
  /// 0..n-1, so rows that shared a position (as a pull can leave them) get
  /// distinct ones on the first reorder.
  Future<void> reorderClays(List<String> orderedIds) async {
    final orders = _ordersOf(orderedIds, {
      for (final clay in await _dao.getAllClays()) clay.id,
    });
    await _dao.updateSortOrders(orders);
    for (final entry in orders) {
      await _trigger.afterClayWrite(entry.id);
    }
  }

  /// [reorderClays] for glazes.
  Future<void> reorderGlazes(List<String> orderedIds) async {
    final orders = _ordersOf(orderedIds, {
      for (final glaze in await _dao.getAllGlazes()) glaze.id,
    });
    await _dao.updateGlazeSortOrders(orders);
    for (final entry in orders) {
      await _trigger.afterGlazeWrite(entry.id);
    }
  }

  /// [reorderClays] for tags.
  Future<void> reorderTags(List<String> orderedIds) async {
    final orders = _ordersOf(orderedIds, {
      for (final tag in await _dao.getAllTags()) tag.id,
    });
    await _dao.updateTagSortOrders(orders);
    for (final entry in orders) {
      await _trigger.afterTagWrite(entry.id);
    }
  }

  /// Each row of [orderedIds] at its index. An id no longer [stored] —
  /// deleted while the list was on screen — is skipped rather than written
  /// back.
  static List<({String id, int sortOrder})> _ordersOf(
    List<String> orderedIds,
    Set<String> stored,
  ) => [
    for (var i = 0; i < orderedIds.length; i++)
      if (stored.contains(orderedIds[i])) (id: orderedIds[i], sortOrder: i),
  ];
}
