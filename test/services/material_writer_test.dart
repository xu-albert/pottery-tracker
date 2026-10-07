import 'package:drift/drift.dart' show Value;
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

  test('renaming a clay queues it and every piece it renamed', () async {
    final clay = await writer.clay('Stoneware');
    for (final (id, clayType) in [
      ('p1', 'Stoneware'),
      ('p2', 'Stoneware'),
      ('p3', 'Porcelain'),
    ]) {
      await db.piecesDao.insertPiece(
        PiecesCompanion(
          id: Value(id),
          clayType: Value(clayType),
          createdAt: Value(DateTime(2025)),
          updatedAt: Value(DateTime(2025)),
        ),
      );
    }
    await queue.clear();

    await writer.renameClay(clay.id, 'B-Mix');

    expect((await db.piecesDao.getPieceById('p1'))!.clayType, 'B-Mix');
    expect(
      await queue.getAll(),
      [
        SyncQueueEntry(operation: SyncOperation.pushClay, entityId: clay.id),
        const SyncQueueEntry(
          operation: SyncOperation.pushPiece,
          entityId: 'p1',
        ),
        const SyncQueueEntry(
          operation: SyncOperation.pushPiece,
          entityId: 'p2',
        ),
      ],
      reason: 'a renamed piece carries a new stamp and new pushed content',
    );
    expect(
      [
        for (final entry in await queue.getAll())
          if (entry.operation == SyncOperation.pushPiece) entry.changedFields,
      ],
      [
        ['clayType'],
        ['clayType'],
      ],
      reason: 'a rename must not push the rest of a piece it did not change',
    );
  });

  test('a renamed piece with an edit of its own queued still pushes '
      'whole', () async {
    final clay = await writer.clay('Stoneware');
    for (final id in ['p1', 'p2']) {
      await db.piecesDao.insertPiece(
        PiecesCompanion(
          id: Value(id),
          clayType: const Value('Stoneware'),
          createdAt: Value(DateTime(2025)),
          updatedAt: Value(DateTime(2025)),
        ),
      );
    }
    final trigger = SyncTrigger(queue);
    await trigger.afterPieceWrite('p1');
    await writer.renameClay(clay.id, 'B-Mix');
    await writer.renameClay(clay.id, 'Stoneware');
    await trigger.afterPieceWrite('p2');

    final pieces = {
      for (final entry in await queue.getAll())
        if (entry.operation == SyncOperation.pushPiece)
          entry.entityId: entry.changedFields,
    };
    expect(pieces, {'p1': null, 'p2': null});
  });
}
