import '../database/daos/materials_dao.dart';
import '../database/database.dart';
import 'sync_trigger.dart';

/// Finds or creates a material, and enqueues a sync for exactly the ones it
/// created.
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
}
