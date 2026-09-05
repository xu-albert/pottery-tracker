import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thrown when the database key could not be persisted where the next launch
/// will look for it.
///
/// Raised only after every fallback has been tried and a read-back still does
/// not return the key. Continuing would let this session write pottery into a
/// database that no launch after it can open, so the caller must stop rather
/// than proceed with the key it still holds in memory.
class KeyStorageException implements Exception {
  const KeyStorageException(this.message);

  final String message;

  @override
  String toString() => 'KeyStorageException: $message';
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
/// injected storage's defaults, and [hardenStoredKey] is what moves a key
/// stored by a release before this one.
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

  static const _keyLength = 32;
  static const _chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  /// The one iOS keychain configuration the key is ever written under.
  static const iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );

  /// What releases before this one stored the key under, kept only so a
  /// hardening rewrite that fails can put the key back where it was rather
  /// than leave the device with no key at all.
  static const legacyIosOptions = IOSOptions(
    accessibility: KeychainAccessibility.unlocked,
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

  EncryptionKeyService({FlutterSecureStorage? storage})
    : _storage = storage ?? defaultStorage;

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
  /// the same, which is what lets [hardenStoredKey] see it. A storage failure
  /// propagates rather than reading as "no key" — treating an unreadable key
  /// as a missing one is exactly the mistake that would send a user with a
  /// perfectly good database into recovery.
  Future<String?> readKey() async {
    final existing = await _storage.read(
      key: _storageKey,
      iOptions: iosOptions,
      aOptions: androidOptions,
    );
    return (existing == null || existing.isEmpty) ? null : existing;
  }

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

  /// Persists a key recovered from a transfer backup as this device's key.
  Future<void> storeRecoveredKey(String key) => _storeHardened(key);

  /// Moves a key stored by an earlier release under the pinned options, and
  /// records that it has been.
  ///
  /// The rewrite is what does the moving. `kSecAttrAccessible` cannot be
  /// changed in place, so the item is deleted (under any accessibility) and
  /// added again under the pinned one — see [_writeKey]; the Android plugin
  /// re-encrypts every value when the cipher options differ from the ones it
  /// recorded. Both are idempotent, so the marker is an optimisation that
  /// also spares the key a delete-and-add on every launch.
  ///
  /// Verified by reading back, because between the delete and the add there
  /// is a moment with no key on disk. If the hardened write does not stick,
  /// the key is written back under [legacyIosOptions] so the device is no
  /// worse off than before this launch, and the marker is left unset so the
  /// next launch tries again. If even that does not stick, a
  /// [KeyStorageException] stops the launch: proceeding with the in-memory
  /// key would let this session add pottery that no later launch can read.
  Future<void> hardenStoredKey(String key) async {
    final version = await _storage.read(
      key: _storageVersionKey,
      iOptions: iosOptions,
      aOptions: androidOptions,
    );
    if (version == _currentStorageVersion) return;

    try {
      await _writeKey(key, iosOptions);
      if (await readKey() == key) {
        await _writeMarker();
        return;
      }
      debugPrint(
        'EncryptionKeyService: the hardened key did not read back; '
        'restoring the previous protections',
      );
    } catch (e) {
      debugPrint('EncryptionKeyService: hardening rewrite failed: $e');
    }

    await _writeKey(key, legacyIosOptions);
    if (await readKey() != key) {
      throw const KeyStorageException(
        'the database key could not be stored under either the current or '
        'the previous protections; refusing to open the database with a key '
        'the next launch will not have',
      );
    }
  }

  Future<void> _storeHardened(String key) async {
    await _writeKey(key, iosOptions);
    if (await readKey() != key) {
      throw const KeyStorageException(
        'the database key did not read back after being written',
      );
    }
    await _writeMarker();
  }

  /// Options whose iOS map carries no `accessibility` at all, so the plugin's
  /// delete query matches the item whatever protection it was stored under.
  static const _anyAccessibility = IOSOptions(
    accessibility: null,
    synchronizable: false,
  );

  /// Replaces the stored key: delete under any accessibility, then add.
  ///
  /// The plugin's own write would do this for a changed accessibility — but
  /// only after a `SecItemUpdate` whose query names the *new* accessibility
  /// fails to match. Deleting first removes the dependence on that query
  /// semantics: the add below always creates the item afresh under
  /// [iOptions]. The read-back that follows every call is what catches the
  /// moment in between going wrong.
  Future<void> _writeKey(String key, IOSOptions iOptions) async {
    await _storage.delete(
      key: _storageKey,
      iOptions: _anyAccessibility,
      aOptions: androidOptions,
    );
    await _storage.write(
      key: _storageKey,
      value: key,
      iOptions: iOptions,
      aOptions: androidOptions,
    );
  }

  /// Best effort: the key is already safely stored by the time this runs, and
  /// a marker that fails to land only means the next launch repeats an
  /// idempotent rewrite.
  Future<void> _writeMarker() async {
    try {
      await _storage.write(
        key: _storageVersionKey,
        value: _currentStorageVersion,
        iOptions: iosOptions,
        aOptions: androidOptions,
      );
    } catch (e) {
      debugPrint('EncryptionKeyService: storage-version marker not saved: $e');
    }
  }
}
