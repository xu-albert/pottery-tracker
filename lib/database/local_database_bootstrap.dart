import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart' show AuthNotifier;
import '../providers/sync_provider.dart' show SyncNotifier;
import '../services/encryption_key_service.dart';
import '../services/sync_queue.dart';
import '../services/sync_service.dart';
import 'database.dart';
import 'transfer_key_backup.dart';

/// What launching the local database came to.
sealed class LocalDatabaseLaunch {
  const LocalDatabaseLaunch();
}

/// The database opened with a key this device holds; the app can start.
class LocalDatabaseReady extends LocalDatabaseLaunch {
  const LocalDatabaseReady(this.database);

  final AppDatabase database;
}

/// A database file is present but no key on this device opens it. The app
/// must not start over it; [recovery] is what the user is offered instead.
class LocalDatabaseUnreadable extends LocalDatabaseLaunch {
  const LocalDatabaseUnreadable(this.recovery);

  final LocalDatabaseRecovery recovery;
}

/// Why the database could not be opened.
enum UnreadableDatabaseCause {
  /// No key is stored on this device at all. The signature of a backup
  /// restored onto a new phone: the file came along, the `ThisDeviceOnly`
  /// keychain item did not.
  keyMissing,

  /// A key is stored, but the file does not decrypt with it. Rare — a
  /// database restored onto a device whose keychain already held a key from
  /// an earlier install — and handled the same way, because to the user it
  /// is the same situation.
  keyMismatch,
}

/// Thrown when the key held by the transfer backup does not open the
/// database either.
class TransferKeyMismatchException implements Exception {
  const TransferKeyMismatchException();

  @override
  String toString() =>
      'TransferKeyMismatchException: the transfer backup opened, but the key '
      'it holds does not open the database';
}

/// The ways out of an unreadable database, offered to the user before the app
/// proper ever runs.
///
/// Abstract so the recovery screen can be tested against a fake; the
/// bootstrap supplies the real one.
abstract class LocalDatabaseRecovery {
  UnreadableDatabaseCause get cause;

  /// Whether a transfer backup came along with the database, so a passphrase
  /// can unlock it. See [TransferKeyBackup].
  bool get hasTransferBackup;

  /// The account this device's pottery was last synced for, if any — read
  /// from the restored preferences. Non-null means the pieces exist in the
  /// cloud and can be downloaded again; whatever the old phone never pushed
  /// is not there.
  String? get stampedOwnerUid;

  /// Unwraps the key with [passphrase], confirms it opens the database, and
  /// makes it this device's key.
  ///
  /// Throws [WrongTransferPassphraseException] or
  /// [TransferKeyMismatchException]; either way nothing has changed on disk.
  Future<AppDatabase> unlockWithPassphrase(String passphrase);

  /// Deletes the unreadable database and starts an empty one, keeping the
  /// photo files so the pull that follows sign-in reuses them instead of
  /// downloading every picture again. Sends the user to the sign-in screen.
  Future<AppDatabase> redownloadFromCloud();

  /// Deletes the unreadable database *and* the photo files that came with
  /// it, then starts empty. Destructive by design and confirmed by the user
  /// first; the only way forward for pottery that never left the old phone.
  Future<AppDatabase> startFresh();
}

/// Decides, before the app runs, whether this device can open its database —
/// and moves the key to the pinned protections while it is at it.
///
/// Every launch goes through here. The decision table:
///
/// | key stored | database file | outcome |
/// |---|---|---|
/// | no  | no  | first launch: create a key, open a fresh database |
/// | yes | no  | reinstall on the same device (iOS keeps the keychain): open a fresh database with the existing key |
/// | yes | yes | normal launch: harden the key's storage if not yet done, open |
/// | no  | yes | **restore onto another device** (on Android, also a copied data directory whose key this device cannot decrypt): [LocalDatabaseUnreadable] |
/// | yes | yes, does not decrypt | [LocalDatabaseUnreadable], `keyMismatch` |
///
/// The one thing this never does is create a key while a database file is
/// present. That would open an empty database over the user's pottery and
/// report a clean first launch — which is precisely what the hardening would
/// otherwise cost a local-only user, silently.
class LocalDatabaseBootstrap {
  LocalDatabaseBootstrap({
    required EncryptionKeyService keys,
    required Directory documentsDir,
    required Directory temporaryDir,
    required SharedPreferences prefs,
    required TransferKeyBackup transferBackup,
    Future<AppDatabase> Function(File file, String key)? openEncrypted,
  }) : _keys = keys,
       _documentsDir = documentsDir,
       _temporaryDir = temporaryDir,
       _prefs = prefs,
       _transferBackup = transferBackup,
       _openEncrypted = openEncrypted ?? AppDatabase.open;

  final EncryptionKeyService _keys;
  final Directory _documentsDir;
  final Directory _temporaryDir;
  final SharedPreferences _prefs;
  final TransferKeyBackup _transferBackup;
  final Future<AppDatabase> Function(File file, String key) _openEncrypted;

  File get databaseFile =>
      File(p.join(_documentsDir.path, AppDatabase.fileName));

  /// sqlite's sidecar files. Left behind, a stale WAL could be replayed into
  /// the next database created at the same path.
  List<File> get _databaseSidecars => [
    for (final suffix in const ['-journal', '-wal', '-shm'])
      File('${databaseFile.path}$suffix'),
  ];

  bool get _databaseExists =>
      databaseFile.existsSync() && databaseFile.lengthSync() > 0;

