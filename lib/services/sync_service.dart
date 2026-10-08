import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database.dart';
import '../database/transfer_key_backup.dart';
import 'encryption_key_service.dart';
import 'sync_queue.dart';
import 'sync_trigger.dart';

/// Raised by [SyncService.deleteLocalData] when everything but the photo
/// files was destroyed.
///
/// Its own type rather than a [StateError], because the caller has to tell
/// this outcome apart from a wipe that deleted nothing: the rows, the queue,
/// the watermarks and the ownership stamp are all gone, the photographs are
/// not, and the erase stays owed. Matching on a message would break the first
/// time the wording changed or another error arrived from the same call.
class LocalPhotoWipeException implements Exception {
  /// What stopped the photos directory from being removed.
  final Object cause;

  LocalPhotoWipeException(this.cause);

  @override
  String toString() =>
      'LocalPhotoWipeException: local photo files were not deleted: $cause';
}

/// Raised by [SyncService.deleteLocalData] when every local store was
/// destroyed but the device was not left secured against the user leaving it.
///
/// Its own type for the same reason as [LocalPhotoWipeException]: the caller
/// must not report this as "nothing was deleted". Everything the confirmation
/// promised to delete is gone — the rows, the photographs, the queue, the
/// watermarks and the ownership stamp. What did not happen is one of the two
/// steps that stop the leaving user reaching what the next person makes here:
/// replacing the database key, or deleting the transfer backup that wraps it.
/// One outcome rather than two because they are the same thing to the reader
/// and want the same thing from them — the erase stays owed, and its retry
/// does both again.
///
/// The transfer backup is reported even when the rotation worked and the key
/// the surviving copy wraps opens nothing here: that file is what Settings
/// reads to decide a passphrase is set, and nothing else on the device ever
/// removes it, so leaving it would tell the next person they have a
/// passphrase they never chose. [causes] carries every step that failed, so a
/// report never drops one in favour of another.
class LocalDeviceNotSecuredException implements Exception {
  /// What stopped the device from being secured, in the order it happened.
  final List<Object> causes;

  LocalDeviceNotSecuredException(this.causes);

  @override
  String toString() =>
      'LocalDeviceNotSecuredException: local data was erased but the device '
      'was not secured for its next user: ${causes.join('; ')}';
}

class SyncService {
  final AppDatabase _db;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final EncryptionKeyService _keys;

  /// The queue a pull consults before writing over a local row. The app must
  /// pass the instance its `SyncTrigger` enqueues into, because an edit made
  /// during a pull is visible to this check through that instance's in-memory
  /// revisions before the persisted queue catches up.
  final SyncQueue _queue;

  /// Where a pull queues a push it finds this device owes the cloud, so the
  /// app schedules a drain for it. The app passes the trigger its writers
  /// use, which enqueues into [_queue].
  final SyncTrigger _trigger;

  SyncService(
    AppDatabase db,
    FirebaseFirestore firestore,
    FirebaseStorage storage, {
    EncryptionKeyService? keys,
    SyncQueue? queue,
    SyncTrigger? trigger,
  }) : this._(
         db,
         firestore,
         storage,
         keys ?? EncryptionKeyService(),
         queue ?? SyncQueue(),
         trigger,
       );

  SyncService._(
    this._db,
    this._firestore,
    this._storage,
    this._keys,
    this._queue,
    SyncTrigger? trigger,
  ) : _trigger = trigger ?? SyncTrigger(_queue);

  DocumentReference _userDoc(String uid) => _firestore.doc('users/$uid');

  CollectionReference _col(String uid, String name) =>
      _userDoc(uid).collection(name);

  /// Prefix of the per-uid "last successful pull" watermarks written by
  /// [_saveLastPulledAt]. Shared with [deleteLocalData], which has to clear
  /// every one of them, and with the database bootstrap, which clears them
  /// when it discards a restored database before any `SyncService` exists.
  static const lastPulledAtPrefix = 'lastPulledAt_';

  /// The uid whose data this device's local database holds.
  ///
  /// Stamped by the first account allowed to sync here and cleared by
  /// [deleteLocalData]. It is what makes an *involuntary* loss of session
  /// (a revoked token, or just an offline launch — see
  /// `AuthNotifier._init`) safe: that path deliberately does not wipe, so the
  /// stamp is the only thing left that knows whose pieces these are, and
  /// `SyncNotifier` refuses to push for anyone else until the owner signs
  /// back in.
  /// Public so startup can seed the read-only lock from it before `runApp`
  /// without restating the literal.
  static const localDataOwnerKey = 'localDataOwnerUid';

  /// Set once this device has refused an account, and cleared only when the
  /// owner named by [localDataOwnerKey] claims it back or the device is
  /// erased.
  ///
  /// It exists because a session-less launch is ambiguous on its own: the
  /// owner opening the app offline and a refused account relaunching after
  /// force-quitting the lock screen both arrive with no uid at all, and
  /// ruling 2 requires the first to keep working. The stamp cannot tell them
  /// apart; this can.
  ///
  /// One flag about the *device*, deliberately not per-row attribution: it
  /// records that somebody was refused here, never which rows anybody touched.
  /// Public for the same reason as [localDataOwnerKey] — startup seeds the
  /// lock from it before `runApp`.
  static const deviceContestedKey = 'localDataContested';

  /// The uid of an account a confirmed deletion removed the cloud tree for
  /// but could not remove itself — almost always because Firebase wants a
  /// recent sign-in first.
  ///
  /// The user is told at the time, but that message is a passing one and two
  /// of the three partial outcomes redirect away from the screen that showed
  /// it. This is what makes the fact survive: a half-finished deletion the
  /// user confirmed has to still be discoverable a minute later, on whichever
  /// screen they end up on — including after the erase those screens tell
  /// them to do first.
  ///
  /// So [deleteLocalData] deliberately leaves it alone: this is about a cloud
  /// account, whose existence has nothing to do with whether local data is
  /// present, and erasing a device deletes no account. It stores the uid
  /// rather than a flag for the same reason — the next account to sign in
  /// here must not be told that *their* account survived a deletion they
  /// never asked for. Cleared when that account is finally deleted.
  static const accountDeletionOwedKey = 'accountDeletionOwed';

  // ════════════════════════════════════════════
  // Delete all data
  // ════════════════════════════════════════════

