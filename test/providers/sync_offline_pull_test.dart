// These SDK-boundary mocks exercise server/cache behavior without native Firebase.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/providers/sync_provider.dart';
import 'package:pottery_tracker/services/image_service.dart';
import 'package:pottery_tracker/services/piece_writer.dart';
import 'package:pottery_tracker/services/sync_queue.dart';
import 'package:pottery_tracker/services/sync_service.dart';
import 'package:pottery_tracker/services/sync_trigger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Firestore extends Mock implements FirebaseFirestore {}

class _Document extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _Collection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _Snapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class _Metadata extends Mock implements SnapshotMetadata {}

class _Query extends Mock implements Query<Map<String, dynamic>> {}

class _Transaction extends Mock implements Transaction {}

class _Images extends Mock implements ImageService {}

class _InstantClock extends SyncClock {
  @override
  Future<void> sleep(Duration duration) async {}
}

/// Models the SDK boundary: default reads can return an incomplete offline
/// cache; server reads and transactions fail offline, while a plain write
/// waits for the server. Both stores execute real query filtering.
class _Network {
  final firestore = _Firestore();
  final server = FakeFirebaseFirestore();
  final cache = FakeFirebaseFirestore();
  String? unavailableCollection;
  DateTime serverTime = DateTime(2024);
  Future<void> Function(String)? afterRead;
  String? boundaryResponse;
  final rejectedWrites = <String>{};
  final reads = <String>[];
  final returnedCounts = <String, int>{};

