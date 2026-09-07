import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thrown when the database key could not be persisted where the next launch
/// will look for it.
///
/// Raised only once neither the stored item nor its migrating copy reads
/// back. Continuing would let this session write pottery into a database
/// that no launch after it can open, so the caller must stop rather than
/// proceed with the key it still holds in memory.
class KeyStorageException implements Exception {
  const KeyStorageException(this.message);

  final String message;

  @override
  String toString() => 'KeyStorageException: $message';
}

/// Thrown when the keychain cannot answer yet.
///
/// On iOS, before the device has been unlocked for the first time since it
/// started — when iOS may prewarm the app — every item is inaccessible, and
/// the plugin reports an item it may not read as absent. That is not "no
/// key". A launch that gets this must fail and be retried, never decide that
/// the database has no key: that decision is only safe once protected data
/// is available.
class KeyStoreUnavailableException implements Exception {
  const KeyStoreUnavailableException();

  @override
  String toString() =>
      'KeyStoreUnavailableException: the keychain is not available yet; the '
      'device has not been unlocked since it started';
}

/// Owns the SQLCipher key for the local database: where it is kept, under
/// which platform protections, and how a key stored under the old ones is
/// moved.
///
/// The protections are pinned here explicitly rather than left to plugin
/// defaults, because they decide what a device backup carries:
///
/// * **iOS** — [iosOptions] uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
///   (`first_unlock_this_device`). The `ThisDeviceOnly` half is the point: an
///   item with it is left out of every backup, encrypted or not, so restoring
///   a backup onto a new phone brings the database file (which lives in
///   `Documents/` and is backed up) without the key that opens it. The plugin
///   default, `unlocked`, migrates with an encrypted backup — key and database
///   travelled together. `first_unlock` rather than `unlocked` because the
///   database is opened at launch and a launch can happen in the background
///   while the screen is locked; nothing here needs the stricter window.
///   `synchronizable: false` keeps it out of iCloud Keychain (also the
///   default, pinned so a default change cannot flip it).
/// * **Android** — [androidOptions] keeps the plugin's own KeyStore-wrapped
///   store but on its modern ciphers: RSA-OAEP(SHA-256, MGF1) to wrap the
///   storage key and AES-GCM for the values, instead of the RSA/ECB/PKCS1 +
///   AES/CBC legacy pair the plugin still defaults to. `minSdk` is 24, above
///   the API 23 these need, so the plugin never falls back. Jetpack
///   `EncryptedSharedPreferences` is deliberately not used: it is deprecated
///   upstream, and this path re-encrypts existing values itself when the
///   ciphers change.
///
/// A key that reaches the disk under different protections than these is a
/// silent regression — on iOS it starts travelling in backups again — so
/// every call here passes the options explicitly rather than relying on the
/// injected storage's defaults, nothing is ever written under any other
/// options, and [hardenStoredKey] is what moves a key stored by a release
/// before this one.
class EncryptionKeyService {
  static const _storageKey = 'db_encryption_key';

  /// Records that [_storageKey] was last written under [iosOptions] /
  /// [androidOptions]. Absent for a key stored by a release before this one.
  ///
  /// It lives in secure storage on purpose, so on iOS it carries the same
  /// backup behaviour as the key it describes: a restored phone has neither.
  /// Re-storing is idempotent, so a lost marker costs one extra rewrite, never
  /// correctness.
  static const _storageVersionKey = 'db_encryption_key_storage_version';
  static const _currentStorageVersion = '2';

  /// A second copy of the key, present only while [_storageKey] is being
  /// deleted and added again (see [_addMain]) — and afterwards, if the
  /// process died in between, which is what it is for.
  static const _migratingStorageKey = 'db_encryption_key_migrating';

