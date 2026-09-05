import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/database/local_database_bootstrap.dart';
import 'package:pottery_tracker/database/transfer_key_backup.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/services/encryption_key_service.dart';
import 'package:pottery_tracker/services/sync_queue.dart';
import 'package:pottery_tracker/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_secure_storage.dart';
import '../helpers/fake_sqlcipher.dart';

const _keyName = 'db_encryption_key';
const _markerName = 'db_encryption_key_storage_version';
const _oldPhoneKey = 'oldPhoneKey0123456789abcdefghijk';

void main() {
  late Directory docs;
  late Directory temp;
  late FakeSecureStoragePlatform platform;
  late EncryptionKeyService keys;
  late TransferKeyBackup backup;
  late SharedPreferences prefs;
  final opened = <AppDatabase>[];

  /// Opens like production does, with the fake standing in for SQLCipher.
  Future<AppDatabase> openEncrypted(File file, String key) async {
    final db = AppDatabase(
      NativeDatabase(file, setup: (raw) => fakeSqlCipher(raw, key)),
    );
    opened.add(db);
    return db;
  }

  LocalDatabaseBootstrap bootstrap() => LocalDatabaseBootstrap(
    keys: keys,
    documentsDir: docs,
    temporaryDir: temp,
    prefs: prefs,
    transferBackup: backup,
    openEncrypted: openEncrypted,
  );

  File dbFile() => File('${docs.path}/pottery_tracker.db');

  /// A database as the old phone left it: keyed with [_oldPhoneKey], with a
  /// piece in it, and — as after a backup restore — its photo files present.
  Future<void> restoreOldPhoneDatabase() async {
    final db = await openEncrypted(dbFile(), _oldPhoneKey);
    await db.customStatement(
      "INSERT INTO pieces (id, title, stage, created_at, updated_at, is_archived) "
      "VALUES ('p1', 'Bowl', 'greenware', 0, 0, 0)",
    );
    await db.close();
    opened.remove(db);
    File('${docs.path}/photos/p1/ph1.jpg')
      ..createSync(recursive: true)
      ..writeAsStringSync('jpeg');
  }

  setUp(() async {
    docs = Directory.systemTemp.createTempSync('bootstrap_docs_');
    temp = Directory.systemTemp.createTempSync('bootstrap_temp_');
    platform = FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = platform;
    keys = EncryptionKeyService(
      storage: const FlutterSecureStorage(
        iOptions: EncryptionKeyService.iosOptions,
        aOptions: EncryptionKeyService.androidOptions,
      ),
    );
    backup = TransferKeyBackup(documentsDir: docs, keyDatabase: fakeSqlCipher);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    for (final db in opened) {
      await db.close();
    }
    opened.clear();
    docs.deleteSync(recursive: true);
    temp.deleteSync(recursive: true);
  });

  group('launch', () {
    test(
      'first launch: no key, no file — creates a key and opens fresh',
      () async {
        final launch = await bootstrap().launch();

        expect(launch, isA<LocalDatabaseReady>());
        final db = (launch as LocalDatabaseReady).database;
        expect(await db.piecesDao.countPieces(), 0);
        expect(platform.values[_keyName], isNotNull);
        expect(platform.values[_markerName], '2');
        expect(dbFile().existsSync(), isTrue);
      },
    );

    test(
      'reinstall: key kept, no file — opens fresh with the existing key',
      () async {
        platform.values[_keyName] = _oldPhoneKey;

        final launch = await bootstrap().launch();

        expect(launch, isA<LocalDatabaseReady>());
        expect(platform.values[_keyName], _oldPhoneKey);
        // The fake records which key the file was created with.
        final db = (launch as LocalDatabaseReady).database;
        final row = await db
            .customSelect('SELECT k FROM fake_cipher')
            .getSingle();
        expect(row.read<String>('k'), _oldPhoneKey);
      },
    );

    test('update on the same phone: legacy key + database — hardens the key '
        'and opens', () async {
      await restoreOldPhoneDatabase();
      platform.values[_keyName] = _oldPhoneKey; // no marker: legacy

      final launch = await bootstrap().launch();

      expect(launch, isA<LocalDatabaseReady>());
      final db = (launch as LocalDatabaseReady).database;
      expect(await db.piecesDao.countPieces(), 1);
      expect(platform.values[_keyName], _oldPhoneKey);
      expect(platform.values[_markerName], '2');
    });

    test('already hardened: opens without rewriting the key', () async {
      await restoreOldPhoneDatabase();
      platform.values[_keyName] = _oldPhoneKey;
      platform.values[_markerName] = '2';

      final launch = await bootstrap().launch();

      expect(launch, isA<LocalDatabaseReady>());
      expect(platform.writes, isEmpty);
    });

    test('restore onto a new phone: database present, no key — unreadable, '
        'and no key is created over it', () async {
      await restoreOldPhoneDatabase();
      // The ThisDeviceOnly key did not come along.

      final launch = await bootstrap().launch();

      expect(launch, isA<LocalDatabaseUnreadable>());
      final recovery = (launch as LocalDatabaseUnreadable).recovery;
      expect(recovery.cause, UnreadableDatabaseCause.keyMissing);
      expect(platform.values.containsKey(_keyName), isFalse);
      expect(platform.writes, isEmpty);
      expect(dbFile().existsSync(), isTrue);
    });

    test(
      'a key that does not open the file — unreadable, keyMismatch',
      () async {
        await restoreOldPhoneDatabase();
        platform.values[_keyName] = 'someOtherKey123456789abcdefghijk';
        platform.values[_markerName] = '2';

        final launch = await bootstrap().launch();

        expect(launch, isA<LocalDatabaseUnreadable>());
        expect(
          (launch as LocalDatabaseUnreadable).recovery.cause,
          UnreadableDatabaseCause.keyMismatch,
        );
        expect(dbFile().existsSync(), isTrue);
      },
    );

    test('a file that is not a database at all is keyMismatch too', () async {
      // Real sqlite3, no fake involved: the probe hits SQLITE_NOTADB itself.
      dbFile().writeAsBytesSync(List.filled(8192, 0x41));
      platform.values[_keyName] = _oldPhoneKey;
      platform.values[_markerName] = '2';
      final plain = LocalDatabaseBootstrap(
        keys: keys,
        documentsDir: docs,
        temporaryDir: temp,
        prefs: prefs,
        transferBackup: backup,
        openEncrypted: (file, key) async {
          final db = AppDatabase(NativeDatabase(file));
          opened.add(db);
          return db;
        },
      );

      final launch = await plain.launch();

      expect(launch, isA<LocalDatabaseUnreadable>());
      expect(
        (launch as LocalDatabaseUnreadable).recovery.cause,
        UnreadableDatabaseCause.keyMismatch,
      );
    });

    test('an empty file counts as no database', () async {
      dbFile().createSync();

      final launch = await bootstrap().launch();

      expect(launch, isA<LocalDatabaseReady>());
    });

    test(
      'a key store that cannot be read fails the launch, never recovery',
      () async {
        await restoreOldPhoneDatabase();
        platform.readFailure = PlatformException(
          code: 'interaction-not-allowed',
        );

        await expectLater(
          bootstrap().launch(),
          throwsA(isA<PlatformException>()),
        );
        expect(dbFile().existsSync(), isTrue);
      },
    );

    test(
      'a key store that will not persist the key fails the launch',
      () async {
        platform.writesVanish = true;

        await expectLater(
          bootstrap().launch(),
          throwsA(isA<KeyStorageException>()),
        );
      },
    );

    test(
      'a hardening rewrite that fails to stick still opens the database',
      () async {
        await restoreOldPhoneDatabase();
        platform.values[_keyName] = _oldPhoneKey;
        // The first (hardened) write vanishes; the legacy fallback lands.
        final inner = platform;
        FlutterSecureStoragePlatform.instance = _FirstWriteVanishes(inner);

        final launch = await bootstrap().launch();

        expect(launch, isA<LocalDatabaseReady>());
        expect(inner.values[_keyName], _oldPhoneKey);
        expect(inner.values.containsKey(_markerName), isFalse);
      },
    );
  });

  group('recovery', () {
    late LocalDatabaseRecovery recovery;

    setUp(() async {
      await restoreOldPhoneDatabase();
      // Restored preferences: the old phone had synced this account and had
      // a pull watermark and a queued edit.
      await prefs.setString(SyncService.localDataOwnerKey, 'uid-old');
      await prefs.setBool(SyncService.deviceContestedKey, true);
      await prefs.setString('${SyncService.lastPulledAtPrefix}uid-old', 'x');
      await prefs.setStringList(SyncQueue.storageKey, ['{}']);
      await prefs.setBool(AuthNotifier.onboardingKey, true);
      final launch = await bootstrap().launch();
      recovery = (launch as LocalDatabaseUnreadable).recovery;
    });

    test('reports what came along with the restore', () async {
      expect(recovery.stampedOwnerUid, 'uid-old');
      expect(recovery.hasTransferBackup, isFalse);
      await backup.write(
        databaseKey: _oldPhoneKey,
        passphrase: 'my passphrase',
      );
      expect(recovery.hasTransferBackup, isTrue);
    });

    group('unlockWithPassphrase', () {
      setUp(
        () => backup.write(
          databaseKey: _oldPhoneKey,
          passphrase: 'my passphrase',
        ),
      );

      test(
        'the right passphrase opens the restored pottery in place',
        () async {
          final db = await recovery.unlockWithPassphrase('my passphrase');
          opened.add(db);

          expect(await db.piecesDao.countPieces(), 1);
          expect(platform.values[_keyName], _oldPhoneKey);
          expect(platform.values[_markerName], '2');
          expect(File('${docs.path}/photos/p1/ph1.jpg').existsSync(), isTrue);
          // Ownership and the sign-in flag are untouched: nothing was lost.
          expect(prefs.getString(SyncService.localDataOwnerKey), 'uid-old');
          expect(prefs.getBool(AuthNotifier.onboardingKey), isTrue);
        },
      );

      test('and the next launch is an ordinary one', () async {
        final db = await recovery.unlockWithPassphrase('my passphrase');
        await db.close();

        final launch = await bootstrap().launch();

        expect(launch, isA<LocalDatabaseReady>());
        final reopened = (launch as LocalDatabaseReady).database;
        expect(await reopened.piecesDao.countPieces(), 1);
      });

      test('the wrong passphrase changes nothing', () async {
        await expectLater(
          recovery.unlockWithPassphrase('not it at all'),
          throwsA(isA<WrongTransferPassphraseException>()),
        );
        expect(platform.values.containsKey(_keyName), isFalse);
        expect(dbFile().existsSync(), isTrue);
      });

      test('a backup whose key does not open the database is reported, and '
          'the key is not stored', () async {
        await backup.write(
          databaseKey: 'aKeyFromSomeOtherPhone0123456789',
          passphrase: 'my passphrase',
        );

        await expectLater(
          recovery.unlockWithPassphrase('my passphrase'),
          throwsA(isA<TransferKeyMismatchException>()),
        );
        expect(platform.values.containsKey(_keyName), isFalse);
      });
    });

    test(
      'redownloadFromCloud discards the database but keeps the photo files, '
      'clears ownership and watermarks, and sends the user to sign-in',
      () async {
        await backup.write(
          databaseKey: _oldPhoneKey,
          passphrase: 'a passphrase',
        );
        File('${dbFile().path}-wal').writeAsStringSync('stale wal');

        final db = await recovery.redownloadFromCloud();
        opened.add(db);

        expect(await db.piecesDao.countPieces(), 0);
        expect(File('${dbFile().path}-wal').existsSync(), isFalse);
        expect(backup.exists(), isFalse);
        expect(File('${docs.path}/photos/p1/ph1.jpg').existsSync(), isTrue);
        expect(prefs.getString(SyncService.localDataOwnerKey), isNull);
        expect(prefs.getBool(SyncService.deviceContestedKey), isNull);
        expect(
          prefs.getString('${SyncService.lastPulledAtPrefix}uid-old'),
          isNull,
        );
        expect(prefs.getStringList(SyncQueue.storageKey), isNull);
        expect(prefs.getBool(AuthNotifier.onboardingKey), isFalse);
        expect(platform.values[_keyName], isNotNull);
        expect(platform.values[_markerName], '2');
      },
    );

    test('startFresh discards the photo files as well', () async {
      File('${temp.path}/image_picker_abc.jpg').writeAsStringSync('tmp');

      final db = await recovery.startFresh();
      opened.add(db);

      expect(await db.piecesDao.countPieces(), 0);
      expect(Directory('${docs.path}/photos').existsSync(), isFalse);
      expect(temp.listSync(), isEmpty);
      expect(prefs.getBool(AuthNotifier.onboardingKey), isFalse);
    });

    test('after a discard the next launch is an ordinary one', () async {
      final db = await recovery.startFresh();
      await db.close();
      opened.remove(db);

      final launch = await bootstrap().launch();

      expect(launch, isA<LocalDatabaseReady>());
    });

    test(
      'a discard on a keyMismatch device keeps the key it already had',
      () async {
        platform.values[_keyName] = 'someOtherKey123456789abcdefghijk';
        platform.values[_markerName] = '2';
        final mismatch =
            (await bootstrap().launch() as LocalDatabaseUnreadable).recovery;
        expect(mismatch.cause, UnreadableDatabaseCause.keyMismatch);

        final db = await mismatch.startFresh();
        opened.add(db);

        expect(platform.values[_keyName], 'someOtherKey123456789abcdefghijk');
        expect(await db.piecesDao.countPieces(), 0);
      },
    );
  });
}

/// The first write vanishes; every later one lands. The shape of a hardened
/// rewrite whose delete succeeded and whose add did not.
class _FirstWriteVanishes extends FlutterSecureStoragePlatform
    with MockPlatformInterfaceMixin {
  _FirstWriteVanishes(this._inner);

  final FakeSecureStoragePlatform _inner;
  var _writes = 0;

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _inner.writes.add(RecordedWrite(key, value, Map.of(options)));
    if (_writes++ == 0) {
      _inner.values.remove(key);
      return;
    }
    _inner.values[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) => _inner.read(key: key, options: options);

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) => _inner.containsKey(key: key, options: options);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) => _inner.delete(key: key, options: options);

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) =>
      _inner.readAll(options: options);

  @override
  Future<void> deleteAll({required Map<String, String> options}) =>
      _inner.deleteAll(options: options);
}
