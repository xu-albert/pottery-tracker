import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pottery_tracker/services/sync_queue.dart';
import 'package:pottery_tracker/services/sync_trigger.dart';

void main() {
  late SyncQueue queue;
  late int callbackCount;
  late String? signedInUid;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    queue = SyncQueue();
    callbackCount = 0;
    signedInUid = null;
  });

  SyncTrigger makeTrigger() => SyncTrigger(
    queue,
    currentUid: () async => signedInUid,
    onEnqueue: () => callbackCount++,
  );

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

    test(
      'enqueues both pushPhoto and pushPhotoFile when includeFile is true',
      () async {
        final trigger = makeTrigger();
        await trigger.afterPhotoWrite('photo-1', includeFile: true);

        final all = await queue.getAll();
        expect(all, hasLength(2));
        expect(all[0].operation, SyncOperation.pushPhoto);
        expect(all[1].operation, SyncOperation.pushPhotoFile);
      },
    );
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
    test(
      'enqueues deleteMaterial with entityId and collection as extraData',
      () async {
        final trigger = makeTrigger();
        await trigger.afterMaterialDeletion('clays', 'clay-1');

        final all = await queue.getAll();
        expect(all, hasLength(1));
        expect(all.first.operation, SyncOperation.deleteMaterial);
        expect(all.first.entityId, 'clay-1');
        expect(all.first.extraData, 'clays');
        expect(callbackCount, 1);
      },
    );
  });

  group('SyncTrigger session stamping', () {
    test('stamps every entry with the uid signed in at write time', () async {
      final trigger = makeTrigger();
      signedInUid = 'user-a';
      await trigger.afterPieceWrite('p1');
      await trigger.afterPhotoWrite('photo-1', includeFile: true);
      await trigger.afterClayWrite('clay-1');
      await trigger.afterGlazeWrite('glaze-1');
      await trigger.afterTagWrite('tag-1');
      await trigger.afterPieceGlazesWrite('p1');
      await trigger.afterPieceTagsWrite('p1');
      await trigger.afterPieceDeletion('p2', ['photo-2']);
      await trigger.afterPhotoDeletion('photo-3');
      await trigger.afterMaterialDeletion('clays', 'clay-2');

      final all = await queue.getAll();
      expect(all, isNotEmpty);
      expect(all.every((e) => e.uid == 'user-a'), isTrue);
    });

    test('leaves a local-only write unattributed', () async {
      final trigger = makeTrigger();
      await trigger.afterPieceWrite('p1');

      final all = await queue.getAll();
      expect(all.single.uid, isNull);
    });

    test(
      'a second session does not merge into the first account\'s entry',
      () async {
        final trigger = makeTrigger();
        signedInUid = 'user-a';
        await trigger.afterPieceWrite('p1', changedFields: ['title']);
        signedInUid = 'user-b';
        await trigger.afterPieceWrite('p1', changedFields: ['notes']);

        final all = await queue.getAll();
        expect(all, hasLength(2));
        expect(all.map((e) => e.uid), containsAll(['user-a', 'user-b']));
      },
    );
  });
}
