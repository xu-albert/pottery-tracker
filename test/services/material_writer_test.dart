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

  group('reordering', () {
    test(
      'saves the dragged order and queues only the clays it moved',
      () async {
        final a = await writer.clay('A');
        final b = await writer.clay('B');
        final c = await writer.clay('C');
        final d = await writer.clay('D');
        await queue.clear();

        // Drag C to the top: A, B and C move down or up, D stays put.
        await writer.reorderClays([c.id, a.id, b.id, d.id]);

        expect((await db.materialsDao.getAllClays()).map((x) => x.name), [
          'C',
          'A',
          'B',
          'D',
        ]);
        expect(
          await queue.getAll(),
          [
            SyncQueueEntry(operation: SyncOperation.pushClay, entityId: c.id),
            SyncQueueEntry(operation: SyncOperation.pushClay, entityId: a.id),
            SyncQueueEntry(operation: SyncOperation.pushClay, entityId: b.id),
          ],
          reason:
              'sortOrder is pushed content, so every moved clay is owed to '
              'the backup, and one that kept its place is not',
        );
      },
    );

    test('an order that changes nothing queues nothing', () async {
      final a = await writer.clay('A');
      final b = await writer.clay('B');
      await queue.clear();

      await writer.reorderClays([a.id, b.id]);

      expect(await queue.getAll(), isEmpty);
    });

    test('rows that shared a position get distinct ones', () async {
      final a = await writer.clay('A');
      final b = await writer.clay('B');
      // A pull of rows written before sortOrder existed leaves them all at 0.
      await db.materialsDao.updateSortOrders([
        (id: a.id, sortOrder: 0),
        (id: b.id, sortOrder: 0),
      ]);
      await queue.clear();

      await writer.reorderClays([a.id, b.id]);

      expect((await db.materialsDao.getAllClays()).map((x) => x.sortOrder), [
        0,
        1,
      ]);
      expect((await queue.getAll()).map((e) => e.entityId), [b.id]);
    });

    test('a clay deleted while the list was on screen is not written '
        'back', () async {
      final a = await writer.clay('A');
      final b = await writer.clay('B');
      await db.materialsDao.deleteClay(a.id);
      await queue.clear();

      await writer.reorderClays([b.id, a.id]);

      expect((await db.materialsDao.getAllClays()).map((x) => x.id), [b.id]);
      expect((await queue.getAll()).map((e) => e.entityId), [b.id]);
    });

    test('glazes and tags follow the same rule', () async {
      final g1 = await writer.glaze('Celadon');
      final g2 = await writer.glaze('Tenmoku');
      final t1 = await writer.tag('Gift');
      final t2 = await writer.tag('Sold');
      await queue.clear();

      await writer.reorderGlazes([g2.id, g1.id]);
      await writer.reorderTags([t2.id, t1.id]);

      expect((await db.materialsDao.getAllGlazes()).map((x) => x.name), [
        'Tenmoku',
        'Celadon',
      ]);
      expect((await db.materialsDao.getAllTags()).map((x) => x.name), [
        'Sold',
        'Gift',
      ]);
      expect(await queue.getAll(), [
        SyncQueueEntry(operation: SyncOperation.pushGlaze, entityId: g2.id),
        SyncQueueEntry(operation: SyncOperation.pushGlaze, entityId: g1.id),
        SyncQueueEntry(operation: SyncOperation.pushTag, entityId: t2.id),
        SyncQueueEntry(operation: SyncOperation.pushTag, entityId: t1.id),
      ]);
    });
  });
}
