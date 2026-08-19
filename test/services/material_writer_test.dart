import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/services/material_writer.dart';
import 'package:pottery_tracker/services/sync_queue.dart';
import 'package:pottery_tracker/services/sync_trigger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The one boundary that decides whether a material write is owed to the
/// backup. Picking an existing material returns the row untouched, so queueing
/// it anyway would report a write that never happened and push a no-op.
void main() {
  late AppDatabase db;
  late SyncQueue queue;
  late MaterialWriter writer;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    queue = SyncQueue();
    writer = MaterialWriter(db.materialsDao, SyncTrigger(queue));
  });

  tearDown(() async {
    await db.close();
  });

  test('creating a material queues it for backup', () async {
    final clay = await writer.clay('Stoneware');

    final queued = await queue.getAll();
    expect(queued, hasLength(1));
    expect(queued.single.operation, SyncOperation.pushClay);
    expect(queued.single.entityId, clay.id);
  });

  test('picking a material that already exists queues nothing', () async {
    final created = await writer.clay('Stoneware');
    await queue.clear();

    final picked = await writer.clay('stoneware');

    expect(picked.id, created.id);
    expect(
      await queue.getAll(),
      isEmpty,
      reason: 'nothing was written, so nothing is owed to the backup',
    );
  });

  test('glazes and tags follow the same rule', () async {
    final glaze = await writer.glaze('Celadon');
    final tag = await writer.tag('Gift');
    expect((await queue.getAll()).map((e) => e.entityId), [glaze.id, tag.id]);

    await queue.clear();
    final sameGlaze = await writer.glaze('celadon');
    final sameTag = await writer.tag('gift');

    expect([sameGlaze.id, sameTag.id], [glaze.id, tag.id]);
    expect(await queue.getAll(), isEmpty);
  });
}