  _Network() {
    final user = _Document();
    when(() => firestore.doc('users/user-1')).thenReturn(user);
    final meta = _Collection();
    final barrier = _Document();
    when(() => user.collection('meta')).thenReturn(meta);
    when(() => meta.doc('pullBoundary')).thenReturn(barrier);
    Future<void> commitBoundary(Object? fields) async {
      expect((fields as Map<String, dynamic>)['at'], isA<FieldValue>());
      await server.doc('users/user-1/meta/pullBoundary').set({
        'at': Timestamp.fromDate(serverTime),
      });
    }

    when(() => barrier.set(any())).thenAnswer((call) {
      if (unavailableCollection == 'meta') return Completer<void>().future;
      return commitBoundary(call.positionalArguments.first);
    });
    when(() => firestore.runTransaction<void>(any())).thenAnswer((call) async {
      final transaction = _Transaction();
      final writes = <Object?>[];
      when(() => transaction.set<Object?>(barrier, any())).thenAnswer((call) {
        writes.add(call.positionalArguments[1]);
        return transaction;
      });
      final handler = call.positionalArguments.single;
      await (handler as TransactionHandler<void>)(transaction);
      if (unavailableCollection == 'meta') {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      }
      for (final fields in writes) {
        await commitBoundary(fields);
      }
    });
    when(() => barrier.get(any())).thenAnswer((call) async {
      expect(
        (call.positionalArguments.single as GetOptions).source,
        Source.server,
      );
      if (unavailableCollection == 'meta' ||
          boundaryResponse == 'unavailable') {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      }
      if (boundaryResponse != null) {
        final snapshot = _Snapshot();
        final metadata = _Metadata();
        when(() => snapshot.metadata).thenReturn(metadata);
        when(
          () => metadata.isFromCache,
        ).thenReturn(boundaryResponse == 'cache');
        when(
          () => metadata.hasPendingWrites,
        ).thenReturn(boundaryResponse == 'pending');
        when(() => snapshot.data()).thenReturn({
          'at': boundaryResponse == 'missing'
              ? null
              : Timestamp.fromDate(serverTime),
        });
        return snapshot;
      }
      return server.doc('users/user-1/meta/pullBoundary').get();
    });
    for (final name in [
      'pieces',
      'photos',
      'clays',
      'glazes',
      'tags',
      'pieceGlazes',
      'pieceTags',
    ]) {
      final collection = _Collection();
      final remote = server.collection('users/user-1/$name');
      final cached = cache.collection('users/user-1/$name');
      when(() => user.collection(name)).thenReturn(collection);
      when(() => collection.doc(any())).thenAnswer((call) {
        final id = call.positionalArguments.single as String;
        if (!rejectedWrites.contains(id)) return remote.doc(id);
        final rejected = _Document();
        when(() => rejected.set(any(), any())).thenThrow(
          FirebaseException(plugin: 'cloud_firestore', code: 'aborted'),
        );
        return rejected;
      });
      when(
        () => collection.where('pieceId', isEqualTo: any(named: 'isEqualTo')),
      ).thenAnswer(
        (call) =>
            remote.where('pieceId', isEqualTo: call.namedArguments[#isEqualTo]),
      );
      when(
        () => collection.get(any()),
      ).thenAnswer((call) => read(name, call, remote, cached));
      when(
        () => collection.where(
          'updatedAt',
          isGreaterThanOrEqualTo: any(named: 'isGreaterThanOrEqualTo'),
        ),
      ).thenAnswer((call) {
        final since = call.namedArguments[#isGreaterThanOrEqualTo];
        final query = _Query();
        when(() => query.get(any())).thenAnswer(
          (call) => read(
            name,
            call,
            remote.where('updatedAt', isGreaterThanOrEqualTo: since),
            cached.where('updatedAt', isGreaterThanOrEqualTo: since),
          ),
        );
        return query;
      });
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> read(
    String name,
    Invocation call,
    Query<Map<String, dynamic>> remote,
    Query<Map<String, dynamic>> cached,
  ) async {
    reads.add(name);
    final options = call.positionalArguments.single as GetOptions?;
    if (unavailableCollection == name) {
      if (options?.source == Source.server) {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      }
      return cached.get();
    }
    final snapshot = await remote.get();
    returnedCounts[name] = snapshot.docs.length;
    await afterRead?.call(name);
    return snapshot;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(const GetOptions());
    registerFallbackValue(SetOptions(merge: true));
    registerFallbackValue((Transaction _) async {});
  });

  for (final fullPull in [true, false]) {
    test(
      '${fullPull ? 'full' : 'incremental'} slow pull keeps a late clay edit for the next sync',
      () async {
        SharedPreferences.setMockInitialValues({});
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final network = _Network();
        final service = SyncService(
          db,
          network.firestore,
          MockFirebaseStorage(),
        );
        final clay = network.server.doc('users/user-1/clays/clay');
        await clay.set({
          'createdAt': Timestamp.fromDate(DateTime(2020)),
          'name': 'Before',
          'updatedAt': Timestamp.fromDate(network.serverTime),
        });
        await service.pullAll('user-1');
        network.serverTime = network.serverTime.add(
          const Duration(seconds: 10),
        );
        final boundary = network.serverTime;
        network.afterRead = (name) async {
          if (name == 'pieceTags') {
            await clay.update({
              'name': 'During download',
              'updatedAt': Timestamp.fromDate(
                boundary.add(const Duration(seconds: 4)),
              ),
            });
          }
        };
        if (fullPull) {
          await service.pullAll('user-1');
        } else {
          await service.pullChangedSince(
            'user-1',
            (await service.getLastPulledAt('user-1'))!,
          );
        }
        expect((await db.materialsDao.getAllClays()).single.name, 'Before');
        network.afterRead = null;
        network.serverTime = boundary.add(const Duration(seconds: 6));
        await service.pullChangedSince(
          'user-1',
          (await service.getLastPulledAt('user-1'))!,
        );
        expect(
          (await db.materialsDao.getAllClays()).single.name,
          'During download',
        );
      },
    );
  }

  test(
    'device clock ahead of server cannot blank the next edit window',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final network = _Network();
      expect(DateTime.now().isAfter(network.serverTime), isTrue);
      final service = SyncService(db, network.firestore, MockFirebaseStorage());
      await service.pullAll('user-1');
      final previous = (await service.getLastPulledAt('user-1'))!;
      network.serverTime = network.serverTime.add(const Duration(seconds: 4));
      await network.server.doc('users/user-1/clays/clay').set({
        'createdAt': Timestamp.fromDate(DateTime(2020)),
        'name': 'Remote edit',
        'updatedAt': Timestamp.fromDate(network.serverTime),
      });
      await service.pullChangedSince('user-1', previous);
      expect(
        (await db.materialsDao.getAllClays()).map((c) => c.name),
        contains('Remote edit'),
      );
      expect(await service.getLastPulledAt('user-1'), network.serverTime);
    },
  );

  test(
    'legacy future marker recovers skipped edits without bulk uploading stale local data',
    () async {
      SharedPreferences.setMockInitialValues({
        '${SyncService.lastPulledAtPrefix}user-1': DateTime(
          2099,
        ).millisecondsSinceEpoch,
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final network = _Network();
      final service = SyncService(db, network.firestore, MockFirebaseStorage());
      final clay = network.server.doc('users/user-1/clays/clay');
      await clay.set({
        'createdAt': Timestamp.fromDate(DateTime(2020)),
        'name': 'Stale local copy',
        'updatedAt': Timestamp.fromDate(DateTime(2020)),
      });
      // Populate local state without giving it a modern watermark.
      await service.pullChangedSince('user-1', DateTime(1970));
      SharedPreferences.setMockInitialValues({
        '${SyncService.lastPulledAtPrefix}user-1': DateTime(
          2099,
        ).millisecondsSinceEpoch,
      });
      await clay.update({
        'name': 'Previously skipped edit',
        'updatedAt': Timestamp.fromDate(DateTime(2021)),
      });
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (_) => AuthNotifier.withState(
              const AuthState(status: AuthStatus.authenticated, uid: 'user-1'),
            ),
          ),
          syncQueueProvider.overrideWithValue(SyncQueue()),
          syncServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      await container.read(syncStateProvider.notifier).syncNow();
      expect(container.read(syncStateProvider).status, SyncStatus.idle);
      expect(
        (await db.materialsDao.getAllClays()).single.name,
        'Previously skipped edit',
      );
      expect((await clay.get()).data()?['name'], 'Previously skipped edit');
      expect(await service.getLastPulledAt('user-1'), network.serverTime);
      network.returnedCounts.clear();
      network.serverTime = network.serverTime.add(const Duration(seconds: 10));
      await container.read(syncStateProvider.notifier).syncNow();
      expect(await service.getLastPulledAt('user-1'), network.serverTime);
      expect(network.returnedCounts['clays'], 0);
    },
  );

  test('a clay renamed during the migration pull keeps the rename', () async {
    SharedPreferences.setMockInitialValues({
      '${SyncService.lastPulledAtPrefix}user-1': DateTime(
        2099,
      ).millisecondsSinceEpoch,
    });
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final network = _Network();
    final service = SyncService(db, network.firestore, MockFirebaseStorage());
    final clay = network.server.doc('users/user-1/clays/clay');
    await clay.set({
      'createdAt': Timestamp.fromDate(DateTime(2020)),
      'name': 'Stoneware',
      'updatedAt': Timestamp.fromDate(DateTime(2020)),
    });
    await db
        .into(db.clayOptions)
        .insert(
          ClayOptionsCompanion.insert(
            id: 'clay',
            name: 'Stoneware',
            createdAt: DateTime(2020),
          ),
        );
    final queue = SyncQueue();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (_) => AuthNotifier.withState(
            const AuthState(status: AuthStatus.authenticated, uid: 'user-1'),
          ),
        ),
        syncQueueProvider.overrideWithValue(queue),
        syncServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    network.afterRead = (name) async {
      if (name != 'clays') return;
      network.afterRead = null;
      await db.materialsDao.updateClayName('clay', 'Porcelain');
      await queue.enqueue(
        const SyncQueueEntry(
          operation: SyncOperation.pushClay,
          entityId: 'clay',
        ),
      );
    };
    final notifier = container.read(syncStateProvider.notifier);

    await notifier.syncNow();
    expect(container.read(syncStateProvider).status, SyncStatus.idle);
    expect((await db.materialsDao.getAllClays()).single.name, 'Porcelain');

    await notifier.syncNow();
    expect((await clay.get()).data()?['name'], 'Porcelain');
    expect((await db.materialsDao.getAllClays()).single.name, 'Porcelain');
    expect(await queue.pendingCount, 0);
  });

  test(
    'material writes whose push exhausted its retries survive the migration pull',
    () async {
      SharedPreferences.setMockInitialValues({
        '${SyncService.lastPulledAtPrefix}user-1': DateTime(
          2099,
        ).millisecondsSinceEpoch,
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final network = _Network()..rejectedWrites.addAll(['clay', 'glaze']);
      final service = SyncService(db, network.firestore, MockFirebaseStorage());
      final clay = network.server.doc('users/user-1/clays/clay');
      await clay.set({
        'createdAt': Timestamp.fromDate(DateTime(2020)),
        'name': 'Stoneware',
        'updatedAt': Timestamp.fromDate(DateTime(2020)),
      });
      final glaze = network.server.doc('users/user-1/glazes/glaze');
      await glaze.set({
        'createdAt': Timestamp.fromDate(DateTime(2020)),
        'name': 'Deleted locally',
        'updatedAt': Timestamp.fromDate(DateTime(2020)),
      });
      await db
          .into(db.clayOptions)
          .insert(
            ClayOptionsCompanion.insert(
              id: 'clay',
              name: 'Porcelain',
              createdAt: DateTime(2020),
            ),
          );
      final queue = SyncQueue();
      await queue.enqueue(
        const SyncQueueEntry(
          operation: SyncOperation.pushClay,
          entityId: 'clay',
        ),
      );
      await queue.enqueue(
        const SyncQueueEntry(
          operation: SyncOperation.deleteMaterial,
          entityId: 'glaze',
          extraData: 'glazes',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (_) => AuthNotifier.withState(
              const AuthState(status: AuthStatus.authenticated, uid: 'user-1'),
            ),
          ),
          syncQueueProvider.overrideWithValue(queue),
          syncServiceProvider.overrideWithValue(service),
          syncStateProvider.overrideWith(
            (ref) => SyncNotifier(ref, queue, service, clock: _InstantClock()),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      final notifier = container.read(syncStateProvider.notifier);

      await notifier.syncNow();
      expect(await service.getLastPulledAt('user-1'), network.serverTime);
      expect((await db.materialsDao.getAllClays()).single.name, 'Porcelain');
      expect(await db.materialsDao.getAllGlazes(), isEmpty);
      expect(await queue.pendingCount, 2);

      network.rejectedWrites.clear();
      await notifier.syncNow();
      expect((await clay.get()).data()?['name'], 'Porcelain');
      expect((await glaze.get()).data()?['deletedAt'], isNotNull);
      expect((await db.materialsDao.getAllClays()).single.name, 'Porcelain');
      expect(await db.materialsDao.getAllGlazes(), isEmpty);
      expect(await queue.pendingCount, 0);
    },
  );

  test(
    'equal boundary timestamps and sub-millisecond writes are replayed',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final network = _Network()
        ..serverTime = DateTime.utc(2024, 1, 1, 0, 0, 0, 0, 500);
      final service = SyncService(db, network.firestore, MockFirebaseStorage());
      await service.pullAll('user-1');
      final boundary = (await service.getLastPulledAt('user-1'))!;
      for (final entry in {
        'equal': boundary,
        'precise': network.serverTime,
      }.entries) {
        await network.server.doc('users/user-1/clays/${entry.key}').set({
          'name': entry.key,
          'createdAt': Timestamp.fromDate(DateTime(2020)),
          'updatedAt': Timestamp.fromDate(entry.value),
        });
      }
      network.serverTime = network.serverTime.add(const Duration(seconds: 1));
      await service.pullChangedSince('user-1', boundary);
      expect(
        (await db.materialsDao.getAllClays()).map((c) => c.name),
        unorderedEquals(['equal', 'precise']),
      );
    },
  );

  test(
    'client-timed pieces remain discoverable below the server boundary without replacing newer local edits',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final network = _Network();
      final service = SyncService(db, network.firestore, MockFirebaseStorage());
      final piece = network.server.doc('users/user-1/pieces/piece');
      await piece.set({
        'title': 'Before',
        'createdAt': Timestamp.fromDate(DateTime(2020)),
        'updatedAt': Timestamp.fromDate(DateTime(2020)),
      });
      await service.pullAll('user-1');
      await piece.update({
        'title': 'Slow clock edit',
        'updatedAt': Timestamp.fromDate(DateTime(2021)),
      });
      await service.pullChangedSince(
        'user-1',
        (await service.getLastPulledAt('user-1'))!,
      );
      expect(
        (await db.piecesDao.getPieceById('piece'))?.title,
        'Slow clock edit',
      );
      await db.piecesDao.updatePiece(
        PiecesCompanion(
          id: const Value('piece'),
          title: const Value('Unsent local edit'),
          updatedAt: Value(DateTime(2025)),
        ),
      );
      await service.pullChangedSince(
        'user-1',
        (await service.getLastPulledAt('user-1'))!,
      );
      expect(
        (await db.piecesDao.getPieceById('piece'))?.title,
        'Unsent local edit',
      );
    },
  );

  test('a piece deleted during an incremental pull stays deleted', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final network = _Network();
    final service = SyncService(db, network.firestore, MockFirebaseStorage());
    await network.server.doc('users/user-1/pieces/piece').set({
      'title': 'Deleted here',
      'createdAt': Timestamp.fromDate(DateTime(2020)),
      'updatedAt': Timestamp.fromDate(DateTime(2020)),
    });
    await service.pullAll('user-1');
    expect(await db.piecesDao.getPieceById('piece'), isNotNull);
    final images = _Images();
    when(() => images.deletePhotos(any())).thenAnswer((_) async {});
    final queue = SyncQueue();
    final writer = PieceWriter(
      piecesDao: db.piecesDao,
      photosDao: db.photosDao,
      imageService: images,
      syncTrigger: SyncTrigger(queue),
    );
    network.afterRead = (name) async {
      if (name != 'pieces') return;
      network.afterRead = null;
      await writer.deletePiece('piece');
    };

    await service.pullChangedSince(
      'user-1',
      (await service.getLastPulledAt('user-1'))!,
    );

    expect(await db.piecesDao.getPieceById('piece'), isNull);
    expect((await queue.getAll()).map((e) => (e.operation, e.entityId)), [
      (SyncOperation.deletePiece, 'piece'),
    ]);
  });

  for (final response in ['unavailable', 'cache', 'pending', 'missing']) {
    test(
      'unconfirmed boundary ($response) leaves the marker and data untouched',
      () async {
        final previous = DateTime(2020);
        final stored = 'server-v1:${previous.millisecondsSinceEpoch}';
        SharedPreferences.setMockInitialValues({
          '${SyncService.lastPulledAtPrefix}user-1': stored,
        });
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        final network = _Network()..boundaryResponse = response;
        final service = SyncService(
          db,
          network.firestore,
          MockFirebaseStorage(),
        );
        await expectLater(
          service.pullChangedSince('user-1', previous),
          throwsA(isA<FirebaseException>()),
        );
        expect(network.reads, isEmpty);
        expect(await service.getLastPulledAt('user-1'), previous);
        expect(
          (await SharedPreferences.getInstance()).get(
            '${SyncService.lastPulledAtPrefix}user-1',
          ),
          stored,
        );
      },
    );
  }

  test(
    'offline Sync Now with nothing queued reports unavailable instead of waiting on the boundary',
    () async {
      final previous = DateTime(2020);
      SharedPreferences.setMockInitialValues({
        '${SyncService.lastPulledAtPrefix}user-1':
            'server-v1:${previous.millisecondsSinceEpoch}',
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final network = _Network()..unavailableCollection = 'meta';
      final service = SyncService(db, network.firestore, MockFirebaseStorage());
      final queue = SyncQueue();
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (_) => AuthNotifier.withState(
              const AuthState(status: AuthStatus.authenticated, uid: 'user-1'),
            ),
          ),
          syncQueueProvider.overrideWithValue(queue),
          syncServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      expect(await queue.pendingCount, 0);

      await container
          .read(syncStateProvider.notifier)
          .syncNow()
          .timeout(const Duration(seconds: 5));

      final state = container.read(syncStateProvider);
      expect(state.status, SyncStatus.error);
      expect(state.errorMessage, SyncState.unavailableErrorCode);
      expect(network.reads, isEmpty);
      expect(await service.getLastPulledAt('user-1'), previous);
    },
  );

  test(
    'failed legacy migration retries broadly and replaces the marker only after success',
    () async {
      final legacy = DateTime(2099).millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        '${SyncService.lastPulledAtPrefix}user-1': legacy,
      });
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final network = _Network()..unavailableCollection = 'pieceTags';
      final service = SyncService(db, network.firestore, MockFirebaseStorage());
      await expectLater(
        service.pullChangedSince(
          'user-1',
          (await service.getLastPulledAt('user-1'))!,
        ),
        throwsA(isA<FirebaseException>()),
      );
      expect(
        (await SharedPreferences.getInstance()).get(
          '${SyncService.lastPulledAtPrefix}user-1',
        ),
        legacy,
      );
      // Legacy data without updatedAt must still be recovered by the broad retry.
      await network.server.doc('users/user-1/clays/legacy').set({
        'name': 'Recovered',
        'createdAt': Timestamp.fromDate(DateTime(2020)),
      });
      network.unavailableCollection = null;
      await service.pullChangedSince(
        'user-1',
        (await service.getLastPulledAt('user-1'))!,
      );
      expect((await db.materialsDao.getAllClays()).single.name, 'Recovered');
      expect(await service.getLastPulledAt('user-1'), network.serverTime);
    },
  );

  for (final fullSync in [true, false]) {
    for (final unavailable in [
      'meta',
      'pieces',
      'photos',
      'clays',
      'glazes',
      'tags',
      'pieceGlazes',
      'pieceTags',
    ]) {
      test(
        '${fullSync ? 'full' : 'incremental'} offline $unavailable pull '
        'cannot complete or advance the watermark; reconnect recovers edits',
        () async {
          final previous = DateTime(2020);
          SharedPreferences.setMockInitialValues({
            if (!fullSync)
              '${SyncService.lastPulledAtPrefix}user-1':
                  'server-v1:${previous.millisecondsSinceEpoch}',
          });
          final db = AppDatabase.forTesting(NativeDatabase.memory());
          final network = _Network()..unavailableCollection = unavailable;
          // A different device wrote this after our previous cursor but before
          // the offline attempt. An end-of-attempt cache watermark would skip it.
          final edited = Timestamp.fromDate(DateTime(2021));
          await network.server.doc('users/user-1/pieces/remote-piece').set({
            'title': 'Other device edit',
            'createdAt': edited,
            'updatedAt': edited,
          });
          final queue = SyncQueue();
          final service = SyncService(
            db,
            network.firestore,
            MockFirebaseStorage(),
          );
          final container = ProviderContainer(
            overrides: [
              authProvider.overrideWith(
                (_) => AuthNotifier.withState(
                  const AuthState(status: AuthStatus.unauthenticated),
                ),
              ),
              syncQueueProvider.overrideWithValue(queue),
              syncServiceProvider.overrideWithValue(service),
            ],
          );
          addTearDown(() async {
            container.dispose();
            await db.close();
          });
          final notifier = container.read(syncStateProvider.notifier);
          final finished = Completer<SyncState>();
          var started = false;
          final sub = container.listen(syncStateProvider, (_, next) {
            if (next.status == SyncStatus.syncing) started = true;
            if (started &&
                next.status != SyncStatus.syncing &&
                !finished.isCompleted) {
              finished.complete(next);
            }
          });
          addTearDown(sub.close);
          container.read(authProvider.notifier).state = const AuthState(
            status: AuthStatus.authenticated,
            uid: 'user-1',
          );
          final failed = await finished.future.timeout(
            const Duration(seconds: 5),
          );
          expect(
            failed.status,
            SyncStatus.error,
            reason: 'cache fallback is not a completed server sync',
          );
          expect(failed.lastSyncedAt, isNull);
          expect(
            await service.getLastPulledAt('user-1'),
            fullSync ? isNull : previous,
          );

          network.unavailableCollection = null;
          await notifier.syncNow();
          expect(container.read(syncStateProvider).status, SyncStatus.idle);
          expect(container.read(syncStateProvider).lastSyncedAt, isNotNull);
          expect(await service.getLastPulledAt('user-1'), isNotNull);
          expect(
            (await db.piecesDao.getPieceById('remote-piece'))?.title,
            'Other device edit',
          );
        },
      );
    }
  }
}
