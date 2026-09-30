import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pottery_tracker/services/sync_queue.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SyncQueue enqueue', () {
    test('appends new entry when queue is empty', () async {
      final queue = SyncQueue();
      const entry = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
        changedFields: ['title'],
      );

      await queue.enqueue(entry);
      final all = await queue.getAll();

      expect(all, hasLength(1));
      expect(all.first.entityId, 'p1');
      expect(all.first.changedFields, ['title']);
    });

    test('appends entry with different operation+entityId', () async {
      final queue = SyncQueue();
      const entry1 = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
      );
      const entry2 = SyncQueueEntry(
        operation: SyncOperation.pushPhoto,
        entityId: 'photo-1',
      );

      await queue.enqueue(entry1);
      await queue.enqueue(entry2);
      final all = await queue.getAll();

      expect(all, hasLength(2));
    });

    test(
      'merges entry with same operation+entityId — unions changedFields',
      () async {
        final queue = SyncQueue();
        const entry1 = SyncQueueEntry(
          operation: SyncOperation.pushPiece,
          entityId: 'p1',
          changedFields: ['title', 'stage'],
        );
        const entry2 = SyncQueueEntry(
          operation: SyncOperation.pushPiece,
          entityId: 'p1',
          changedFields: ['stage', 'notes'],
        );

        await queue.enqueue(entry1);
        await queue.enqueue(entry2);
        final all = await queue.getAll();

        expect(all, hasLength(1));
        expect(all.first.changedFields!.toSet(), {'title', 'stage', 'notes'});
      },
    );

    test(
      'does not merge entries with same entityId but different operation',
      () async {
        final queue = SyncQueue();
        const entry1 = SyncQueueEntry(
          operation: SyncOperation.pushPiece,
          entityId: 'p1',
        );
        const entry2 = SyncQueueEntry(
          operation: SyncOperation.deletePiece,
          entityId: 'p1',
        );

        await queue.enqueue(entry1);
        await queue.enqueue(entry2);
        final all = await queue.getAll();

        expect(all, hasLength(2));
      },
    );

    test(
      'merged entry preserves null changedFields (push-all semantics)',
      () async {
        final queue = SyncQueue();
        const entry1 = SyncQueueEntry(
          operation: SyncOperation.pushPiece,
          entityId: 'p1',
        );
        const entry2 = SyncQueueEntry(
          operation: SyncOperation.pushPiece,
          entityId: 'p1',
          changedFields: ['title'],
        );

        await queue.enqueue(entry1);
        await queue.enqueue(entry2);
        final all = await queue.getAll();

        expect(all, hasLength(1));
        expect(all.first.changedFields, isNull);
      },
    );
  });

  group('SyncQueue getAll / remove / clear / pendingCount', () {
    test('returns empty list when nothing enqueued', () async {
      final queue = SyncQueue();
      final all = await queue.getAll();
      expect(all, isEmpty);
    });

    test('persists across new SyncQueue instances', () async {
      final queue1 = SyncQueue();
      const entry = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
      );
      await queue1.enqueue(entry);

      final queue2 = SyncQueue();
      final all = await queue2.getAll();
      expect(all, hasLength(1));
      expect(all.first.entityId, 'p1');
    });

    test('remove works by == (ignores changedFields)', () async {
      final queue = SyncQueue();
      const entry = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
        changedFields: ['title', 'stage'],
      );
      await queue.enqueue(entry);

      const removeKey = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
      );
      await queue.remove(removeKey);

      final all = await queue.getAll();
      expect(all, isEmpty);
    });

    test('acknowledge removes only the revision that was dispatched', () async {
      final queue = SyncQueue();
      const entry = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
        changedFields: ['title'],
      );
      await queue.enqueue(entry);
      final dispatchedRevision = queue.revisionOf(entry);

      expect(await queue.acknowledge(entry, dispatchedRevision), isTrue);
      expect(await queue.getAll(), isEmpty);
    });

    test(
      'an enqueue racing acknowledgement keeps the newer revision',
      () async {
        final queue = SyncQueue();
        const first = SyncQueueEntry(
          operation: SyncOperation.pushPiece,
          entityId: 'p1',
          changedFields: ['title'],
        );
        const newer = SyncQueueEntry(
          operation: SyncOperation.pushPiece,
          entityId: 'p1',
          changedFields: ['notes'],
        );
        await queue.enqueue(first);
        final dispatchedRevision = queue.revisionOf(first);

        final enqueue = queue.enqueue(newer);
        final acknowledged = queue.acknowledge(first, dispatchedRevision);
        await enqueue;

        expect(await acknowledged, isFalse);
        final remaining = await queue.getAll();
        expect(remaining, hasLength(1));
        expect(remaining.single.changedFields!.toSet(), {'title', 'notes'});
      },
    );

    test('clear empties the queue; pendingCount returns 0 after', () async {
      final queue = SyncQueue();
      await queue.enqueue(
        const SyncQueueEntry(
          operation: SyncOperation.pushPiece,
          entityId: 'p1',
        ),
      );
      await queue.enqueue(
        const SyncQueueEntry(
          operation: SyncOperation.pushPhoto,
          entityId: 'photo-1',
        ),
      );

      expect(await queue.pendingCount, 2);

      await queue.clear();

      expect(await queue.pendingCount, 0);
      expect(await queue.getAll(), isEmpty);
    });
  });
}
