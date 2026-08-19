import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/services/sync_queue.dart';

void main() {
  group('SyncQueueEntry toJson / fromJson', () {
    test('round-trips all fields including changedFields', () {
      const entry = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'piece-1',
        extraData: 'extra',
        changedFields: ['title', 'stage'],
      );
      final json = entry.toJson();
      final restored = SyncQueueEntry.fromJson(json);

      expect(restored.operation, SyncOperation.pushPiece);
      expect(restored.entityId, 'piece-1');
      expect(restored.extraData, 'extra');
      expect(restored.changedFields, ['title', 'stage']);
    });

    test('round-trips with null changedFields', () {
      const entry = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'piece-1',
      );
      final json = entry.toJson();
      final restored = SyncQueueEntry.fromJson(json);

      expect(restored.changedFields, isNull);
      expect(restored.extraData, isNull);
    });

    test('round-trips with empty changedFields list', () {
      const entry = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'piece-1',
        changedFields: [],
      );
      final json = entry.toJson();
      final restored = SyncQueueEntry.fromJson(json);

      expect(restored.changedFields, isEmpty);
    });

    test('handles all SyncOperation enum values', () {
      for (final op in SyncOperation.values) {
        final entry = SyncQueueEntry(operation: op, entityId: 'id-1');
        final json = entry.toJson();
        final restored = SyncQueueEntry.fromJson(json);
        expect(restored.operation, op);
      }
    });
  });

  group('SyncQueueEntry mergeWith', () {
    test('unions changedFields when both non-null', () {
      const a = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
        changedFields: ['title', 'stage'],
      );
      const b = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
        changedFields: ['stage', 'notes'],
      );
      final merged = a.mergeWith(b);

      expect(merged.changedFields, isNotNull);
      expect(merged.changedFields!.toSet(), {'title', 'stage', 'notes'});
    });

    test('returns null changedFields when this.changedFields is null', () {
      const a = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
      );
      const b = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
        changedFields: ['title'],
      );
      final merged = a.mergeWith(b);

      expect(merged.changedFields, isNull);
    });

    test('returns null changedFields when other.changedFields is null', () {
      const a = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
        changedFields: ['title'],
      );
      const b = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
      );
      final merged = a.mergeWith(b);

      expect(merged.changedFields, isNull);
    });

    test('returns null changedFields when both are null', () {
      const a = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
      );
      const b = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
      );
      final merged = a.mergeWith(b);

      expect(merged.changedFields, isNull);
    });

    test('preserves operation, entityId, extraData from this', () {
      const a = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
        extraData: 'from-a',
        changedFields: ['title'],
      );
      const b = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
        extraData: 'from-a',
        changedFields: ['stage'],
      );
      final merged = a.mergeWith(b);

      expect(merged.operation, SyncOperation.pushPiece);
      expect(merged.entityId, 'p1');
      expect(merged.extraData, 'from-a');
    });
  });

  group('SyncQueueEntry operator ==', () {
    test('equal when same operation + entityId + extraData', () {
      const a = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
        extraData: 'x',
      );
      const b = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
        extraData: 'x',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('equal regardless of changedFields difference', () {
      const a = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
        changedFields: ['title'],
      );
      const b = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
        changedFields: ['stage', 'notes'],
      );
      expect(a, equals(b));
    });

    test('not equal when operation differs', () {
      const a = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
      );
      const b = SyncQueueEntry(
        operation: SyncOperation.deletePiece,
        entityId: 'p1',
      );
      expect(a, isNot(equals(b)));
    });

    test('not equal when entityId differs', () {
      const a = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p1',
      );
      const b = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'p2',
      );
      expect(a, isNot(equals(b)));
    });

    test('not equal when extraData differs', () {
      const a = SyncQueueEntry(
        operation: SyncOperation.deleteMaterial,
        entityId: 'id1',
        extraData: 'clays',
      );
      const b = SyncQueueEntry(
        operation: SyncOperation.deleteMaterial,
        entityId: 'id1',
        extraData: 'glazes',
      );
      expect(a, isNot(equals(b)));
    });
  });
}