  Future<void> deleteCloudData(String uid) async {
    debugPrint('SyncService: deleting cloud data for user $uid');

    // Delete all Firestore subcollections
    for (final collection in [
      'pieces',
      'photos',
      'clays',
      'glazes',
      'tags',
      'pieceGlazes',
      'pieceTags',
      'meta',
    ]) {
      final snap = await _col(uid, collection).get();
      for (final doc in snap.docs) {
        await doc.reference.delete();
      }
      debugPrint(
        'SyncService: deleted ${snap.docs.length} docs from $collection',
      );
    }

    // Delete all Cloud Storage files. A failure propagates: the caller must
    // not delete the account, or report the data deleted, while photos are
    // still in the bucket. Every step is safe to repeat on a retry.
    await _deleteStorageTree(_storage.ref('users/$uid'));
    debugPrint('SyncService: deleted all Cloud Storage files');
  }

  Future<void> _deleteStorageTree(Reference ref) async {
    final listing = await ref.listAll();
    for (final item in listing.items) {
      await _deleteStorageObject(item);
    }
    for (final prefix in listing.prefixes) {
      await _deleteStorageTree(prefix);
    }
  }

  /// Deletes one Storage object. One that is already gone counts as deleted,
  /// so a retry converges; any other failure propagates, keeping the queue
  /// entry that asked for the deletion pending.
  Future<void> _deleteStorageObject(Reference ref) async {
    try {
      await ref.delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }

  /// Where a photo's file lives in Cloud Storage. `storage.rules` accepts
  /// uploads at this shape only.
  static String photoStoragePath(String uid, String pieceId, String photoId) =>
      'users/$uid/photos/$pieceId/$photoId.jpg';

  /// Destroys this device's entire local copy of the account's data.
  ///
  /// Every local store the app owns must be listed here. Whatever survives is
  /// what [fullUploadEntries] stages into the *next* account's cloud tree on
  /// its first sync, so an omission here is a cross-account data leak, not a
  /// cosmetic bug. That is also why this runs on sign-out — see
  /// `SyncNotifier.signOutAndWipeLocalData`.
  ///
  /// The SQLCipher key is rotated here too — see [_rotateDatabaseKey] — so
  /// the leaving user's transfer passphrase, whose backup file a phone backup
  /// may have kept, unwraps nothing the next person on this device makes.
  Future<void> deleteLocalData() async {
    debugPrint('SyncService: deleting all local data');

    await _db.transaction(() async {
      await _db.delete(_db.pieceTags).go();
      await _db.delete(_db.pieceGlazes).go();
      await _db.delete(_db.deletedJunctions).go();
      await _db.delete(_db.photos).go();
      await _db.delete(_db.pieces).go();
      await _db.delete(_db.clayOptions).go();
      await _db.delete(_db.glazeOptions).go();
      await _db.delete(_db.tagOptions).go();
    });

    // Hand the freed pages back to the filesystem rather than leaving deleted
    // rows sitting in the database file's free list.
    try {
      await _db.customStatement('VACUUM');
    } catch (e) {
      debugPrint('SyncService: VACUUM after wipe failed: $e');
    }

    final rotationFailure = await _rotateDatabaseKey();

    final photoFailure = await _deleteLocalPhotoFiles();
    await _clearSyncWatermarks();
    final transferFailure = await _deleteTransferKeyBackup();

    // The data is gone, so nobody owns this device any more: the next account
    // to sign in starts from a clean slate rather than inheriting the claim,
    // and there is nothing left here for anyone to be refused over.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(localDataOwnerKey);
    await prefs.remove(deviceContestedKey);

    // Raised last, so everything that could be cleared has been: the wipe is
    // best-effort, the *reporting* is not. The confirmation the user answered
    // promises every photo on this device is deleted, and an erase that left
    // them on disk must not come back as done — the wipe stays owed, and the
    // lock screen keeps offering the retry that finishes it.
    if (photoFailure != null) {
      throw LocalPhotoWipeException(photoFailure);
    }
    final notSecured = [?rotationFailure, ?transferFailure];
    if (notSecured.isNotEmpty) {
      throw LocalDeviceNotSecuredException(notSecured);
    }
  }

  /// Deletes the transfer backup, returning what stopped it or null.
  ///
  /// The transfer passphrase was the leaving user's: the next person on this
  /// device must not inherit a backup that a passphrase they do not know can
  /// open. Returned rather than thrown for the same reason as the rotation —
  /// the ownership stamp this device is refused over is cleared after it, and
  /// a stamp left standing on an emptied device refuses the next account for
  /// nothing.
  Future<Object?> _deleteTransferKeyBackup() async {
    try {
      await TransferKeyBackup.deleteIn(
        await getApplicationDocumentsDirectory(),
      );
      return null;
    } catch (e) {
      debugPrint('SyncService: the transfer backup was not deleted: $e');
      return e;
    }
  }

  /// Re-encrypts the emptied database under a fresh key and stores it.
  ///
  /// The database is rekeyed first and the new key stored second. If storing
  /// fails, the file is keyed back and the old key stored again. A process
  /// that dies in between leaves the file at the new key: once the store's
  /// migrating copy has landed, the next launch finds the stored key does
  /// not open the file, probes the copy and finishes the store
  /// (`LocalDatabaseBootstrap`); before that instant it is a key mismatch
  /// over an empty database, where starting fresh costs nothing.
  ///
  /// Every way this can end with the old key still on the file — a key store
  /// that cannot be read, a rekey that sqlite3 refuses, a key-back after a
  /// store that failed, whether that key-back succeeded or not — leaves the
  /// same state and is returned the same way, so none of them can be the one
  /// that passes for a rotation that happened. A key-back that works is the
  /// likeliest of them: it is the designed fallback, not a refusal.
  /// Returned rather than thrown because the photographs the user was
  /// promised must be deleted first, so [deleteLocalData] raises what comes
  /// back here as a [LocalDeviceNotSecuredException] once the rest of the
  /// wipe has run. The erase stays owed, and its retry rotates again. No
  /// error from here quotes a key (`AppDatabase.rekey`).
  Future<Object?> _rotateDatabaseKey() async {
    final String? oldKey;
    try {
      oldKey = await _keys.readKey();
    } catch (e) {
      debugPrint('SyncService: database key rotation could not read a key: $e');
      return e;
    }
    if (oldKey == null) return null;
    final newKey = EncryptionKeyService.generateKey();
    try {
      await _db.rekey(newKey);
    } catch (e) {
      debugPrint('SyncService: the database was not rekeyed: $e');
      return e;
    }
    try {
      await _keys.storeKey(newKey);
    } catch (e) {
      debugPrint(
        'SyncService: rotated key not stored, keying the database back: $e',
      );
      try {
        await _db.rekey(oldKey);
        await _keys.storeKey(oldKey);
      } catch (keyBack) {
        return keyBack;
      }
      return e;
    }
    return null;
  }

  /// Deletes the photo files, returning what stopped it or null if nothing did.
  ///
  /// The two directories are not equivalent. The photos directory holds the
  /// user's pottery photographs, which the erase promised to destroy, so a
  /// failure there is returned and becomes the caller's problem. The temp
  /// directory holds `image_picker`'s copies — worth clearing, but a cache
  /// entry the platform will not release is not the erase failing.
  Future<Object?> _deleteLocalPhotoFiles() async {
    Object? photoFailure;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final photosDir = Directory('${appDir.path}/photos');
      if (photosDir.existsSync()) {
        photosDir.deleteSync(recursive: true);
        debugPrint('SyncService: deleted local photo files');
      }
    } catch (e) {
      debugPrint('SyncService: local file cleanup error: $e');
      photoFailure = e;
    }

    // image_picker copies every picked photo into the platform temp directory
    // and those copies outlive the pick, so they are user photos too.
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        for (final entity in tempDir.listSync()) {
          try {
            entity.deleteSync(recursive: true);
          } catch (_) {
            // A single undeletable cache entry must not abort the wipe.
          }
        }
        debugPrint('SyncService: cleared cached image files');
      }
    } catch (e) {
      debugPrint('SyncService: temp file cleanup error: $e');
    }

    return photoFailure;
  }

  /// The uid this device's local data belongs to, or null when it belongs to
  /// nobody yet — a fresh install, a local-only user who has never signed in,
  /// or a device that has just been wiped.
  Future<String?> getLocalDataOwner() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(localDataOwnerKey);
  }

  /// Claims this device's local data for [uid]. Only ever called for an
  /// account that is allowed to sync here, so it never overwrites another
  /// account's claim.
  Future<void> setLocalDataOwner(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(localDataOwnerKey, uid);
  }

  /// Whether this device has been refused for an account and not reclaimed.
  Future<bool> getDeviceContested() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(deviceContestedKey) ?? false;
  }

  /// Clears every per-uid pull watermark.
  ///
  /// Leaving one behind is not just untidy: the same account signing back in
  /// would take the *incremental* pull branch and never re-download the pieces
  /// this wipe just deleted.
  Future<void> _clearSyncWatermarks() async {
    final prefs = await SharedPreferences.getInstance();
    final stale = prefs
        .getKeys()
        .where((k) => k.startsWith(lastPulledAtPrefix))
        .toList();
    for (final key in stale) {
      await prefs.remove(key);
    }
  }

  // ════════════════════════════════════════════
  // Push methods
  // ════════════════════════════════════════════

  /// Performs an authenticated server-only read before a push run starts.
  ///
  /// Unlike a write, a server-only read reports `unavailable` while Firestore
  /// knows it is offline instead of remaining pending until reconnection. The
  /// document does not need to exist: an authoritative missing result proves
  /// the same reachability as an existing one.
  Future<void> checkServerReachability(String uid) async {
    await _col(
      uid,
      'meta',
    ).doc('sync-reachability').get(const GetOptions(source: Source.server));
  }

  /// Pushes the whole row, or only [fields] of it when its queue entry names
  /// them. A field-scoped push updates just those fields, so a device that
  /// has not pulled another device's edit to the rest of the piece cannot
  /// write its older copy over it. A piece the cloud does not hold yet has no
  /// fields to keep, and is uploaded whole.
  Future<void> pushPiece(
    String uid,
    String pieceId, {
    List<String>? fields,
  }) async {
    final piece = await _db.piecesDao.getPieceById(pieceId);
    if (piece == null) return;
    final doc = _col(uid, 'pieces').doc(pieceId);
    final data = {
      'title': piece.title,
      'stage': piece.stage,
      'clayType': piece.clayType,
      'notes': piece.notes,
      'coverPhotoId': piece.coverPhotoId,
      'isArchived': piece.isArchived,
      'displayDate': piece.displayDate != null
          ? Timestamp.fromDate(piece.displayDate!)
          : null,
      'createdAt': Timestamp.fromDate(piece.createdAt),
      // Server time, like every other collection, never this device's edit
      // time: incremental pulls select on it, and an edit made offline and
      // pushed later would otherwise carry a time older than the watermarks
      // other devices have already passed.
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _write(doc, data, fields);
  }

  /// Writes [data] whole, or only [fields] of it with its `updatedAt`. A doc
  /// the cloud does not hold yet has no fields to keep, and is written whole.
  static Future<void> _write(
    DocumentReference doc,
    Map<String, Object?> data,
    List<String>? fields,
  ) async {
    if (fields != null) {
      try {
        await doc.update({
          for (final field in fields) field: data[field],
          'updatedAt': data['updatedAt'],
        });
        return;
      } on FirebaseException catch (e) {
        if (e.code != 'not-found') rethrow;
      }
    }
    await doc.set(data, SetOptions(merge: true));
  }

  Future<void> pushPhoto(String uid, String photoId) async {
    final photo = await _db.photosDao.getPhotoById(photoId);
    if (photo == null) return;
    await _col(uid, 'photos').doc(photoId).set({
      'pieceId': photo.pieceId,
      // Only [uploadPhotoFile] publishes a URL, and once published it is final.
      // A device that has not learned it yet must not write its null over it.
      if (photo.cloudUrl != null) 'cloudUrl': photo.cloudUrl,
      'dateTaken': Timestamp.fromDate(photo.dateTaken),
      'createdAt': Timestamp.fromDate(photo.createdAt),
      'sortOrder': photo.sortOrder,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Uploads the photo's file unless its row already records where it is. A
  /// photo's file never changes once taken, so that URL is final. A photo
  /// deleted while its file was uploading gets that file deleted again, since
  /// its piece's deletion may already have looked for it, and no URL.
  Future<void> uploadPhotoFile(String uid, String photoId) async {
    final photo = await _db.photosDao.getPhotoById(photoId);
    if (photo == null || photo.cloudUrl != null) return;
    final file = File(photo.localPath);
    if (!file.existsSync()) return;

    final ref = _storage.ref(photoStoragePath(uid, photo.pieceId, photoId));
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    if (await _db.photosDao.getPhotoById(photoId) == null) {
      try {
        await ref.delete();
      } catch (_) {}
      return;
    }
    final url = await ref.getDownloadURL();

    // A file is backed up only once its remote metadata can locate it.
    // Keep the local row pending if publishing the URL fails.
    // updatedAt moves with it, so devices that already pulled this photo
    // without a URL select it again on their next incremental pull.
    await _col(uid, 'photos').doc(photoId).update({
      'cloudUrl': url,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _db.photosDao.updatePhoto(
      PhotosCompanion(id: Value(photoId), cloudUrl: Value(url)),
    );
  }

  /// Pushes the whole row, or only [fields] of it, as [pushPiece] does: a
  /// reorder sends just `sortOrder`, so a device that has not pulled another
  /// device's rename cannot write its older name over it.
  Future<void> pushClay(
    String uid,
    String clayId, {
    List<String>? fields,
  }) async {
    final clays = await _db.materialsDao.getAllClays();
    final clay = clays.where((c) => c.id == clayId).firstOrNull;
    if (clay == null) return;
    await _write(_col(uid, 'clays').doc(clayId), {
      'name': clay.name,
      'sortOrder': clay.sortOrder,
      'createdAt': Timestamp.fromDate(clay.createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    }, fields);
  }

  /// [pushClay] for glazes.
  Future<void> pushGlaze(
    String uid,
    String glazeId, {
    List<String>? fields,
  }) async {
    final glazes = await _db.materialsDao.getAllGlazes();
    final glaze = glazes.where((g) => g.id == glazeId).firstOrNull;
    if (glaze == null) return;
    await _write(_col(uid, 'glazes').doc(glazeId), {
      'name': glaze.name,
      'sortOrder': glaze.sortOrder,
      'createdAt': Timestamp.fromDate(glaze.createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    }, fields);
  }

  /// [pushClay] for tags, whose colour a reorder does not send either.
  Future<void> pushTag(String uid, String tagId, {List<String>? fields}) async {
    final tags = await _db.materialsDao.getAllTags();
    final tag = tags.where((t) => t.id == tagId).firstOrNull;
    if (tag == null) return;
    await _write(_col(uid, 'tags').doc(tagId), {
      'name': tag.name,
      'color': tag.color,
      'sortOrder': tag.sortOrder,
      'createdAt': Timestamp.fromDate(tag.createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    }, fields);
  }

  Future<void> pushPieceGlazes(String uid, String pieceId) async {
    final col = _col(uid, 'pieceGlazes');
    final existing = await col
        .where('pieceId', isEqualTo: pieceId)
        .get(const GetOptions(source: Source.server));
    final glazes = await _db.materialsDao.getGlazesForPiece(pieceId);
    final desired = <String, Map<String, Object>>{};
    for (var i = 0; i < glazes.length; i++) {
      final id = _junctionDocumentId(pieceId, glazes[i].id);
      desired[id] = {
        'pieceId': pieceId,
        'glazeOptionId': glazes[i].id,
        'sortOrder': i,
      };
    }
    final batch = _firestore.batch();
    for (final doc in existing.docs) {
      if (!desired.containsKey(doc.id)) batch.delete(doc.reference);
    }
    for (final entry in desired.entries) {
      batch.set(col.doc(entry.key), entry.value);
    }
    await batch.commit();
  }

  Future<void> pushPieceTags(String uid, String pieceId) async {
    final col = _col(uid, 'pieceTags');
    final existing = await col
        .where('pieceId', isEqualTo: pieceId)
        .get(const GetOptions(source: Source.server));
    final tags = await _db.materialsDao.getTagsForPiece(pieceId);
    final desired = <String, Map<String, Object>>{};
    for (var i = 0; i < tags.length; i++) {
      final id = _junctionDocumentId(pieceId, tags[i].id);
      desired[id] = {
        'pieceId': pieceId,
        'tagOptionId': tags[i].id,
        'sortOrder': i,
      };
    }
    final batch = _firestore.batch();
    for (final doc in existing.docs) {
      if (!desired.containsKey(doc.id)) batch.delete(doc.reference);
    }
    for (final entry in desired.entries) {
      batch.set(col.doc(entry.key), entry.value);
    }
    await batch.commit();
  }

  /// Stable across retries and app versions. Existing UUID-named junction
  /// documents are deleted by the same atomic batch that installs these, so
  /// old and new clients can alternate without a one-time data migration.
  String _junctionDocumentId(String pieceId, String optionId) =>
      sha256.convert(utf8.encode('$pieceId\u0000$optionId')).toString();

  Future<void> pushDeletion(String uid, String collection, String docId) async {
    await _col(uid, collection).doc(docId).set({
      'deletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Deletes a photo's cloud copy: its metadata, as a tombstone, and its
  /// Storage object. [pieceId] names the object; an entry queued before
  /// deletions recorded it falls back to the piece the metadata names. With
  /// neither, nothing names an object to delete.
  Future<void> pushPhotoDeletion(
    String uid,
    String photoId, {
    String? pieceId,
  }) async {
    final doc = _col(uid, 'photos').doc(photoId);
    pieceId ??=
        ((await doc.get()).data() as Map<String, dynamic>?)?['pieceId']
            as String?;
    await pushDeletion(uid, 'photos', photoId);
    if (pieceId != null) {
      await _deleteStorageObject(
        _storage.ref(photoStoragePath(uid, pieceId, photoId)),
      );
    }
  }

  Future<void> pushPieceDeletion(String uid, String pieceId) async {
    await pushDeletion(uid, 'pieces', pieceId);
    // Also mark photos and junctions as deleted
    final photoDocs = await _col(
      uid,
      'photos',
    ).where('pieceId', isEqualTo: pieceId).get();
    for (final doc in photoDocs.docs) {
      await doc.reference.set({
        'deletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _deleteStorageObject(
        _storage.ref(photoStoragePath(uid, pieceId, doc.id)),
      );
    }
    // Delete junction rows
    final glazeDocs = await _col(
      uid,
      'pieceGlazes',
    ).where('pieceId', isEqualTo: pieceId).get();
    for (final doc in glazeDocs.docs) {
      await doc.reference.delete();
    }
    final tagDocs = await _col(
      uid,
      'pieceTags',
    ).where('pieceId', isEqualTo: pieceId).get();
    for (final doc in tagDocs.docs) {
      await doc.reference.delete();
    }
  }

  // ════════════════════════════════════════════
  // Full local snapshot (first and forced sync)
  // ════════════════════════════════════════════

  /// Describes a full local snapshot using the same durable operations as the
  /// incremental queue. [SyncNotifier] enqueues these, less what its full pull
  /// found in the cloud ([pullAll]), before dispatching them, so first sync,
  /// forced sync and normal drains share acknowledgement, revision and
  /// single-flight semantics.
  Future<List<SyncQueueEntry>> fullUploadEntries(String uid) async {
    final entries = <SyncQueueEntry>[];
    final allPieces = await _db.select(_db.pieces).get();
    final allPhotos = await _db.select(_db.photos).get();
    final clays = await _db.materialsDao.getAllClays();
    final glazes = await _db.materialsDao.getAllGlazes();
    final tags = await _db.materialsDao.getAllTags();

    entries.addAll(
      allPieces.map(
        (piece) => SyncQueueEntry(
          operation: SyncOperation.pushPiece,
          entityId: piece.id,
        ),
      ),
    );
    for (final photo in allPhotos) {
      entries.add(
        SyncQueueEntry(operation: SyncOperation.pushPhoto, entityId: photo.id),
      );
      if (photo.cloudUrl == null && File(photo.localPath).existsSync()) {
        entries.add(
          SyncQueueEntry(
            operation: SyncOperation.pushPhotoFile,
            entityId: photo.id,
          ),
        );
      }
    }
    entries.addAll(
      clays.map(
        (clay) => SyncQueueEntry(
          operation: SyncOperation.pushClay,
          entityId: clay.id,
        ),
      ),
    );
    entries.addAll(
      glazes.map(
        (glaze) => SyncQueueEntry(
          operation: SyncOperation.pushGlaze,
          entityId: glaze.id,
        ),
      ),
    );
    entries.addAll(
      tags.map(
        (tag) =>
            SyncQueueEntry(operation: SyncOperation.pushTag, entityId: tag.id),
      ),
    );
    for (final piece in allPieces) {
      entries.add(
        SyncQueueEntry(
          operation: SyncOperation.pushPieceGlazes,
          entityId: piece.id,
        ),
      );
      entries.add(
        SyncQueueEntry(
          operation: SyncOperation.pushPieceTags,
          entityId: piece.id,
        ),
      );
    }
    return entries;
  }

  // ════════════════════════════════════════════
  // Pull methods
  // ════════════════════════════════════════════

  /// The collections pulled by `updatedAt`, in merge order. Pieces come
  /// first so photo and junction rows find their piece.
  static const _pulledCollections = [
    'pieces',
    'photos',
    'clays',
    'glazes',
    'tags',
  ];

  /// How far behind its watermark an incremental query starts.
  ///
  /// The watermarks below are already server time, so this is insurance, not
  /// load-bearing: a merge is idempotent and guarded, so reading a doc twice
  /// costs only the read.
  static const _pullOverlap = Duration(minutes: 1);

  // Pulls must reach the server for every collection, including junctions.
  // A cache fallback can omit another device's edits; saving a successful
  // pull watermark after it would skip those edits on the next online sync.
  //
  // Returns the entries of a full snapshot ([fullUploadEntries]) for what the
  // cloud already holds: every live doc the pull read, and for each piece
  // among them its glaze and tag links. Each such row is now the cloud's copy
  // here, or has queued work of its own that sends it, so a snapshot that
  // pushed it again could only carry an older copy.
  //
  // It does not record that this device has pulled ([getLastPulledAt]), nor
  // download missing photos. A full pull comes before the snapshot it trims
  // is queued: a device that stops between the two must pull in full and
  // stage that snapshot again, and the snapshot must not wait behind the
  // downloads. The incremental pull that follows its pushes does both.
  Future<Set<SyncQueueEntry>> pullAll(String uid) {
    debugPrint('SyncService: full pull (first sync on this device)');
    return _pull(uid, full: true);
  }

  /// Pulls what changed in each collection since that collection's own
  /// server-time watermark. A collection without one — the first pull after
  /// upgrading from a version that kept a single device-clock watermark — is
  /// pulled in full, once, so edits and photo URLs that version's pulls
  /// missed arrive however long ago they were made.
  Future<void> pullChangedSince(String uid) async {
    debugPrint('SyncService: incremental pull');
    await _pull(uid, full: false);
    await _downloadMissingPhotos(uid);
    await _saveLastPulledAt(uid);
  }

  /// One pull of every collection, in full when [full] is set. Returns what
  /// [pullAll] does.
  ///
  /// It never writes over local work that is queued for the cloud. An entity
  /// with a queued push or delete is skipped: that entry still owns it, and
  /// the push it makes is what the other devices will pull. Pieces and their
  /// junctions are guarded further: a piece that changed here while the pull
  /// ran is skipped too, checked in the same transaction as the write, and a
  /// junction set is replaced only while its piece still carries the
  /// `updatedAt` this pull last saw, so a piece edit landing mid-pull wins
  /// even before its queue entry is written. Photos and materials rely on
  /// the queued-entry check alone. A doc skipped by either check holds its
  /// collection's watermark behind it, so the next pull reads it again;
  /// junctions are read in full every time.
  ///
  /// Remote piece stamps are server time, the time the cloud copy was last
  /// pushed. A device taking the cloud copy converges with it instead of
  /// keeping an older copy of its own.
  Future<Set<SyncQueueEntry>> _pull(String uid, {required bool full}) async {
    final prefs = await SharedPreferences.getInstance();
    final pieceStamps = {
      for (final piece in await _db.select(_db.pieces).get())
        piece.id: piece.updatedAt,
    };
    final watermarks = <String, DateTime>{};
    final inCloud = <SyncQueueEntry>{};
    final queriedAt = await _serverNow(uid);

    for (final collection in _pulledCollections) {
      final from = full ? null : _collectionWatermark(prefs, uid, collection);
      final collectionRef = _col(uid, collection);
      final query = from == null
          ? collectionRef
          : collectionRef.where(
              'updatedAt',
              isGreaterThan: Timestamp.fromDate(from.subtract(_pullOverlap)),
            );
      final isQueued = await _queuedCheck();
      final snap = await query.get(const GetOptions(source: Source.server));
      DateTime? held;

      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        if (data['deletedAt'] != null) {
          await _handleRemoteDeletion(collection, doc.id);
          continue;
        }
        final push = _pushEntryFor(collection, doc.id);
        inCloud.add(push);
        if (collection == 'pieces') {
          inCloud.addAll([
            SyncQueueEntry(
              operation: SyncOperation.pushPieceGlazes,
              entityId: doc.id,
            ),
            SyncQueueEntry(
              operation: SyncOperation.pushPieceTags,
              entityId: doc.id,
            ),
          ]);
        }
        final applied =
            !isQueued(push) &&
            !isQueued(_deletionEntryFor(collection, doc.id)) &&
            await _mergeRemoteDoc(collection, doc, pieceStamps);
        if (data['updatedAt'] case final Timestamp stamp when !applied) {
          final at = stamp.toDate();
          if (held == null || at.isBefore(held)) held = at;
        }
      }
      watermarks[collection] = _nextWatermark(from, snap.docs, queriedAt, held);
    }

    await _pullJunctions(
      uid,
      'pieceGlazes',
      optionField: 'glazeOptionId',
      pushOperation: SyncOperation.pushPieceGlazes,
      pieceStamps: pieceStamps,
    );
    await _pullJunctions(
      uid,
      'pieceTags',
      optionField: 'tagOptionId',
      pushOperation: SyncOperation.pushPieceTags,
      pieceStamps: pieceStamps,
    );

    // Saved only once the whole pull succeeded: a pull that throws part-way
    // reads the same docs again next time, which the merges tolerate.
    for (final MapEntry(key: collection, value: watermark)
        in watermarks.entries) {
      await prefs.setInt(
        _collectionWatermarkKey(uid, collection),
        watermark.microsecondsSinceEpoch,
      );
    }
    return inCloud;
  }

  Future<DateTime?> getLastPulledAt(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('$lastPulledAtPrefix$uid');
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Records, on this device's clock, that an incremental pull for [uid]
  /// completed, which a device only runs once its full snapshot is queued.
  /// The caller uses it to choose between a full and an incremental pull;
  /// the queries themselves start from the per-collection watermarks.
  Future<void> _saveLastPulledAt(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      '$lastPulledAtPrefix$uid',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Under [lastPulledAtPrefix], so every path that clears the device-wide
  /// watermark clears these with it.
  static String _collectionWatermarkKey(String uid, String collection) =>
      '$lastPulledAtPrefix$uid/$collection';

  DateTime? _collectionWatermark(
    SharedPreferences prefs,
    String uid,
    String collection,
  ) {
    final micros = prefs.getInt(_collectionWatermarkKey(uid, collection));
    return micros == null ? null : DateTime.fromMicrosecondsSinceEpoch(micros);
  }

  /// Where the next query of a collection may start: the newest `updatedAt`
  /// the server returned, which is server time, so a doc this query did not
  /// see was committed after it and carries a later one.
  ///
  /// It is capped at the server's clock read before the query, [queriedAt].
  /// Pieces pushed by an earlier app version carry their device's edit time
  /// instead, and one from a fast clock must not carry the watermark past
  /// server-stamped writes still to come. It stays behind [held], the oldest
  /// doc this pull read without applying, so the next query reads that doc
  /// again. A query that returned nothing leaves the watermark where it was;
  /// a full pull of an empty collection starts the next query from the
  /// beginning, which costs nothing while it stays empty.
  DateTime _nextWatermark(
    DateTime? from,
    List<QueryDocumentSnapshot> docs,
    DateTime queriedAt,
    DateTime? held,
  ) {
    DateTime? newest;
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      final updatedAt = data?['updatedAt'];
      if (updatedAt is! Timestamp) continue;
      final at = updatedAt.toDate();
      if (newest == null || at.isAfter(newest)) newest = at;
    }
    if (newest == null) {
      return from ?? DateTime.fromMicrosecondsSinceEpoch(0);
    }
    final bounded = newest.isAfter(queriedAt) ? queriedAt : newest;
    final next = from != null && from.isAfter(bounded) ? from : bounded;
    return held != null && !next.isBefore(held)
        ? held.subtract(const Duration(microseconds: 1))
        : next;
  }

  /// The server's clock now, read back from a document stamped with it. A
  /// transaction rather than a plain write, because a transaction fails while
  /// the device is offline where a write would wait for the network with the
  /// pull still holding the sync.
  Future<DateTime> _serverNow(String uid) async {
    final clock = _col(uid, 'meta').doc('sync-clock');
    await _firestore.runTransaction<void>((transaction) async {
      transaction.set(clock, {'at': FieldValue.serverTimestamp()});
    });
    final read = await clock.get(const GetOptions(source: Source.server));
    return ((read.data() as Map<String, dynamic>)['at'] as Timestamp).toDate();
  }

  /// A test for whether an entry is still waiting to reach the cloud: in the
  /// persisted queue, or enqueued by this process since that was read.
  ///
  /// Read it before the query whose docs it judges. An entry whose push lands
  /// while that query is in the air then still counts as queued, so the copy
  /// the query read from before that push is not written over it.
  Future<bool Function(SyncQueueEntry)> _queuedCheck() async {
    final persisted = (await _queue.getAll()).toSet();
    return (entry) =>
        persisted.contains(entry) || _queue.revisionOf(entry) != 0;
  }

  /// The queue entry that pushes the local row a pulled [collection] doc
  /// mirrors. It, or [_deletionEntryFor], owns that row while queued.
  static SyncQueueEntry _pushEntryFor(String collection, String id) =>
      SyncQueueEntry(
        operation: switch (collection) {
          'pieces' => SyncOperation.pushPiece,
          'photos' => SyncOperation.pushPhoto,
          'clays' => SyncOperation.pushClay,
          'glazes' => SyncOperation.pushGlaze,
          _ => SyncOperation.pushTag,
        },
        entityId: id,
      );

  static SyncQueueEntry _deletionEntryFor(String collection, String id) =>
      switch (collection) {
        'pieces' => SyncQueueEntry(
          operation: SyncOperation.deletePiece,
          entityId: id,
        ),
        'photos' => SyncQueueEntry(
          operation: SyncOperation.deletePhoto,
          entityId: id,
        ),
        _ => SyncQueueEntry(
          operation: SyncOperation.deleteMaterial,
          entityId: id,
          extraData: collection,
        ),
      };

  /// Junctions have no `updatedAt`, so every pull reads them in full; a set
  /// skipped here is simply looked at again next time.
  Future<void> _pullJunctions(
    String uid,
    String collection, {
    required String optionField,
    required SyncOperation pushOperation,
    required Map<String, DateTime> pieceStamps,
  }) async {
    final isQueued = await _queuedCheck();
    final snap = await _col(
      uid,
      collection,
    ).get(const GetOptions(source: Source.server));
    final byPiece = <String, List<Map<String, dynamic>>>{};
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      final pieceId = data?['pieceId'] as String?;
      if (pieceId == null) continue;
      byPiece.putIfAbsent(pieceId, () => []).add(data!);
    }
    for (final MapEntry(key: pieceId, value: docs) in byPiece.entries) {
      if (isQueued(
            SyncQueueEntry(operation: pushOperation, entityId: pieceId),
          ) ||
          isQueued(
            SyncQueueEntry(
              operation: SyncOperation.deletePiece,
              entityId: pieceId,
            ),
          )) {
        continue;
      }
      docs.sort(
        (a, b) => (a['sortOrder'] as int? ?? 0).compareTo(
          b['sortOrder'] as int? ?? 0,
        ),
      );
      final remoteIds = [
        for (final data in docs)
          if (data[optionField] case final String optionId) optionId,
      ];
      if (remoteIds.isEmpty) continue;
      await _mergeRemoteJunctions(
        collection,
        pieceId,
        remoteIds,
        pieceStamps[pieceId],
      );
    }
  }

  // ════════════════════════════════════════════
  // Remote merge
  // ════════════════════════════════════════════

  /// Applies one live remote doc whose local row has no queued work, and
  /// answers whether it did. [pieceStamps] is told the `updatedAt` of every
  /// piece row written here.
  ///
  /// A piece is kept only when it changed here while the pull ran; otherwise
  /// the cloud's copy replaces it, whatever either stamp says. Local work not
  /// yet pushed is queued, and was skipped before this was called.
  Future<bool> _mergeRemoteDoc(
    String collection,
    QueryDocumentSnapshot doc,
    Map<String, DateTime> pieceStamps,
  ) async {
    switch (collection) {
      case 'pieces':
        return _db.transaction(() async {
          final local = await _db.piecesDao.getPieceById(doc.id);
          final d = doc.data() as Map<String, dynamic>;
          final remoteUpdatedAt = _wholeSeconds(
            (d['updatedAt'] as Timestamp).toDate(),
          );
          if (local == null) {
            await _insertPieceFromRemote(doc, remoteUpdatedAt);
          } else {
            final seen = pieceStamps[doc.id];
            if (seen == null || !local.updatedAt.isAtSameMomentAs(seen)) {
              return false;
            }
            await _updatePieceFromRemote(doc, remoteUpdatedAt);
          }
          pieceStamps[doc.id] = remoteUpdatedAt;
          return true;
        });
      case 'photos':
        final local = await _db.photosDao.getPhotoById(doc.id);
        if (local == null) {
          await _insertPhotoFromRemote(doc);
        } else {
          await _updatePhotoFromRemote(doc);
          // This device published the URL, and an earlier version's pushPhoto
          // from a device that had not learned it wrote null over it. Pushing
          // the photo again puts the URL back for every other device.
          if (local.cloudUrl != null &&
              (doc.data() as Map<String, dynamic>)['cloudUrl'] == null) {
            await _trigger.afterPhotoWrite(doc.id);
          }
        }
      case 'clays':
        await _insertClayFromRemote(doc);
      case 'glazes':
        await _insertGlazeFromRemote(doc);
      case 'tags':
        await _insertTagFromRemote(doc);
    }
    return true;
  }

  /// Truncated to the whole second the local database stores, so the stamp a
  /// pull records in `pieceStamps` for a piece it wrote is the one the
  /// junction merge reads back.
  static DateTime _wholeSeconds(DateTime at) =>
      DateTime.fromMillisecondsSinceEpoch(
        at.millisecondsSinceEpoch - at.millisecondsSinceEpoch % 1000,
      );

  /// Rewrites a piece's glaze or tag links from [remoteIds], which also
  /// rebuilds its `glazes` or `tags` text from the option names this pull
  /// brought in, unless the piece changed locally since [expectedStamp] was
  /// read: every local link edit moves the piece's `updatedAt`, and this
  /// pull's own writes do not.
  Future<void> _mergeRemoteJunctions(
    String collection,
    String pieceId,
    List<String> remoteIds,
    DateTime? expectedStamp,
  ) async {
    if (expectedStamp == null) return;
    final materials = _db.materialsDao;
    await _db.transaction(() async {
      final piece = await _db.piecesDao.getPieceById(pieceId);
      if (piece == null || !piece.updatedAt.isAtSameMomentAs(expectedStamp)) {
        return;
      }
      if (collection == 'pieceGlazes') {
        await materials.setGlazesForPiece(
          pieceId,
          remoteIds,
          touchUpdatedAt: false,
        );
      } else {
        await materials.setTagsForPiece(
          pieceId,
          remoteIds,
          touchUpdatedAt: false,
        );
      }
    });
  }

  Future<void> _handleRemoteDeletion(String collection, String docId) async {
    switch (collection) {
      case 'pieces':
        await _db.photosDao.deletePhotosForPiece(docId);
        await _db.piecesDao.deletePiece(docId);
      case 'photos':
        await _db.photosDao.deletePhoto(docId);
      case 'clays':
        await _db.materialsDao.deleteClay(docId);
      case 'glazes':
        await _db.materialsDao.deleteGlaze(docId, touchUpdatedAt: false);
      case 'tags':
        await _db.materialsDao.deleteTag(docId, touchUpdatedAt: false);
    }
  }

  // ════════════════════════════════════════════
  // Entity insert/update from remote
  // ════════════════════════════════════════════

  Future<void> _insertPieceFromRemote(
    QueryDocumentSnapshot doc,
    DateTime updatedAt,
  ) async {
    final d = doc.data() as Map<String, dynamic>;
    final displayDateTs = d['displayDate'] as Timestamp?;
    await _db.piecesDao.insertPiece(
      PiecesCompanion(
        id: Value(doc.id),
        title: Value(d['title'] as String?),
        stage: Value(d['stage'] as String?),
        clayType: Value(d['clayType'] as String?),
        notes: Value(d['notes'] as String?),
        coverPhotoId: Value(d['coverPhotoId'] as String?),
        isArchived: Value(d['isArchived'] as bool? ?? false),
        displayDate: Value(displayDateTs?.toDate()),
        createdAt: Value((d['createdAt'] as Timestamp).toDate()),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<void> _updatePieceFromRemote(
    QueryDocumentSnapshot doc,
    DateTime updatedAt,
  ) async {
    final d = doc.data() as Map<String, dynamic>;
    final displayDateTs = d['displayDate'] as Timestamp?;
    await _db.piecesDao.updatePiece(
      PiecesCompanion(
        id: Value(doc.id),
        title: Value(d['title'] as String?),
        stage: Value(d['stage'] as String?),
        clayType: Value(d['clayType'] as String?),
        notes: Value(d['notes'] as String?),
        coverPhotoId: Value(d['coverPhotoId'] as String?),
        isArchived: Value(d['isArchived'] as bool? ?? false),
        displayDate: Value(displayDateTs?.toDate()),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<void> _insertPhotoFromRemote(QueryDocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    final cloudUrl = d['cloudUrl'] as String?;
    // Use a placeholder path — actual file will be downloaded later
    final appDir = await getApplicationDocumentsDirectory();
    final pieceId = d['pieceId'] as String;
    final localPath = '${appDir.path}/photos/$pieceId/${doc.id}.jpg';

    await _db.photosDao.insertPhoto(
      PhotosCompanion(
        id: Value(doc.id),
        pieceId: Value(pieceId),
        localPath: Value(localPath),
        cloudUrl: Value(cloudUrl),
        dateTaken: Value((d['dateTaken'] as Timestamp).toDate()),
        createdAt: Value((d['createdAt'] as Timestamp).toDate()),
        sortOrder: Value(d['sortOrder'] as int? ?? 0),
      ),
    );
  }

  Future<void> _updatePhotoFromRemote(QueryDocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    final cloudUrl = d['cloudUrl'] as String?;
    await _db.photosDao.updatePhoto(
      PhotosCompanion(
        id: Value(doc.id),
        // A URL is final once published; a remote null only means the doc
        // was last written by a device that had not learned it.
        cloudUrl: cloudUrl != null ? Value(cloudUrl) : const Value.absent(),
        sortOrder: Value(d['sortOrder'] as int? ?? 0),
      ),
    );
  }

  Future<void> _insertClayFromRemote(QueryDocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    try {
      await _db
          .into(_db.clayOptions)
          .insert(
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

  Future<void> _insertGlazeFromRemote(QueryDocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    try {
      await _db
          .into(_db.glazeOptions)
          .insert(
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

  Future<void> _insertTagFromRemote(QueryDocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    try {
      await _db
          .into(_db.tagOptions)
          .insert(
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

  // ════════════════════════════════════════════
  // Photo upload retry (for photos with local files but null cloudUrl)
  // ════════════════════════════════════════════

  /// Durable upload work, including files whose queue attempt already ended.
  /// Remote-only photos have no local file to upload, so they are excluded.
  /// `SyncNotifier.syncNow` retries each of these through its push lanes.
  Future<Set<String>> pendingPhotoUploadIds() async {
    final photos = await _db.select(_db.photos).get();
    return {
      for (final photo in photos)
        if (photo.cloudUrl == null && File(photo.localPath).existsSync())
          photo.id,
    };
  }

  // ════════════════════════════════════════════
  // Photo download
  // ════════════════════════════════════════════

  Future<void> _downloadMissingPhotos(String uid) async {
    final allPhotos = await _db.select(_db.photos).get();
    final missingLocal = allPhotos
        .where((p) => !File(p.localPath).existsSync())
        .toList();
    final downloadable = missingLocal.where((p) => p.cloudUrl != null).toList();
    final unrecoverable = missingLocal
        .where((p) => p.cloudUrl == null)
        .toList();

    debugPrint(
      'SyncService: ${missingLocal.length} photos missing locally '
      '(${downloadable.length} downloadable, '
      '${unrecoverable.length} have no cloudUrl — need upload from source device)',
    );

    final missing = downloadable;

    // Download in batches of 5
    for (var i = 0; i < missing.length; i += 5) {
      final batch = missing.sublist(
        i,
        i + 5 > missing.length ? missing.length : i + 5,
      );
      await Future.wait(batch.map((photo) => _downloadPhoto(photo)));
    }
  }

  Future<void> _downloadPhoto(Photo photo) async {
    try {
      debugPrint(
        'SyncService: downloading photo ${photo.id} from ${photo.cloudUrl}',
      );

      // Use current app directory (container UUID changes on reinstall)
      final appDir = await getApplicationDocumentsDirectory();
      final localPath =
          '${appDir.path}/photos/${photo.pieceId}/${photo.id}.jpg';
      final thumbnailPath =
          '${appDir.path}/photos/${photo.pieceId}/${photo.id}_thumb.jpg';

      final file = File(localPath);
      await file.parent.create(recursive: true);

      // Download from cloud URL with timeout
      final ref = _storage.refFromURL(photo.cloudUrl!);
      final data = await ref.getData().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('SyncService: download timed out for ${photo.id}');
          return null;
        },
      );
      if (data == null) return;

      await file.writeAsBytes(data);
      debugPrint(
        'SyncService: downloaded photo ${photo.id} (${data.length} bytes)',
      );

      // Regenerate thumbnail
      final thumbBytes = await FlutterImageCompress.compressWithList(
        data,
        minWidth: 300,
        minHeight: 300,
        quality: 60,
      );
      await File(thumbnailPath).writeAsBytes(thumbBytes);

      // Update DB with current paths
      await _db.photosDao.updatePhoto(
        PhotosCompanion(
          id: Value(photo.id),
          localPath: Value(localPath),
          thumbnailPath: Value(thumbnailPath),
        ),
      );
    } catch (e) {
      debugPrint('SyncService: download failed for ${photo.id}: $e');
    }
  }
}
