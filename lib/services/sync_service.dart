import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../database/database.dart';

class SyncService {
  final AppDatabase _db;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  SyncService(this._db, this._firestore, this._storage);

  DocumentReference _userDoc(String uid) => _firestore.doc('users/$uid');

  CollectionReference _col(String uid, String name) =>
      _userDoc(uid).collection(name);

  // ════════════════════════════════════════════
  // Push methods
  // ════════════════════════════════════════════

  Future<void> pushPiece(String uid, String pieceId) async {
    final piece = await _db.piecesDao.getPieceById(pieceId);
    if (piece == null) return;
    await _col(uid, 'pieces').doc(pieceId).set({
      'title': piece.title,
      'stage': piece.stage,
      'clayType': piece.clayType,
      'notes': piece.notes,
      'coverPhotoId': piece.coverPhotoId,
      'isArchived': piece.isArchived,
      'createdAt': Timestamp.fromDate(piece.createdAt),
      'updatedAt': Timestamp.fromDate(piece.updatedAt),
    }, SetOptions(merge: true));
  }

  Future<void> pushPhoto(String uid, String photoId) async {
    final photo = await _db.photosDao.getPhotoById(photoId);
    if (photo == null) return;
    await _col(uid, 'photos').doc(photoId).set({
      'pieceId': photo.pieceId,
      'cloudUrl': photo.cloudUrl,
      'dateTaken': Timestamp.fromDate(photo.dateTaken),
      'createdAt': Timestamp.fromDate(photo.createdAt),
      'sortOrder': photo.sortOrder,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> uploadPhotoFile(String uid, String photoId) async {
    final photo = await _db.photosDao.getPhotoById(photoId);
    if (photo == null) return;
    final file = File(photo.localPath);
    if (!file.existsSync()) return;

    final storagePath =
        'users/$uid/photos/${photo.pieceId}/$photoId.jpg';
    final ref = _storage.ref(storagePath);
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();

    // Update local DB with cloud URL
    await _db.photosDao.updatePhoto(PhotosCompanion(
      id: Value(photoId),
      cloudUrl: Value(url),
    ));

    // Update Firestore photo doc with URL
    await _col(uid, 'photos').doc(photoId).update({'cloudUrl': url});
  }

  Future<void> pushClay(String uid, String clayId) async {
    final clays = await _db.materialsDao.getAllClays();
    final clay = clays.where((c) => c.id == clayId).firstOrNull;
    if (clay == null) return;
    await _col(uid, 'clays').doc(clayId).set({
      'name': clay.name,
      'sortOrder': clay.sortOrder,
      'createdAt': Timestamp.fromDate(clay.createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> pushGlaze(String uid, String glazeId) async {
    final glazes = await _db.materialsDao.getAllGlazes();
    final glaze = glazes.where((g) => g.id == glazeId).firstOrNull;
    if (glaze == null) return;
    await _col(uid, 'glazes').doc(glazeId).set({
      'name': glaze.name,
      'sortOrder': glaze.sortOrder,
      'createdAt': Timestamp.fromDate(glaze.createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> pushTag(String uid, String tagId) async {
    final tags = await _db.materialsDao.getAllTags();
    final tag = tags.where((t) => t.id == tagId).firstOrNull;
    if (tag == null) return;
    await _col(uid, 'tags').doc(tagId).set({
      'name': tag.name,
      'color': tag.color,
      'sortOrder': tag.sortOrder,
      'createdAt': Timestamp.fromDate(tag.createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> pushPieceGlazes(String uid, String pieceId) async {
    final col = _col(uid, 'pieceGlazes');
    // Delete existing remote junction rows for this piece
    final existing =
        await col.where('pieceId', isEqualTo: pieceId).get();
    for (final doc in existing.docs) {
      await doc.reference.delete();
    }
    // Get current local junction data
    final glazes = await _db.materialsDao.getGlazesForPiece(pieceId);
    for (var i = 0; i < glazes.length; i++) {
      final id = const Uuid().v4();
      await col.doc(id).set({
        'pieceId': pieceId,
        'glazeOptionId': glazes[i].id,
        'sortOrder': i,
      });
    }
  }

  Future<void> pushPieceTags(String uid, String pieceId) async {
    final col = _col(uid, 'pieceTags');
    final existing =
        await col.where('pieceId', isEqualTo: pieceId).get();
    for (final doc in existing.docs) {
      await doc.reference.delete();
    }
    final tags = await _db.materialsDao.getTagsForPiece(pieceId);
    for (var i = 0; i < tags.length; i++) {
      final id = const Uuid().v4();
      await col.doc(id).set({
        'pieceId': pieceId,
        'tagOptionId': tags[i].id,
        'sortOrder': i,
      });
    }
  }

  Future<void> pushDeletion(
      String uid, String collection, String docId) async {
    await _col(uid, collection).doc(docId).set({
      'deletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> pushPieceDeletion(String uid, String pieceId) async {
    await pushDeletion(uid, 'pieces', pieceId);
    // Also mark photos and junctions as deleted
    final photoDocs = await _col(uid, 'photos')
        .where('pieceId', isEqualTo: pieceId)
        .get();
    for (final doc in photoDocs.docs) {
      await doc.reference.set({
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      // Delete photo file from storage
      try {
        final storagePath =
            'users/$uid/photos/$pieceId/${doc.id}.jpg';
        await _storage.ref(storagePath).delete();
      } catch (_) {}
    }
    // Delete junction rows
    final glazeDocs = await _col(uid, 'pieceGlazes')
        .where('pieceId', isEqualTo: pieceId)
        .get();
    for (final doc in glazeDocs.docs) {
      await doc.reference.delete();
    }
    final tagDocs = await _col(uid, 'pieceTags')
        .where('pieceId', isEqualTo: pieceId)
        .get();
    for (final doc in tagDocs.docs) {
      await doc.reference.delete();
    }
  }

  // ════════════════════════════════════════════
  // Push all local data (first sync)
  // ════════════════════════════════════════════

  Future<void> pushAllLocal(String uid) async {
    debugPrint('SyncService: pushing all local data');

    // Push all pieces
    final allPieces = await _db.select(_db.pieces).get();
    for (final piece in allPieces) {
      await pushPiece(uid, piece.id);
    }

    // Push all photos (metadata first, then attempt file uploads)
    final allPhotos = await _db.select(_db.photos).get();
    for (final photo in allPhotos) {
      await pushPhoto(uid, photo.id);
    }
    // File uploads are best-effort — Storage may not be available on Spark plan
    for (final photo in allPhotos) {
      if (photo.cloudUrl == null) {
        try {
          await uploadPhotoFile(uid, photo.id);
        } catch (e) {
          debugPrint('SyncService: photo upload skipped (${photo.id}): $e');
        }
      }
    }

    // Push all materials
    final clays = await _db.materialsDao.getAllClays();
    for (final clay in clays) {
      await pushClay(uid, clay.id);
    }
    final glazes = await _db.materialsDao.getAllGlazes();
    for (final glaze in glazes) {
      await pushGlaze(uid, glaze.id);
    }
    final tags = await _db.materialsDao.getAllTags();
    for (final tag in tags) {
      await pushTag(uid, tag.id);
    }

    // Push junction rows for each piece
    for (final piece in allPieces) {
      await pushPieceGlazes(uid, piece.id);
      await pushPieceTags(uid, piece.id);
    }
  }

  // ════════════════════════════════════════════
  // Pull methods
  // ════════════════════════════════════════════

  Future<void> pullAll(String uid) async {
    debugPrint('SyncService: full pull (first sync on this device)');

    await _pullCollection(
      uid: uid,
      collection: 'pieces',
      insert: (doc) => _insertPieceFromRemote(doc),
      update: (doc) => _updatePieceFromRemote(doc),
      existsLocally: (id) async =>
          await _db.piecesDao.getPieceById(id) != null,
      isRemoteNewer: (doc, id) async {
        final local = await _db.piecesDao.getPieceById(id);
        if (local == null) return true;
        final remoteUpdated =
            (doc['updatedAt'] as Timestamp).toDate();
        return remoteUpdated.isAfter(local.updatedAt);
      },
    );

    await _pullCollection(
      uid: uid,
      collection: 'photos',
      insert: (doc) => _insertPhotoFromRemote(doc),
      update: (doc) => _updatePhotoFromRemote(doc),
      existsLocally: (id) async =>
          await _db.photosDao.getPhotoById(id) != null,
      isRemoteNewer: (doc, id) async => true,
    );

    await _pullCollection(
      uid: uid,
      collection: 'clays',
      insert: (doc) => _insertClayFromRemote(doc),
      update: (doc) => _updateClayFromRemote(doc),
      existsLocally: (id) async {
        final all = await _db.materialsDao.getAllClays();
        return all.any((c) => c.id == id);
      },
      isRemoteNewer: (doc, id) async => true,
    );

    await _pullCollection(
      uid: uid,
      collection: 'glazes',
      insert: (doc) => _insertGlazeFromRemote(doc),
      update: (doc) => _updateGlazeFromRemote(doc),
      existsLocally: (id) async {
        final all = await _db.materialsDao.getAllGlazes();
        return all.any((g) => g.id == id);
      },
      isRemoteNewer: (doc, id) async => true,
    );

    await _pullCollection(
      uid: uid,
      collection: 'tags',
      insert: (doc) => _insertTagFromRemote(doc),
      update: (doc) => _updateTagFromRemote(doc),
      existsLocally: (id) async {
        final all = await _db.materialsDao.getAllTags();
        return all.any((t) => t.id == id);
      },
      isRemoteNewer: (doc, id) async => true,
    );

    // Pull junction tables
    await _pullJunctions(uid, 'pieceGlazes', _mergeRemotePieceGlazes);
    await _pullJunctions(uid, 'pieceTags', _mergeRemotePieceTags);

    // Download missing photo files
    await _downloadMissingPhotos(uid);

    // Update lastPulledAt
    await _userDoc(uid)
        .collection('meta')
        .doc('syncInfo')
        .set({'lastPulledAt': FieldValue.serverTimestamp()});
  }

  Future<void> pullChangedSince(String uid, DateTime since) async {
    debugPrint('SyncService: incremental pull since $since');
    final sinceTs = Timestamp.fromDate(since);

    for (final collection in ['pieces', 'photos', 'clays', 'glazes', 'tags']) {
      final snap = await _col(uid, collection)
          .where('updatedAt', isGreaterThan: sinceTs)
          .get();

      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        if (data['deletedAt'] != null) {
          await _handleRemoteDeletion(collection, doc.id);
          continue;
        }

        await _mergeRemoteDoc(collection, doc);
      }
    }

    // Pull junction tables (always full — they're small and have no updatedAt)
    await _pullJunctions(uid, 'pieceGlazes', _mergeRemotePieceGlazes);
    await _pullJunctions(uid, 'pieceTags', _mergeRemotePieceTags);

    await _downloadMissingPhotos(uid);

    await _userDoc(uid)
        .collection('meta')
        .doc('syncInfo')
        .set({'lastPulledAt': FieldValue.serverTimestamp()});
  }

  Future<DateTime?> getLastPulledAt(String uid) async {
    final doc =
        await _userDoc(uid).collection('meta').doc('syncInfo').get();
    if (!doc.exists) return null;
    final ts = doc.data()?['lastPulledAt'] as Timestamp?;
    return ts?.toDate();
  }

  // ════════════════════════════════════════════
  // Generic pull helpers
  // ════════════════════════════════════════════

  Future<void> _pullCollection({
    required String uid,
    required String collection,
    required Future<void> Function(QueryDocumentSnapshot) insert,
    required Future<void> Function(QueryDocumentSnapshot) update,
    required Future<bool> Function(String id) existsLocally,
    required Future<bool> Function(
            QueryDocumentSnapshot doc, String id)
        isRemoteNewer,
  }) async {
    final snap = await _col(uid, collection).get();
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      if (data['deletedAt'] != null) {
        await _handleRemoteDeletion(collection, doc.id);
        continue;
      }
      if (await existsLocally(doc.id)) {
        if (await isRemoteNewer(doc, doc.id)) {
          await update(doc);
        }
      } else {
        await insert(doc);
      }
    }
  }

  Future<void> _pullJunctions(
    String uid,
    String collection,
    Future<void> Function(String pieceId, List<QueryDocumentSnapshot> docs)
        mergeFn,
  ) async {
    final snap = await _col(uid, collection).get();
    final byPiece = <String, List<QueryDocumentSnapshot>>{};
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      final pieceId = data?['pieceId'] as String?;
      if (pieceId == null) continue;
      byPiece.putIfAbsent(pieceId, () => []).add(doc);
    }
    for (final entry in byPiece.entries) {
      await mergeFn(entry.key, entry.value);
    }
  }

  // ════════════════════════════════════════════
  // Remote merge
  // ════════════════════════════════════════════

  Future<void> _mergeRemoteDoc(
      String collection, QueryDocumentSnapshot doc) async {
    switch (collection) {
      case 'pieces':
        final exists = await _db.piecesDao.getPieceById(doc.id) != null;
        if (exists) {
          await _updatePieceFromRemote(doc);
        } else {
          await _insertPieceFromRemote(doc);
        }
      case 'photos':
        final exists = await _db.photosDao.getPhotoById(doc.id) != null;
        if (exists) {
          await _updatePhotoFromRemote(doc);
        } else {
          await _insertPhotoFromRemote(doc);
        }
      case 'clays':
        await _insertClayFromRemote(doc);
      case 'glazes':
        await _insertGlazeFromRemote(doc);
      case 'tags':
        await _insertTagFromRemote(doc);
    }
  }

  Future<void> _handleRemoteDeletion(
      String collection, String docId) async {
    switch (collection) {
      case 'pieces':
        await _db.photosDao.deletePhotosForPiece(docId);
        await _db.piecesDao.deletePiece(docId);
      case 'photos':
        await _db.photosDao.deletePhoto(docId);
      case 'clays':
        await _db.materialsDao.deleteClay(docId);
      case 'glazes':
        await _db.materialsDao.deleteGlaze(docId);
      case 'tags':
        await _db.materialsDao.deleteTag(docId);
    }
  }

  // ════════════════════════════════════════════
  // Entity insert/update from remote
  // ════════════════════════════════════════════

  Future<void> _insertPieceFromRemote(QueryDocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    await _db.piecesDao.insertPiece(PiecesCompanion(
      id: Value(doc.id),
      title: Value(d['title'] as String?),
      stage: Value(d['stage'] as String?),
      clayType: Value(d['clayType'] as String?),
      notes: Value(d['notes'] as String?),
      coverPhotoId: Value(d['coverPhotoId'] as String?),
      isArchived: Value(d['isArchived'] as bool? ?? false),
      createdAt: Value((d['createdAt'] as Timestamp).toDate()),
      updatedAt: Value((d['updatedAt'] as Timestamp).toDate()),
    ));
  }

  Future<void> _updatePieceFromRemote(QueryDocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    await _db.piecesDao.updatePiece(PiecesCompanion(
      id: Value(doc.id),
      title: Value(d['title'] as String?),
      stage: Value(d['stage'] as String?),
      clayType: Value(d['clayType'] as String?),
      notes: Value(d['notes'] as String?),
      coverPhotoId: Value(d['coverPhotoId'] as String?),
      isArchived: Value(d['isArchived'] as bool? ?? false),
      updatedAt: Value((d['updatedAt'] as Timestamp).toDate()),
    ));
  }

  Future<void> _insertPhotoFromRemote(QueryDocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    final cloudUrl = d['cloudUrl'] as String?;
    // Use a placeholder path — actual file will be downloaded later
    final appDir = await getApplicationDocumentsDirectory();
    final pieceId = d['pieceId'] as String;
    final localPath =
        '${appDir.path}/photos/$pieceId/${doc.id}.jpg';

    await _db.photosDao.insertPhoto(PhotosCompanion(
      id: Value(doc.id),
      pieceId: Value(pieceId),
      localPath: Value(localPath),
      cloudUrl: Value(cloudUrl),
      dateTaken: Value((d['dateTaken'] as Timestamp).toDate()),
      createdAt: Value((d['createdAt'] as Timestamp).toDate()),
      sortOrder: Value(d['sortOrder'] as int? ?? 0),
    ));
  }

  Future<void> _updatePhotoFromRemote(QueryDocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    await _db.photosDao.updatePhoto(PhotosCompanion(
      id: Value(doc.id),
      cloudUrl: Value(d['cloudUrl'] as String?),
      sortOrder: Value(d['sortOrder'] as int? ?? 0),
    ));
  }

  Future<void> _insertClayFromRemote(QueryDocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    try {
      await _db.into(_db.clayOptions).insert(
        ClayOptionsCompanion.insert(
          id: doc.id,
          name: d['name'] as String,
          sortOrder: Value(d['sortOrder'] as int? ?? 0),
          createdAt: (d['createdAt'] as Timestamp).toDate(),
        ),
        mode: InsertMode.insertOrReplace,
      );
    } catch (e) {
      debugPrint('SyncService: clay insert failed: $e');
    }
  }

  Future<void> _updateClayFromRemote(QueryDocumentSnapshot doc) async {
    await _insertClayFromRemote(doc);
  }

  Future<void> _insertGlazeFromRemote(QueryDocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    try {
      await _db.into(_db.glazeOptions).insert(
        GlazeOptionsCompanion.insert(
          id: doc.id,
          name: d['name'] as String,
          sortOrder: Value(d['sortOrder'] as int? ?? 0),
          createdAt: (d['createdAt'] as Timestamp).toDate(),
        ),
        mode: InsertMode.insertOrReplace,
      );
    } catch (e) {
      debugPrint('SyncService: glaze insert failed: $e');
    }
  }

  Future<void> _updateGlazeFromRemote(QueryDocumentSnapshot doc) async {
    await _insertGlazeFromRemote(doc);
  }

  Future<void> _insertTagFromRemote(QueryDocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    try {
      await _db.into(_db.tagOptions).insert(
        TagOptionsCompanion.insert(
          id: doc.id,
          name: d['name'] as String,
          color: Value(d['color'] as String?),
          sortOrder: Value(d['sortOrder'] as int? ?? 0),
          createdAt: (d['createdAt'] as Timestamp).toDate(),
        ),
        mode: InsertMode.insertOrReplace,
      );
    } catch (e) {
      debugPrint('SyncService: tag insert failed: $e');
    }
  }

  Future<void> _updateTagFromRemote(QueryDocumentSnapshot doc) async {
    await _insertTagFromRemote(doc);
  }

  // ════════════════════════════════════════════
  // Junction merge
  // ════════════════════════════════════════════

  Future<void> _mergeRemotePieceGlazes(
      String pieceId, List<QueryDocumentSnapshot> docs) async {
    final glazeIds = <String>[];
    // Sort by sortOrder
    docs.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>;
      final bData = b.data() as Map<String, dynamic>;
      return (aData['sortOrder'] as int? ?? 0)
          .compareTo(bData['sortOrder'] as int? ?? 0);
    });
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final glazeId = data['glazeOptionId'] as String?;
      if (glazeId != null) glazeIds.add(glazeId);
    }
    if (glazeIds.isNotEmpty) {
      await _db.materialsDao.setGlazesForPiece(pieceId, glazeIds);
    }
  }

  Future<void> _mergeRemotePieceTags(
      String pieceId, List<QueryDocumentSnapshot> docs) async {
    final tagIds = <String>[];
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final tagId = data['tagOptionId'] as String?;
      if (tagId != null) tagIds.add(tagId);
    }
    if (tagIds.isNotEmpty) {
      await _db.materialsDao.setTagsForPiece(pieceId, tagIds);
    }
  }

  // ════════════════════════════════════════════
  // Photo download
  // ════════════════════════════════════════════

  Future<void> _downloadMissingPhotos(String uid) async {
    final allPhotos = await _db.select(_db.photos).get();
    final missing = allPhotos
        .where((p) =>
            p.cloudUrl != null && !File(p.localPath).existsSync())
        .toList();

    debugPrint('SyncService: ${missing.length} photos to download');

    // Download in batches of 5
    for (var i = 0; i < missing.length; i += 5) {
      final batch =
          missing.sublist(i, i + 5 > missing.length ? missing.length : i + 5);
      await Future.wait(
          batch.map((photo) => _downloadPhoto(photo)));
    }
  }

  Future<void> _downloadPhoto(Photo photo) async {
    try {
      final file = File(photo.localPath);
      await file.parent.create(recursive: true);

      // Download from cloud URL
      final ref = _storage.refFromURL(photo.cloudUrl!);
      final data = await ref.getData();
      if (data == null) return;

      await file.writeAsBytes(data);

      // Regenerate thumbnail
      final thumbnailPath =
          photo.localPath.replaceAll('.jpg', '_thumb.jpg');
      final thumbBytes = await FlutterImageCompress.compressWithList(
        data,
        minWidth: 300,
        minHeight: 300,
        quality: 60,
      );
      await File(thumbnailPath).writeAsBytes(thumbBytes);

      await _db.photosDao.updatePhoto(PhotosCompanion(
        id: Value(photo.id),
        thumbnailPath: Value(thumbnailPath),
      ));
    } catch (e) {
      debugPrint('SyncService: download failed for ${photo.id}: $e');
    }
  }
}