  Future<LocalDatabaseLaunch> launch() async {
    final key = await _keys.readKey();

    if (key == null) {
      if (!_databaseExists) {
        final fresh = await _keys.createKey();
        return LocalDatabaseReady(await _openAndProbe(fresh));
      }
      return LocalDatabaseUnreadable(
        _Recovery(this, UnreadableDatabaseCause.keyMissing),
      );
    }

    await _keys.hardenStoredKey(key);

    if (!_databaseExists) {
      return LocalDatabaseReady(await _openAndProbe(key));
    }
    try {
      return LocalDatabaseReady(await _openAndProbe(key));
    } on _NotADatabaseException {
      final staged = await _keys.readMigratingCopy();
      if (staged != null && staged != key) {
        // A rotation at erase rekeys the file and then stores the new key,
        // via a migrating copy first. A process that died between the copy
        // landing and the item being replaced left the file keyed to the
        // copy; opening with it and finishing the store is that launch's
        // ordinary continuation.
        try {
          return LocalDatabaseReady(await _openAndAdoptKey(staged));
        } on _NotADatabaseException {
          // Not the rotation's key either.
        }
      }
      return LocalDatabaseUnreadable(
        _Recovery(this, UnreadableDatabaseCause.keyMismatch),
      );
    }
  }

  /// Opens the database with [key] and makes [key] this device's, in that
  /// order: a key that did not open the file would have replaced whatever
  /// this device held for nothing, and a store that fails must not leave the
  /// connection it opened behind.
  Future<AppDatabase> _openAndAdoptKey(String key) async {
    final db = await _openAndProbe(key);
    try {
      await _keys.storeKey(key);
    } catch (_) {
      await db.close();
      rethrow;
    }
    return db;
  }

  /// Opens the database and runs one statement against it, so a key that
  /// does not decrypt the file fails here — where it can be told apart and
  /// acted on — rather than on the album's first query.
  Future<AppDatabase> _openAndProbe(String key) async {
    final db = await _openEncrypted(databaseFile, key);
    try {
      await db.customSelect('SELECT count(*) FROM sqlite_master').getSingle();
    } catch (e) {
      await db.close();
      if (isNotADatabase(e)) throw const _NotADatabaseException();
      rethrow;
    }
    return db;
  }

  Future<AppDatabase> _unlockWithPassphrase(String passphrase) async {
    final key = await _transferBackup.read(passphrase);
    final AppDatabase db;
    try {
      db = await _openAndAdoptKey(key);
    } on _NotADatabaseException {
      throw const TransferKeyMismatchException();
    }
    await _clearOwedWipe();
    return db;
  }

  /// An erase owed on the old phone does not survive recovery on this one.
  ///
  /// The flag rides along in the restored preferences, and the lock screen
  /// retries it without asking anything — over the journal the passphrase
  /// just unlocked, or over the photo files [_discard] deliberately kept for
  /// the re-download. Every exit from recovery leaves the user with a
  /// database they chose, so none of them may leave that behind.
  Future<void> _clearOwedWipe() async {
    await _prefs.remove(SyncNotifier.pendingWipeKey);
  }

  Future<AppDatabase> _discard({required bool deletePhotoFiles}) async {
    for (final file in [databaseFile, ..._databaseSidecars]) {
      if (file.existsSync()) await file.delete();
    }
    // Whatever passphrase wrapped the old key unlocks nothing now.
    await _transferBackup.delete();

    if (deletePhotoFiles) {
      final photosDir = Directory(p.join(_documentsDir.path, 'photos'));
      if (photosDir.existsSync()) await photosDir.delete(recursive: true);
      if (_temporaryDir.existsSync()) {
        for (final entity in _temporaryDir.listSync()) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {
            // A cache entry the platform holds on to is not the erase failing.
          }
        }
      }
    }

    await _clearOwedWipe();

    // Nobody owns an empty device, nothing on it can be refused over, and a
    // restored pull watermark would make the next sync incremental — skipping
    // exactly the pieces this just deleted. The sign-in flag goes down so the
    // router puts the user on the sign-in screen, where re-downloading starts.
    await _prefs.remove(SyncService.localDataOwnerKey);
    await _prefs.remove(SyncService.deviceContestedKey);
    await _prefs.remove(SyncQueue.storageKey);
    final watermarks = _prefs
        .getKeys()
        .where((k) => k.startsWith(SyncService.lastPulledAtPrefix))
        .toList();
    for (final key in watermarks) {
      await _prefs.remove(key);
    }
    await _prefs.setBool(AuthNotifier.onboardingKey, false);

    final key = await _keys.readKey() ?? await _keys.createKey();
    return _openAndProbe(key);
  }
}

class _NotADatabaseException implements Exception {
  const _NotADatabaseException();
}

class _Recovery implements LocalDatabaseRecovery {
  _Recovery(this._bootstrap, this.cause);

  final LocalDatabaseBootstrap _bootstrap;

  @override
  final UnreadableDatabaseCause cause;

  @override
  bool get hasTransferBackup => _bootstrap._transferBackup.exists();

  @override
  String? get stampedOwnerUid =>
      _bootstrap._prefs.getString(SyncService.localDataOwnerKey);

  @override
  Future<AppDatabase> unlockWithPassphrase(String passphrase) =>
      _bootstrap._unlockWithPassphrase(passphrase);

  @override
  Future<AppDatabase> redownloadFromCloud() {
    debugPrint(
      'LocalDatabaseBootstrap: discarding unreadable database, '
      'keeping photo files for the re-pull',
    );
    return _bootstrap._discard(deletePhotoFiles: false);
  }

  @override
  Future<AppDatabase> startFresh() {
    debugPrint(
      'LocalDatabaseBootstrap: discarding unreadable database and '
      'its photo files',
    );
    return _bootstrap._discard(deletePhotoFiles: true);
  }
}
