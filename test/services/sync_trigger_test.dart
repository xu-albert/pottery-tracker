import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pottery_tracker/services/sync_queue.dart';
import 'package:pottery_tracker/services/sync_trigger.dart';

void main() {
  late SyncQueue queue;
  late int callbackCount;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    queue = SyncQueue();
    callbackCount = 0;
  });

  SyncTrigger makeTrigger() =>
      SyncTrigger(queue, onEnqueue: () => callbackCount++);

  group('SyncTrigger afterPieceWrite', () {
    test('enqueues pushPiece with changedFields', () async {
      final trigger = makeTrigger();
      await trigger.afterPieceWrite('p1', changedFields: ['title', 'notes']);

      final all = await queue.getAll();
      expect(all, hasLength(1));
      expect(all.first.operation, SyncOperation.pushPiece);
      expect(all.first.entityId, 'p1');
      expect(all.first.changedFields, ['title', 'notes']);
    });

    test('enqueues pushPiece with null changedFields', () async {
      final trigger = makeTrigger();
      await trigger.afterPieceWrite('p1');

      final all = await queue.getAll();
      expect(all, hasLength(1));
      expect(all.first.changedFields, isNull);
    });

    test('calls onEnqueue callback', () async {
      final trigger = makeTrigger();
      await trigger.afterPieceWrite('p1');
      expect(callbackCount, 1);
    });
  });

  group('SyncTrigger afterPhotoWrite', () {
    test('enqueues pushPhoto with correct entityId', () async {
      final trigger = makeTrigger();
      await trigger.afterPhotoWrite('photo-1');

      final all = await queue.getAll();
      expect(all, hasLength(1));
      expect(all.first.operation, SyncOperation.pushPhoto);
      expect(all.first.entityId, 'photo-1');
    });

    test('enqueues both pushPhoto and pushPhotoFile when includeFile is true',
        () async {
      final trigger = makeTrigger();
      await trigger.afterPhotoWrite('photo-1', includeFile: true);

      final all = await queue.getAll();
      expect(all, hasLength(2));
      expect(all[0].operation, SyncOperation.pushPhoto);
      expect(all[1].operation, SyncOperation.pushPhotoFile);
    });
  });

  group('SyncTrigger afterClayWrite', () {
    test('enqueues pushClay with correct entityId', () async {
      final trigger = makeTrigger();
      await trigger.afterClayWrite('clay-1');

      final all = await queue.getAll();
      expect(all, hasLength(1));
      expect(all.first.operation, SyncOperation.pushClay);
      expect(all.first.entityId, 'clay-1');
      expect(callbackCount, 1);
    });
  });

  group('SyncTrigger afterGlazeWrite', () {
    test('enqueues pushGlaze with correct entityId', () async {
      final trigger = makeTrigger();
      await trigger.afterGlazeWrite('glaze-1');

      final all = await queue.getAll();
      expect(all, hasLength(1));
      expect(all.first.operation, SyncOperation.pushGlaze);
      expect(all.first.entityId, 'glaze-1');
      expect(callbackCount, 1);
    });
  });

  group('SyncTrigger afterTagWrite', () {
    test('enqueues pushTag with correct entityId', () async {
      final trigger = makeTrigger();
      await trigger.afterTagWrite('tag-1');

      final all = await queue.getAll();
      expect(all, hasLength(1));
      expect(all.first.operation, SyncOperation.pushTag);
      expect(all.first.entityId, 'tag-1');
      expect(callbackCount, 1);
    });
  });

  group('SyncTrigger afterPieceGlazesWrite', () {
    test('enqueues pushPieceGlazes with correct entityId', () async {
      final trigger = makeTrigger();
      await trigger.afterPieceGlazesWrite('p1');

      final all = await queue.getAll();
      expect(all, hasLength(1));
      expect(all.first.operation, SyncOperation.pushPieceGlazes);
      expect(all.first.entityId, 'p1');
      expect(callbackCount, 1);
    });
  });

  group('SyncTrigger afterPieceTagsWrite', () {
    test('enqueues pushPieceTags with correct entityId', () async {
      final trigger = makeTrigger();
      await trigger.afterPieceTagsWrite('p1');

      final all = await queue.getAll();
      expect(all, hasLength(1));
      expect(all.first.operation, SyncOperation.pushPieceTags);
      expect(all.first.entityId, 'p1');
      expect(callbackCount, 1);
    });
  });

  group('SyncTrigger afterPieceDeletion', () {
    test('enqueues deletePhoto for each photo then deletePiece', () async {
      final trigger = makeTrigger();
      await trigger.afterPieceDeletion('p1', ['photo-1', 'photo-2']);

      final all = await queue.getAll();
      expect(all, hasLength(3));
      expect(all[0].operation, SyncOperation.deletePhoto);
      expect(all[0].entityId, 'photo-1');
      expect(all[1].operation, SyncOperation.deletePhoto);
      expect(all[1].entityId, 'photo-2');
      expect(all[2].operation, SyncOperation.deletePiece);
      expect(all[2].entityId, 'p1');
      expect(callbackCount, 1);
    });
  });

  group('SyncTrigger afterPhotoDeletion', () {
    test('enqueues deletePhoto with correct entityId', () async {
      final trigger = makeTrigger();
      await trigger.afterPhotoDeletion('photo-1');

      final all = await queue.getAll();
      expect(all, hasLength(1));
      expect(all.first.operation, SyncOperation.deletePhoto);
      expect(all.first.entityId, 'photo-1');
      expect(callbackCount, 1);
    });
  });

  group('SyncTrigger afterMaterialDeletion', () {
    test('enqueues deleteMaterial with entityId and collection as extraData',
        () async {
      final trigger = makeTrigger();
      await trigger.afterMaterialDeletion('clays', 'clay-1');

      final all = await queue.getAll();
      expect(all, hasLength(1));
      expect(all.first.operation, SyncOperation.deleteMaterial);
      expect(all.first.entityId, 'clay-1');
      expect(all.first.extraData, 'clays');
      expect(callbackCount, 1);
    });
  });
}
