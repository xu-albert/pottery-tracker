// These SDK-boundary mocks exercise server/cache behavior without native Firebase.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/providers/sync_provider.dart';
import 'package:pottery_tracker/services/sync_queue.dart';
import 'package:pottery_tracker/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Firestore extends Mock implements FirebaseFirestore {}

class _Document extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class _Collection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _Query extends Mock implements Query<Map<String, dynamic>> {}

/// Models the SDK boundary: default reads can return an incomplete offline
/// cache; server reads fail offline. Both stores execute real query filtering.
class _Network {
  final firestore = _Firestore();
  final server = FakeFirebaseFirestore();
  final cache = FakeFirebaseFirestore();
  String? unavailableCollection;

  _Network() {
    final user = _Document();
    when(() => firestore.doc('users/user-1')).thenReturn(user);
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
      when(() => collection.doc(any())).thenAnswer(
        (call) => remote.doc(call.positionalArguments.single as String),
      );
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
          isGreaterThan: any(named: 'isGreaterThan'),
        ),
      ).thenAnswer((call) {
        final since = call.namedArguments[#isGreaterThan];
        final query = _Query();
        when(() => query.get(any())).thenAnswer(
          (call) => read(
            name,
            call,
            remote.where('updatedAt', isGreaterThan: since),
            cached.where('updatedAt', isGreaterThan: since),
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
  ) {
    final options = call.positionalArguments.single as GetOptions?;
    if (unavailableCollection == name) {
      if (options?.source == Source.server) {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
      }
      return cached.get();
    }
    return remote.get();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => registerFallbackValue(const GetOptions()));

  for (final fullSync in [true, false]) {
    for (final unavailable in [
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
                  previous.millisecondsSinceEpoch,
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
