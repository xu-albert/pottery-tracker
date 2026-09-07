import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/sqlcipher_guard.dart';
import 'package:pottery_tracker/database/transfer_key_backup.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

import '../helpers/fake_sqlcipher.dart';

const _dbKey = 'theDatabaseKey0123456789abcdefXY';

void main() {
  late Directory docs;
  late TransferKeyBackup backup;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('transfer_key_backup_');
    backup = TransferKeyBackup(documentsDir: docs, keyDatabase: fakeSqlCipher);
  });

  tearDown(() => docs.deleteSync(recursive: true));

  test('lives next to the database under its documented name', () {
    expect(
      TransferKeyBackup.fileFor(docs).path,
      '${docs.path}/pottery_tracker_transfer_key.db',
    );
    expect(backup.exists(), isFalse);
  });

  test('round-trips the key under the passphrase', () async {
    await backup.write(databaseKey: _dbKey, passphrase: 'correct horse');
    expect(backup.exists(), isTrue);
    expect(await backup.read('correct horse'), _dbKey);
  });

  test('the wrong passphrase is reported as such, not as corruption', () async {
    await backup.write(databaseKey: _dbKey, passphrase: 'correct horse');
    await expectLater(
      backup.read('battery staple'),
      throwsA(isA<WrongTransferPassphraseException>()),
    );
  });

  test(
    'writing again replaces the passphrase — there is only ever one',
    () async {
      await backup.write(databaseKey: _dbKey, passphrase: 'first phrase');
      await backup.write(databaseKey: _dbKey, passphrase: 'second phrase');
      expect(await backup.read('second phrase'), _dbKey);
      await expectLater(
        backup.read('first phrase'),
        throwsA(isA<WrongTransferPassphraseException>()),
      );
    },
  );

  test(
    'refuses a passphrase shorter than the floor and writes nothing',
    () async {
      await expectLater(
        backup.write(databaseKey: _dbKey, passphrase: 'short'),
        throwsA(isA<ArgumentError>()),
      );
      expect(backup.exists(), isFalse);
      expect(TransferKeyBackup.minPassphraseLength, 8);
    },
  );

  test('a keying failure leaves no half-written file behind', () async {
    final refusing = TransferKeyBackup(
      documentsDir: docs,
      keyDatabase: (_, _) => throw const SqlCipherUnavailableException(),
    );
    await expectLater(
      refusing.write(databaseKey: _dbKey, passphrase: 'correct horse'),
      throwsA(isA<SqlCipherUnavailableException>()),
    );
    expect(refusing.exists(), isFalse);
    expect(docs.listSync(), isEmpty);
  });

  test('a write that sqlite3 refuses never reports the key it was '
      'binding', () async {
    // sqlite3 attaches a failing statement and its bound parameters to the
    // exception and prints both, and the sheet shows whatever comes out of
    // here — so the key must not survive the trip.
    final failing = TransferKeyBackup(
      documentsDir: docs,
      openSqlite: (_) => _FullDisk(),
      keyDatabase: (_, _) {},
    );

    Object? thrown;
    try {
      await failing.write(databaseKey: _dbKey, passphrase: 'correct horse');
    } catch (e) {
      thrown = e;
    }

    expect(thrown, isA<SqliteException>());
    expect((thrown! as SqliteException).extendedResultCode, 13);
    expect(thrown.toString(), contains('database or disk is full'));
    expect(thrown.toString(), isNot(contains(_dbKey)));
    expect(docs.listSync(), isEmpty);
  });

  test(
    'a change that fails partway keeps the previous passphrase working',
    () async {
      await backup.write(databaseKey: _dbKey, passphrase: 'first phrase');
      final refusing = TransferKeyBackup(
        documentsDir: docs,
        keyDatabase: (_, _) => throw const SqlCipherUnavailableException(),
      );

      await expectLater(
        refusing.write(databaseKey: _dbKey, passphrase: 'second phrase'),
        throwsA(isA<SqlCipherUnavailableException>()),
      );

      expect(backup.exists(), isTrue);
      expect(await backup.read('first phrase'), _dbKey);
      expect(docs.listSync().map((f) => f.path.split('/').last), [
        TransferKeyBackup.fileName,
      ]);
    },
  );

  test('a replacement only takes the old backup\'s place once it holds the '
      'key', () async {
    await backup.write(databaseKey: _dbKey, passphrase: 'first phrase');
    final finalFile = TransferKeyBackup.fileFor(docs);
    final before = finalFile.lastModifiedSync();
    String? finalDuringWrite;
    final observing = TransferKeyBackup(
      documentsDir: docs,
      keyDatabase: (db, key) {
        fakeSqlCipher(db, key);
        finalDuringWrite = finalFile.existsSync()
            ? finalFile.lastModifiedSync().toIso8601String()
            : null;
      },
    );

    await observing.write(databaseKey: _dbKey, passphrase: 'second phrase');

    expect(finalDuringWrite, before.toIso8601String());
    expect(await backup.read('second phrase'), _dbKey);
  });

  test('the production keyer refuses to write when SQLCipher is not what '
      'loaded, and leaves nothing behind', () async {
    // `flutter test` runs on plain sqlite3, so the guard's probe finds no
    // cipher and refuses — which is exactly what must happen on a build
    // where SQLCipher did not load, rather than a key written in the clear.
    final production = TransferKeyBackup(documentsDir: docs);

    await expectLater(
      production.write(databaseKey: _dbKey, passphrase: 'correct horse'),
      throwsA(isA<SqlCipherUnavailableException>()),
    );

    expect(production.exists(), isFalse);
    expect(docs.listSync(), isEmpty);
  });

  test('reading a missing backup is a programming error, not a wrong key', () {
    expect(backup.read('anything at all'), throwsA(isA<StateError>()));
  });

  test(
    'delete removes the file; deleteIn does the same without an instance',
    () async {
      await backup.write(databaseKey: _dbKey, passphrase: 'correct horse');
      await backup.delete();
      expect(backup.exists(), isFalse);
      await backup.delete(); // idempotent

      await backup.write(databaseKey: _dbKey, passphrase: 'correct horse');
      await TransferKeyBackup.deleteIn(docs);
      expect(backup.exists(), isFalse);

      // A replacement that never finished goes with them.
      File(
        '${TransferKeyBackup.fileFor(docs).path}.tmp',
      ).writeAsStringSync('x');
      await backup.delete();
      expect(docs.listSync(), isEmpty);
      File(
        '${TransferKeyBackup.fileFor(docs).path}.tmp',
      ).writeAsStringSync('x');
      await TransferKeyBackup.deleteIn(docs);
      expect(docs.listSync(), isEmpty);
    },
  );

  test(
    'a real plain-sqlite file that is not a database reads as NOTADB',
    () async {
      // With the real sqlite3 and no keyer, garbage in the file surfaces as
      // SQLITE_NOTADB on the first read — the same code SQLCipher uses for a
      // wrong key, which is why the read path maps it to a wrong passphrase.
      TransferKeyBackup.fileFor(docs).writeAsBytesSync(List.filled(4096, 0x41));
      final unkeyed = TransferKeyBackup(
        documentsDir: docs,
        keyDatabase: (_, _) {},
      );
      await expectLater(
        unkeyed.read('irrelevant'),
        throwsA(isA<WrongTransferPassphraseException>()),
      );
    },
  );

  group('isNotADatabase', () {
    test('recognises SQLITE_NOTADB as sqlite3 raises it', () {
      expect(
        isNotADatabase(SqliteException(26, 'file is not a database')),
        isTrue,
      );
    });

    test('is false for other sqlite errors and unrelated exceptions', () {
      expect(isNotADatabase(SqliteException(1, 'generic')), isFalse);
      expect(isNotADatabase(StateError('nope')), isFalse);
    });

    test('recognises the code the real sqlite3 raises on garbage', () {
      final path = '${docs.path}/garbage.db';
      File(path).writeAsBytesSync(List.filled(4096, 0x41));
      final db = sqlite3.open(path);
      Object? caught;
      try {
        db.select('SELECT count(*) FROM sqlite_master');
      } catch (e) {
        caught = e;
      } finally {
        db.dispose();
      }
      expect(caught, isNotNull);
      expect(isNotADatabase(caught!), isTrue);
    });
  });

  test('fakeSqlCipher fails the way SQLCipher does on a wrong key', () {
    // Guards the fake the bootstrap tests lean on.
    final path = '${docs.path}/fake.db';
    final a = sqlite3.open(path);
    fakeSqlCipher(a, 'right');
    a.dispose();
    final b = sqlite3.open(path);
    expect(
      () => fakeSqlCipher(b, 'wrong'),
      throwsA(
        isA<SqliteException>().having((e) => e.resultCode, 'resultCode', 26),
      ),
    );
    b.dispose();
    final c = sqlite3.open(path);
    expect(() => fakeSqlCipher(c, 'right'), returnsNormally);
    c.dispose();
  });

  test('CommonDatabase is what the keyer receives', () async {
    CommonDatabase? seen;
    final spy = TransferKeyBackup(
      documentsDir: docs,
      keyDatabase: (db, key) {
        seen = db;
        fakeSqlCipher(db, key);
      },
    );
    await spy.write(databaseKey: _dbKey, passphrase: 'correct horse');
    expect(seen, isNotNull);
  });
}

/// A database that fails the one statement binding the key, the way sqlite3
/// reports a full disk: with the statement and its parameters attached.
class _FullDisk implements CommonDatabase {
  @override
  void execute(String sql, [List<Object?> parameters = const []]) {
    if (!sql.startsWith('INSERT')) return;
    throw SqliteException(
      13,
      'database or disk is full',
      null,
      sql,
      parameters,
    );
  }

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
