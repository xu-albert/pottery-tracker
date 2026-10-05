import '../database/daos/materials_dao.dart';
import '../database/database.dart';
import 'sync_trigger.dart';

/// Finds or creates a material, and enqueues a sync for exactly the ones it
/// created; renames a clay, and enqueues everything the rename rewrote.
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
}
