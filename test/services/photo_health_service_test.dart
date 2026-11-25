import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/services/photo_health_service.dart';
import 'package:pottery_tracker/services/photo_paths.dart';
import 'package:pottery_tracker/services/telemetry_service.dart';

void main() {
  late AppDatabase db;
  late Directory tempDocs;
  late PhotoPaths photoPaths;

  final baseTime = DateTime(2026, 11, 1, 12, 0);

  PackageInfo fakePackageInfo() => PackageInfo(
    appName: 'Potter Journal',
    packageName: 'com.albertxu.potterytracker',
    version: '1.2.4',
    buildNumber: '29',
  );

  Future<void> seedPiece(String pieceId) async {
    await db.piecesDao.insertPiece(
      PiecesCompanion.insert(
        id: pieceId,
        title: const Value('Secret Vase Name'),
        stage: const Value('greenware'),
        clayType: const Value('Stoneware'),
        createdAt: baseTime,
        updatedAt: baseTime,
      ),
    );
  }

  Future<void> seedPhoto({
    required String id,
    required String pieceId,
    required String localPath,
    String? cloudUrl,
    bool createFile = false,
  }) async {
    await db.photosDao.insertPhoto(
      PhotosCompanion.insert(
        id: id,
        pieceId: pieceId,
        localPath: localPath,
        cloudUrl: Value(cloudUrl),
        dateTaken: baseTime,
        createdAt: baseTime,
      ),
    );
    if (createFile) {
      final file = photoPaths.mainFile(pieceId, id);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);
    }
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tempDocs = Directory.systemTemp.createTempSync('photo_health_test_');
    photoPaths = PhotoPaths(tempDocs.path);
  });

  tearDown(() async {
    await db.close();
    if (tempDocs.existsSync()) {
      tempDocs.deleteSync(recursive: true);
    }
  });

  group('PhotoHealthService.computeSnapshot', () {
    test('reports allVisible=true for an empty library', () async {
      final service = PhotoHealthService(isFirebaseReady: () => false);

      final snapshot = await service.computeSnapshot(
        db: db,
        photoPaths: photoPaths,
        trigger: PhotoHealthTrigger.startup,
        repairedCount: 0,
      );

      expect(snapshot.trigger, PhotoHealthTrigger.startup);
      expect(snapshot.totalPhotos, 0);
      expect(snapshot.presentLocal, 0);
      expect(snapshot.repairedCount, 0);
      expect(snapshot.missingLocal, 0);
      expect(snapshot.missingWithCloud, 0);
      expect(snapshot.missingUnrecoverable, 0);
      expect(snapshot.allVisible, isTrue);
    });

    test(
      'counts present, relocated, missing-with-cloud, and missing-unrecoverable accurately',
      () async {
        await seedPiece('piece-1');
        // 1. Present via canonical relative path.
        await seedPhoto(
          id: 'ph-present',
          pieceId: 'piece-1',
          localPath: PhotoPaths.relativeMainPath('piece-1', 'ph-present'),
          createFile: true,
        );
        // 2. Present via legacy absolute container path rebased onto tempDocs.
        await seedPhoto(
          id: 'ph-relocated',
          pieceId: 'piece-1',
          localPath:
              '/var/mobile/Containers/Data/Application/OLD-UUID/Documents/'
              'photos/piece-1/ph-relocated.jpg',
          createFile: true,
        );
        // 3. Missing locally, recoverable from cloudUrl.
        await seedPhoto(
          id: 'ph-cloud',
          pieceId: 'piece-1',
          localPath: PhotoPaths.relativeMainPath('piece-1', 'ph-cloud'),
          cloudUrl: 'https://storage.googleapis.com/bucket/ph-cloud.jpg',
          createFile: false,
        );
        // 4. Missing locally, null cloudUrl (unrecoverable).
        await seedPhoto(
          id: 'ph-unrec-null',
          pieceId: 'piece-1',
          localPath: PhotoPaths.relativeMainPath('piece-1', 'ph-unrec-null'),
          cloudUrl: null,
          createFile: false,
        );
        // 5. Missing locally, whitespace-only cloudUrl (unrecoverable).
        await seedPhoto(
          id: 'ph-unrec-blank',
          pieceId: 'piece-1',
          localPath: PhotoPaths.relativeMainPath('piece-1', 'ph-unrec-blank'),
          cloudUrl: '   ',
          createFile: false,
        );

        final service = PhotoHealthService(isFirebaseReady: () => false);
        final snapshot = await service.computeSnapshot(
          db: db,
          photoPaths: photoPaths,
          trigger: PhotoHealthTrigger.startup,
          repairedCount: 2,
        );

        expect(snapshot.totalPhotos, 5);
        expect(snapshot.presentLocal, 2);
        expect(snapshot.repairedCount, 2);
        expect(snapshot.missingLocal, 3);
        expect(snapshot.missingWithCloud, 1);
        expect(snapshot.missingUnrecoverable, 2);
        expect(snapshot.allVisible, isFalse);
      },
    );
  });

  group('PhotoHealthService.report', () {
    test(
      'emits zero-PII telemetry to Analytics, Firestore, and Crashlytics when signed in',
      () async {
        await seedPiece('piece-secret-title');
        await seedPhoto(
          id: 'ph-ok',
          pieceId: 'piece-secret-title',
          localPath: PhotoPaths.relativeMainPath('piece-secret-title', 'ph-ok'),
          createFile: true,
        );
        await seedPhoto(
          id: 'ph-recoverable',
          pieceId: 'piece-secret-title',
          localPath: PhotoPaths.relativeMainPath(
            'piece-secret-title',
            'ph-recoverable',
          ),
          cloudUrl: 'https://example.com/recoverable.jpg',
        );
        await seedPhoto(
          id: 'ph-lost',
          pieceId: 'piece-secret-title',
          localPath: PhotoPaths.relativeMainPath(
            'piece-secret-title',
            'ph-lost',
          ),
          cloudUrl: null,
        );

        final firestore = FakeFirebaseFirestore();
        final analyticsEvents = <(String, Map<String, Object>)>[];
        final customKeys = <String, Object>{};
        final crashLogs = <String>[];
        final nonFatals =
            <
              (Object error, String reason, Iterable<Object> info, bool fatal)
            >[];

        final telemetry = TelemetryService(
          isFirebaseReady: () => true,
          log: crashLogs.add,
          setCustomKey: (key, value) => customKeys[key] = value,
          recordError:
              (
                error,
                stack, {
                required String reason,
                required Iterable<Object> information,
                required bool fatal,
              }) {
                nonFatals.add((error, reason, information, fatal));
              },
        );

        final service = PhotoHealthService(
          isFirebaseReady: () => true,
          telemetry: telemetry,
          logAnalyticsEvent: (name, params) =>
              analyticsEvents.add((name, params)),
          firestore: firestore,
          packageInfoLoader: () async => fakePackageInfo(),
          platformResolver: () => 'ios',
        );

        final snapshot = await service.report(
          db: db,
          photoPaths: photoPaths,
          trigger: PhotoHealthTrigger.startup,
          repairedCount: 1,
          uid: 'user-abc',
        );

        expect(snapshot, isNotNull);
        expect(snapshot!.allVisible, isFalse);

        // 1. Firebase Analytics event + exact allowlisted params.
        expect(analyticsEvents, hasLength(1));
        expect(analyticsEvents.single.$1, 'photo_health_check');
        expect(analyticsEvents.single.$2, {
          'app_version': '1.2.4+29',
          'trigger': 'startup',
          'total_photos': 3,
          'present_local': 1,
          'repaired_count': 1,
          'missing_local': 2,
          'missing_with_cloud': 1,
          'missing_unrecoverable': 1,
          'all_visible': 0,
        });

        // 2. Firestore users/{uid}/diagnostics/photo_health doc.
        final doc = await firestore
            .collection('users')
            .doc('user-abc')
            .collection('diagnostics')
            .doc('photo_health')
            .get();
        expect(doc.exists, isTrue);
        final data = doc.data()!;
        expect(data.keys.toSet(), {
          'appVersion',
          'platform',
          'trigger',
          'checkedAt',
          'totalPhotos',
          'presentLocal',
          'repairedCount',
          'missingLocal',
          'missingWithCloud',
          'missingUnrecoverable',
          'allVisible',
        });
        expect(data['appVersion'], '1.2.4+29');
        expect(data['platform'], 'ios');
        expect(data['trigger'], 'startup');
        expect(data['checkedAt'], isA<Timestamp>());
        expect(data['totalPhotos'], 3);
        expect(data['presentLocal'], 1);
        expect(data['repairedCount'], 1);
        expect(data['missingLocal'], 2);
        expect(data['missingWithCloud'], 1);
        expect(data['missingUnrecoverable'], 1);
        expect(data['allVisible'], isFalse);

        // 3. Crashlytics custom keys are set on startup while the unrecoverable
        // non-fatal is deferred until post_sync for signed-in users.
        expect(customKeys['photos_missing_unrecoverable_count'], 1);
        expect(customKeys['photos_all_visible'], isFalse);
        expect(nonFatals, isEmpty);

        await service.report(
          db: db,
          photoPaths: photoPaths,
          trigger: PhotoHealthTrigger.postSync,
          repairedCount: 0,
          uid: 'user-abc',
        );

        expect(nonFatals, hasLength(1));
        expect(nonFatals.single.$1, isA<SanitizedTelemetryError>());
        expect(
          nonFatals.single.$1.toString(),
          'photo.missing_unrecoverable: PhotoMissingUnrecoverableException',
        );
        expect(nonFatals.single.$2, 'photo.missing_unrecoverable');
        expect(
          nonFatals.single.$3,
          contains(
            'photo.missing_unrecoverable trigger=post_sync '
            'missing_unrecoverable=1 total=3 '
            'error=PhotoMissingUnrecoverableException',
          ),
        );
        expect(nonFatals.single.$4, isFalse);

        // Zero PII check across every emitted payload.
        final serialized = [
          analyticsEvents.toString(),
          data.toString(),
          crashLogs.toString(),
          nonFatals.toString(),
        ].join('\n');
        expect(serialized, isNot(contains('piece-secret-title')));
        expect(serialized, isNot(contains('Secret Vase Name')));
        expect(serialized, isNot(contains('ph-lost')));
        expect(serialized, isNot(contains(tempDocs.path)));
        expect(serialized, isNot(contains('user-abc')));
      },
    );

    test(
      'defers photo.missing_unrecoverable non-fatal to post_sync for signed-in '
      'users, reports the post-recovery count, and latches once per session',
      () async {
        await seedPiece('p1');
        await seedPhoto(
          id: 'ph-recovered',
          pieceId: 'p1',
          localPath: PhotoPaths.relativeMainPath('p1', 'ph-recovered'),
          cloudUrl: null,
        );
        await seedPhoto(
          id: 'ph-lost',
          pieceId: 'p1',
          localPath: PhotoPaths.relativeMainPath('p1', 'ph-lost'),
          cloudUrl: null,
        );

        final firestore = FakeFirebaseFirestore();
        final analyticsEvents = <(String, Map<String, Object>)>[];
        final nonFatals = <(String reason, List<Object> info)>[];
        final customKeys = <String, Object>{};
        final telemetry = TelemetryService(
          isFirebaseReady: () => true,
          log: (_) {},
          setCustomKey: (k, v) => customKeys[k] = v,
          recordError:
              (
                error,
                stack, {
                required String reason,
                required Iterable<Object> information,
                required bool fatal,
              }) {
                nonFatals.add((reason, information.toList()));
              },
        );

        final service = PhotoHealthService(
          isFirebaseReady: () => true,
          telemetry: telemetry,
          logAnalyticsEvent: (name, params) =>
              analyticsEvents.add((name, params)),
          firestore: firestore,
          packageInfoLoader: () async => fakePackageInfo(),
          platformResolver: () => 'ios',
        );

        await service.report(
          db: db,
          photoPaths: photoPaths,
          trigger: PhotoHealthTrigger.startup,
          repairedCount: 2,
          uid: 'user-1',
        );

        expect(nonFatals, isEmpty);
        expect(customKeys['photos_missing_unrecoverable_count'], 2);

        final recoveredFile = photoPaths.mainFile('p1', 'ph-recovered');
        recoveredFile.parent.createSync(recursive: true);
        recoveredFile.writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);

        await service.report(
          db: db,
          photoPaths: photoPaths,
          trigger: PhotoHealthTrigger.postSync,
          repairedCount: 0,
          uid: 'user-1',
        );
        await service.report(
          db: db,
          photoPaths: photoPaths,
          trigger: PhotoHealthTrigger.postSync,
          repairedCount: 0,
          uid: 'user-1',
        );

        expect(nonFatals, hasLength(1));
        expect(nonFatals.single.$1, 'photo.missing_unrecoverable');
        expect(
          nonFatals.single.$2,
          contains(
            'photo.missing_unrecoverable trigger=post_sync '
            'missing_unrecoverable=1 total=2 '
            'error=PhotoMissingUnrecoverableException',
          ),
        );
        expect(analyticsEvents, hasLength(3));
        expect(analyticsEvents[0].$2['trigger'], 'startup');
        expect(analyticsEvents[0].$2['repaired_count'], 2);
        expect(analyticsEvents[0].$2['missing_unrecoverable'], 2);
        expect(analyticsEvents[1].$2['trigger'], 'post_sync');
        expect(analyticsEvents[1].$2['repaired_count'], 0);
        expect(analyticsEvents[1].$2['missing_unrecoverable'], 1);

        final doc = await firestore
            .doc('users/user-1/diagnostics/photo_health')
            .get();
        expect(doc.data()!['trigger'], 'post_sync');
        expect(doc.data()!['repairedCount'], 0);
        expect(doc.data()!['missingUnrecoverable'], 1);
        expect(customKeys['photos_missing_unrecoverable_count'], 1);
        expect(customKeys['photos_all_visible'], isFalse);
      },
    );

    test(
      'never emits photo.missing_unrecoverable when signed-in sync recovers '
      'all orphaned photos before post_sync',
      () async {
        await seedPiece('p1');
        await seedPhoto(
          id: 'ph-orphan',
          pieceId: 'p1',
          localPath: PhotoPaths.relativeMainPath('p1', 'ph-orphan'),
          cloudUrl: null,
        );

        final nonFatals = <String>[];
        final customKeys = <String, Object>{};
        final telemetry = TelemetryService(
          isFirebaseReady: () => true,
          log: (_) {},
          setCustomKey: (k, v) => customKeys[k] = v,
          recordError:
              (
                error,
                stack, {
                required String reason,
                required Iterable<Object> information,
                required bool fatal,
              }) {
                nonFatals.add(reason);
              },
        );

        final service = PhotoHealthService(
          isFirebaseReady: () => true,
          telemetry: telemetry,
          logAnalyticsEvent: (_, _) {},
          firestore: FakeFirebaseFirestore(),
          packageInfoLoader: () async => fakePackageInfo(),
          platformResolver: () => 'ios',
        );

        await service.report(
          db: db,
          photoPaths: photoPaths,
          trigger: PhotoHealthTrigger.startup,
          uid: 'user-1',
        );
        expect(nonFatals, isEmpty);

        final recoveredFile = photoPaths.mainFile('p1', 'ph-orphan');
        recoveredFile.parent.createSync(recursive: true);
        recoveredFile.writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);

        await service.report(
          db: db,
          photoPaths: photoPaths,
          trigger: PhotoHealthTrigger.postSync,
          uid: 'user-1',
        );

        expect(nonFatals, isEmpty);
        expect(customKeys['photos_missing_unrecoverable_count'], 0);
        expect(customKeys['photos_all_visible'], isTrue);
      },
    );

    test(
      'emits photo.missing_unrecoverable on startup for local-only (uid == null) '
      'sessions at most once',
      () async {
        await seedPiece('p1');
        await seedPhoto(
          id: 'ph-local-lost',
          pieceId: 'p1',
          localPath: PhotoPaths.relativeMainPath('p1', 'ph-local-lost'),
          cloudUrl: null,
        );

        final firestore = FakeFirebaseFirestore();
        final nonFatals = <(String reason, List<Object> info)>[];
        final customKeys = <String, Object>{};
        final telemetry = TelemetryService(
          isFirebaseReady: () => true,
          log: (_) {},
          setCustomKey: (k, v) => customKeys[k] = v,
          recordError:
              (
                error,
                stack, {
                required String reason,
                required Iterable<Object> information,
                required bool fatal,
              }) {
                nonFatals.add((reason, information.toList()));
              },
        );

        final service = PhotoHealthService(
          isFirebaseReady: () => true,
          telemetry: telemetry,
          logAnalyticsEvent: (_, _) {},
          firestore: firestore,
          packageInfoLoader: () async => fakePackageInfo(),
          platformResolver: () => 'ios',
        );

        await service.report(
          db: db,
          photoPaths: photoPaths,
          trigger: PhotoHealthTrigger.startup,
          uid: null,
        );
        await service.report(
          db: db,
          photoPaths: photoPaths,
          trigger: PhotoHealthTrigger.startup,
          uid: null,
        );

        expect(nonFatals, hasLength(1));
        expect(nonFatals.single.$1, 'photo.missing_unrecoverable');
        expect(
          nonFatals.single.$2,
          contains(
            'photo.missing_unrecoverable trigger=startup '
            'missing_unrecoverable=1 total=1 '
            'error=PhotoMissingUnrecoverableException',
          ),
        );
        expect(customKeys['photos_missing_unrecoverable_count'], 1);
        expect(customKeys['photos_all_visible'], isFalse);
        final usersSnap = await firestore.collection('users').get();
        expect(usersSnap.docs, isEmpty);
      },
    );

    test(
      'does not emit non-fatal when all photos are visible or only missingWithCloud',
      () async {
        await seedPiece('p1');
        await seedPhoto(
          id: 'ph-cloud',
          pieceId: 'p1',
          localPath: PhotoPaths.relativeMainPath('p1', 'ph-cloud'),
          cloudUrl: 'https://example.com/ph-cloud.jpg',
        );

        final nonFatals = <String>[];
        final customKeys = <String, Object>{};
        final analyticsEvents = <Map<String, Object>>[];
        final telemetry = TelemetryService(
          isFirebaseReady: () => true,
          log: (_) {},
          setCustomKey: (k, v) => customKeys[k] = v,
          recordError:
              (
                error,
                stack, {
                required String reason,
                required Iterable<Object> information,
                required bool fatal,
              }) {
                nonFatals.add(reason);
              },
        );

        final service = PhotoHealthService(
          isFirebaseReady: () => true,
          telemetry: telemetry,
          logAnalyticsEvent: (_, params) => analyticsEvents.add(params),
          firestore: FakeFirebaseFirestore(),
          packageInfoLoader: () async => fakePackageInfo(),
          platformResolver: () => 'ios',
        );

        await service.report(
          db: db,
          photoPaths: photoPaths,
          trigger: PhotoHealthTrigger.startup,
          uid: 'user-1',
        );
        expect(nonFatals, isEmpty);
        expect(customKeys['photos_missing_unrecoverable_count'], 0);
        expect(customKeys['photos_all_visible'], isFalse);
        expect(analyticsEvents.last['all_visible'], 0);

        // Now materialize the photo on disk and re-run post_sync.
        final file = photoPaths.mainFile('p1', 'ph-cloud');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);

        await service.report(
          db: db,
          photoPaths: photoPaths,
          trigger: PhotoHealthTrigger.postSync,
          uid: 'user-1',
        );
        expect(nonFatals, isEmpty);
        expect(customKeys['photos_all_visible'], isTrue);
        expect(analyticsEvents.last['all_visible'], 1);
        expect(analyticsEvents.last['present_local'], 1);
        expect(analyticsEvents.last['missing_local'], 0);
      },
    );

    test(
      'skips Firestore write for signed-out local-only users while emitting Analytics and Crashlytics',
      () async {
        await seedPiece('p1');
        await seedPhoto(
          id: 'ph-ok',
          pieceId: 'p1',
          localPath: PhotoPaths.relativeMainPath('p1', 'ph-ok'),
          createFile: true,
        );

        final firestore = FakeFirebaseFirestore();
        final analyticsEvents = <(String, Map<String, Object>)>[];
        final customKeys = <String, Object>{};
        final telemetry = TelemetryService(
          isFirebaseReady: () => true,
          log: (_) {},
          setCustomKey: (k, v) => customKeys[k] = v,
        );

        final service = PhotoHealthService(
          isFirebaseReady: () => true,
          telemetry: telemetry,
          logAnalyticsEvent: (name, params) =>
              analyticsEvents.add((name, params)),
          firestore: firestore,
          packageInfoLoader: () async => fakePackageInfo(),
          platformResolver: () => 'android',
        );

        await service.report(
          db: db,
          photoPaths: photoPaths,
          trigger: PhotoHealthTrigger.startup,
          uid: null,
        );

        expect(analyticsEvents, hasLength(1));
        expect(analyticsEvents.single.$2['all_visible'], 1);
        expect(customKeys['photos_all_visible'], isTrue);
        final usersSnap = await firestore.collection('users').get();
        expect(usersSnap.docs, isEmpty);
      },
    );

    test(
      'is a clean no-op across all three Firebase surfaces when Firebase is not ready',
      () async {
        await seedPiece('p1');
        await seedPhoto(
          id: 'ph-lost',
          pieceId: 'p1',
          localPath: PhotoPaths.relativeMainPath('p1', 'ph-lost'),
        );

        var analyticsCalled = false;
        var crashlyticsKeyCalled = false;
        var crashlyticsErrorCalled = false;
        final firestore = FakeFirebaseFirestore();
        final telemetry = TelemetryService(
          isFirebaseReady: () => false,
          setCustomKey: (_, _) => crashlyticsKeyCalled = true,
          recordError:
              (
                _,
                _, {
                required String reason,
                required Iterable<Object> information,
                required bool fatal,
              }) {
                crashlyticsErrorCalled = true;
              },
        );

        final service = PhotoHealthService(
          isFirebaseReady: () => false,
          telemetry: telemetry,
          logAnalyticsEvent: (_, _) => analyticsCalled = true,
          firestore: firestore,
          packageInfoLoader: () async => fakePackageInfo(),
          platformResolver: () => 'ios',
        );

        final snapshot = await service.report(
          db: db,
          photoPaths: photoPaths,
          trigger: PhotoHealthTrigger.startup,
          uid: 'user-offline',
        );

        expect(snapshot, isNotNull);
        expect(snapshot!.missingUnrecoverable, 1);
        expect(analyticsCalled, isFalse);
        expect(crashlyticsKeyCalled, isFalse);
        expect(crashlyticsErrorCalled, isFalse);
        final doc = await firestore
            .doc('users/user-offline/diagnostics/photo_health')
            .get();
        expect(doc.exists, isFalse);
        expect(
          telemetry.recentBreadcrumbs,
          contains(startsWith('photo_health.check trigger=startup')),
        );
      },
    );

    test(
      'swallows Analytics, PackageInfo, and Firestore failures without blocking sibling surfaces',
      () async {
        await seedPiece('p1');
        await seedPhoto(
          id: 'ph-ok',
          pieceId: 'p1',
          localPath: PhotoPaths.relativeMainPath('p1', 'ph-ok'),
          createFile: true,
        );

        final firestore = FakeFirebaseFirestore();
        final customKeys = <String, Object>{};
        final telemetry = TelemetryService(
          isFirebaseReady: () => true,
          log: (_) {},
          setCustomKey: (k, v) => customKeys[k] = v,
        );

        final service = PhotoHealthService(
          isFirebaseReady: () => true,
          telemetry: telemetry,
          logAnalyticsEvent: (_, _) => throw StateError('analytics down'),
          firestore: firestore,
          packageInfoLoader: () async => throw StateError('no platform info'),
          platformResolver: () => 'ios',
        );

        await expectLater(
          service.report(
            db: db,
            photoPaths: photoPaths,
            trigger: PhotoHealthTrigger.postSync,
            uid: 'user-resilient',
          ),
          completes,
        );

        // Firestore and Crashlytics still succeeded with fallback appVersion.
        expect(customKeys['photos_all_visible'], isTrue);
        final doc = await firestore
            .doc('users/user-resilient/diagnostics/photo_health')
            .get();
        expect(doc.exists, isTrue);
        expect(doc.data()!['appVersion'], 'unknown');
        expect(
          telemetry.recentBreadcrumbs,
          contains('photo_health.analytics_failed error=StateError'),
        );
      },
    );
  });
}
