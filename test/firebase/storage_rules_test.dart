import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `storage.rules` has no emulator suite (TEST_PLAN §11-P2), so this pins
/// the two halves that must agree: the rules admit uploads only as a JPEG
/// under the size cap at the photo path, and the app's one upload is exactly
/// that. A rule change that loosens a write, or an upload that drifts from
/// the path or content type, fails here instead of in production.
void main() {
  final rules = File('storage.rules').readAsStringSync();
  final grants = RegExp(
    r'allow ([a-z, ]+):',
  ).allMatches(rules).map((m) => m.group(1)!).toList();

  // The photo rule's path and filename pattern, as the rules state them.
  final photoPath = RegExp(r'^users/[^/]+/photos/[^/]+/[^/]+\.jpg$');

  test('writes are granted only as create/update on the photo path; '
      'delete is separate, and nothing grants a blanket write', () {
    expect(grants, ['read, delete', 'create, update', 'read, write']);
    expect(rules, contains("allow read, write: if false;"));
    expect(
      rules,
      contains('match /users/{userId}/photos/{pieceId}/{photoFile} {'),
    );
  });

  test('an upload must be a JPEG under 10 MiB with a .jpg name', () {
    final upload = rules.substring(rules.indexOf('allow create, update:'));
    final clause = upload.substring(0, upload.indexOf(';'));
    expect(clause, contains('isOwner(userId)'));
    expect(clause, contains("photoFile.matches('[^/]+[.]jpg')"));
    expect(clause, contains("request.resource.contentType == 'image/jpeg'"));
    expect(clause, contains('request.resource.size < 10 * 1024 * 1024'));
  });

  test(
    'the app uploads a photo where the rules admit it, as image/jpeg',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final dir = Directory.systemTemp.createTempSync('storage_rules_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/ph1.jpg')..writeAsBytesSync([1, 2, 3]);
      final now = DateTime(2025);
      await db.photosDao.insertPhoto(
        PhotosCompanion(
          id: const Value('ph1'),
          pieceId: const Value('p1'),
          localPath: Value(file.path),
          dateTaken: Value(now),
          createdAt: Value(now),
        ),
      );
      final firestore = FakeFirebaseFirestore();
      await firestore.doc('users/u1/photos/ph1').set({'pieceId': 'p1'});
      final storage = MockFirebaseStorage();

      await SyncService(db, firestore, storage).uploadPhotoFile('u1', 'ph1');

      expect(storage.storedFilesMap.keys, ['users/u1/photos/p1/ph1.jpg']);
      expect(storage.storedFilesMap.keys.single, matches(photoPath));
      expect(
        storage.storedSettableMetadataMap.values.single['contentType'],
        'image/jpeg',
      );
      expect(
        SyncService.photoStoragePath('u1', 'p1', 'ph1'),
        matches(photoPath),
      );
    },
  );
}