  static const _keyLength = 32;
  static const _chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  /// The one iOS keychain configuration the key is ever written under.
  static const iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );

  /// The one Android configuration the key is ever written under.
  static const androidOptions = AndroidOptions(
    encryptedSharedPreferences: false,
    keyCipherAlgorithm:
        KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
    storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
  );

  /// The storage the app uses when nothing is injected, pinned to the same
  /// options every call passes anyway.
  static const FlutterSecureStorage defaultStorage = FlutterSecureStorage(
    iOptions: iosOptions,
    aOptions: androidOptions,
  );

  final FlutterSecureStorage _storage;
  final Future<bool?> Function() _protectedDataAvailable;

  /// [protectedDataAvailable] answers whether the iOS keychain can be read at
  /// all right now (see [KeyStoreUnavailableException]). It defaults to the
  /// plugin's own query and is injectable because the plugin only answers it
  /// over a real method channel; null means the platform has no such notion.
  EncryptionKeyService({
    FlutterSecureStorage? storage,
    Future<bool?> Function()? protectedDataAvailable,
  }) : _storage = storage ?? defaultStorage,
       _protectedDataAvailable =
           protectedDataAvailable ??
           (storage ?? defaultStorage).isCupertinoProtectedDataAvailable;

  /// Generates a fresh 32-character alphanumeric key.
  ///
  /// The alphabet is deliberately `[A-Za-z0-9]`: the key becomes a SQL
  /// literal in `PRAGMA key` (see `configureSqlCipher`), and while that path
  /// escapes quotes, an alphabet that cannot produce one is the cheaper
  /// guarantee.
  static String generateKey() {
    final random = Random.secure();
    return List.generate(
      _keyLength,
      (_) => _chars[random.nextInt(_chars.length)],
    ).join();
  }

  /// The stored key, or null when none is stored.
  ///
  /// Reads deliberately pass no accessibility: the iOS plugin ignores it on
  /// reads anyway, so a key stored under the legacy protections is found just
  /// the same, which is what lets [hardenStoredKey] see it. A launch that
  /// died halfway through a rewrite finds the key in the migrating copy
  /// instead (see [_writeMigratingCopy]).
  ///
  /// Null is only returned once it can be trusted. On iOS the plugin reports
  /// an item it is not allowed to read as absent, so a null is confirmed
  /// against protected-data availability and becomes
  /// [KeyStoreUnavailableException] when the keychain is simply not open
  /// yet. A read that throws propagates rather than reading as "no key";
  /// Android's one exception is in [_read].
  Future<String?> readKey() async {
    final key = await _read(_storageKey) ?? await _read(_migratingStorageKey);
    if (key != null) return key;
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        await _protectedDataAvailable() == false) {
      throw const KeyStoreUnavailableException();
    }
    return null;
  }

  /// The migrating copy alone, for a launch whose stored key does not open
  /// the database: a rotation at erase that died after its copy landed but
  /// before the item was replaced left the file keyed to the copy.
  Future<String?> readMigratingCopy() => _read(_migratingStorageKey);

  /// Generates a key, stores it under the pinned options and returns it.
  ///
  /// Only for a device with no database yet. A device that has a database
  /// but no key is a restore, not a first launch, and is the bootstrap's
  /// problem — creating a key here would open a fresh empty database over the
  /// user's pottery.
  Future<String> createKey() async {
    final key = generateKey();
    await _storeHardened(key);
    return key;
  }

  /// Persists [key] as this device's key under the pinned options: one
  /// recovered from a transfer backup, or a fresh one the database was just
  /// rekeyed to.
  Future<void> storeKey(String key) => _storeHardened(key);

  /// Moves a key stored by an earlier release under the pinned options, and
  /// records that it has been.
  ///
  /// The rewrite is what does the moving. `kSecAttrAccessible` cannot be
  /// changed in place, so the item is deleted (under any accessibility) and
  /// added again under the pinned one — see [_addMain], with a copy on disk
  /// throughout ([_writeMigratingCopy]) so that a process dying between the
  /// two leaves a key the next launch can read; the Android plugin
  /// re-encrypts every value when the cipher options differ from the ones it
  /// recorded. Both are idempotent, so the marker is an optimisation that
  /// also spares the key a delete-and-add on every launch.
  ///
  /// Verified by reading back. If the hardened add does not stick, the copy
  /// — itself under the pinned options — is what the device keeps, and the
  /// marker is left unset so the next launch tries again; nothing is ever
  /// written back under the old protections. A [KeyStorageException] stops
  /// the launch only if neither the item nor the copy reads back: proceeding
  /// with the in-memory key would let this session add pottery that no
  /// later launch can read.
  Future<void> hardenStoredKey(String key) async {
    if (await _read(_storageVersionKey) == _currentStorageVersion) return;

    try {
      if (!await _writeMigratingCopy(key)) {
        debugPrint(
          'EncryptionKeyService: the migrating copy did not read back; '
          'leaving the key where it is until the next launch',
        );
        return;
      }
    } catch (e) {
      debugPrint(
        'EncryptionKeyService: the migrating copy could not be written; '
        'leaving the key where it is until the next launch: $e',
      );
      return;
    }

    var hardened = false;
    try {
      hardened = await _addMain(key, iosOptions);
      if (!hardened) {
        debugPrint(
          'EncryptionKeyService: the hardened key did not read back; the '
          'migrating copy stays until the next launch',
        );
      }
    } catch (e) {
      debugPrint(
        'EncryptionKeyService: hardening rewrite failed; the migrating copy '
        'stays until the next launch: $e',
      );
    }
    if (hardened) {
      await _finishHardened();
      return;
    }

    if (await _read(_migratingStorageKey) != key) {
      throw const KeyStorageException(
        'the database key could not be stored under the pinned protections '
        'and its migrating copy is gone; refusing to open the database with '
        'a key the next launch will not have',
      );
    }
  }

  Future<void> _storeHardened(String key) async {
    if (!await _writeMigratingCopy(key) || !await _addMain(key, iosOptions)) {
      throw const KeyStorageException(
        'the database key did not read back after being written',
      );
    }
    await _finishHardened();
  }

  /// Writes the migrating copy of [key] and reports whether it read back.
  ///
  /// Always before [_addMain], so that at no instant of the delete-then-add
  /// is there no key on disk: a process that dies in between leaves the
  /// copy, [readKey] falls back to it, and the next launch finishes the job.
  /// Under the pinned options — the copy must never enter a backup either.
  /// If it does not read back nothing else is touched, because without it
  /// the rewrite would have no safety net.
  Future<bool> _writeMigratingCopy(String key) async {
    await _write(_migratingStorageKey, key, iosOptions);
    return await _read(_migratingStorageKey) == key;
  }

  /// Replaces the stored key with [key] under [iOptions], and reports whether
  /// it read back.
  ///
  /// The plugin's own write would delete-and-add for a changed accessibility,
  /// but only after a `SecItemUpdate` whose query names the *new*
  /// accessibility fails to match. Deleting first, under any accessibility,
  /// removes the dependence on that query semantics: the add always creates
  /// the item afresh under [iOptions].
  Future<bool> _addMain(String key, IOSOptions iOptions) async {
    await _delete(_storageKey);
    await _write(_storageKey, key, iOptions);
    return await _read(_storageKey) == key;
  }

  /// Once the hardened item has read back: drop the copy, then record the
  /// version — never the marker while a copy could still be found, or a
  /// launch that trusts the marker would leave the copy behind for good.
  Future<void> _finishHardened() async {
    if (await _tryDeleteMigratingCopy()) await _writeMarker();
  }

  Future<bool> _tryDeleteMigratingCopy() async {
    try {
      await _delete(_migratingStorageKey);
      return true;
    } catch (e) {
      debugPrint('EncryptionKeyService: migrating copy not removed: $e');
      return false;
    }
  }

  /// Options whose iOS map carries no `accessibility` at all, so the plugin's
  /// delete query matches the item whatever protection it was stored under.
  static const _anyAccessibility = IOSOptions(
    accessibility: null,
    synchronizable: false,
  );

  /// One stored value, or null when absent or empty.
  ///
  /// On Android, a value the plugin cannot decrypt reads as absent. The plugin
  /// wraps its storage key with a KeyStore key that never leaves the device,
  /// so a value it cannot decrypt is one that came from another device — an
  /// app data directory copied by a device-to-device transfer — and to the
  /// launch that is the same situation as a restored database with no key:
  /// the recovery screen, not a launch failure whose retry fails the same
  /// way forever. The next write replaces the value and reads back fine.
  /// Only that failure reads as absent — the plugin reports every error
  /// under one code, so it is told apart by the `AEADBadTagException` the
  /// GCM decrypt raises; anything else propagates, as on iOS.
  Future<String?> _read(String name) async {
    final String? value;
    try {
      value = await _storage.read(
        key: name,
        iOptions: iosOptions,
        aOptions: androidOptions,
      );
    } on PlatformException catch (e) {
      if (defaultTargetPlatform != TargetPlatform.android ||
          !_isUndecryptable(e)) {
        rethrow;
      }
      debugPrint(
        'EncryptionKeyService: $name is stored but cannot be decrypted on '
        'this device: $e',
      );
      return null;
    }
    return (value == null || value.isEmpty) ? null : value;
  }

  static bool _isUndecryptable(PlatformException e) =>
      '${e.message} ${e.details}'.contains('AEADBadTagException');

  Future<void> _write(String name, String value, IOSOptions iOptions) =>
      _storage.write(
        key: name,
        value: value,
        iOptions: iOptions,
        aOptions: androidOptions,
      );

  Future<void> _delete(String name) => _storage.delete(
    key: name,
    iOptions: _anyAccessibility,
    aOptions: androidOptions,
  );

  /// Best effort: the key is already safely stored by the time this runs, and
  /// a marker that fails to land only means the next launch repeats an
  /// idempotent rewrite.
  Future<void> _writeMarker() async {
    try {
      await _write(_storageVersionKey, _currentStorageVersion, iosOptions);
    } catch (e) {
      debugPrint('EncryptionKeyService: storage-version marker not saved: $e');
    }
  }
}
