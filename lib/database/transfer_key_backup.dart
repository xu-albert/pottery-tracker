import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

import 'sqlcipher_guard.dart';

/// Thrown when the passphrase does not open the transfer backup.
class WrongTransferPassphraseException implements Exception {
  const WrongTransferPassphraseException();

  @override
  String toString() =>
      'WrongTransferPassphraseException: the passphrase does not open the '
      'transfer backup';
}

/// The one file the database key is allowed to leave the keychain for, and
/// the only thing that lets pottery kept on this phone alone survive a move
/// to a new phone.
///
/// The key itself is stored under `ThisDeviceOnly` protections and so never
/// enters a backup — that is the hardening, and it is what makes a restored
/// database unreadable. This file is the migration path for a user with no
/// cloud account to re-pull from: a second SQLCipher database in `Documents/`
/// (backed up alongside the real one) holding a single row with the key, and
/// keyed with a passphrase the user chose. SQLCipher derives the file key
/// from the passphrase with its own PBKDF2-HMAC-SHA512 (256,000 rounds in
/// SQLCipher 4) and authenticates every page, so the wrapping uses the same
/// vetted cipher the pottery does and adds no dependency.
///
/// It is written only when the user sets a passphrase, so a user who never
/// does has nothing extra on disk. What the file protects the key with is
/// exactly the passphrase's strength against an offline guess by whoever
/// holds the backup, which is why [minPassphraseLength] exists and why the
/// settings copy asks for a passphrase rather than a PIN.
///
/// Opened through [configureSqlCipher] like the real database, so on a build
/// where SQLCipher did not load this refuses rather than writing the key in
/// the clear.
class TransferKeyBackup {
  /// Sits next to `pottery_tracker.db`; both are backed up, and the erase
  /// paths that delete one delete the other.
  static const fileName = 'pottery_tracker_transfer_key.db';

  /// The shortest passphrase accepted. Eight is a floor, not a
  /// recommendation; the settings sheet says so.
  static const minPassphraseLength = 8;

  final File _file;
  final CommonDatabase Function(String path) _openSqlite;
  final void Function(CommonDatabase db, String key) _keyDatabase;

  /// [openSqlite] and [keyDatabase] are injectable so the file's own logic
  /// can be tested against plain sqlite3, where SQLCipher is not available to
  /// `flutter test`. Production uses the real pair.
  TransferKeyBackup({
    required Directory documentsDir,
    CommonDatabase Function(String path)? openSqlite,
    void Function(CommonDatabase db, String key)? keyDatabase,
  }) : _file = fileFor(documentsDir),
       _openSqlite = openSqlite ?? sqlite3.open,
       _keyDatabase = keyDatabase ?? configureSqlCipher;

  static File fileFor(Directory documentsDir) =>
      File(p.join(documentsDir.path, fileName));

  /// Where a replacement is written before it takes the backup's place.
  static File _stagingFor(File file) => File('${file.path}.tmp');

  /// Removes the backup at [documentsDir], for erase paths that have no
  /// instance — the file must go wherever the database it unlocks goes.
  static Future<void> deleteIn(Directory documentsDir) async {
    _deleteFiles(fileFor(documentsDir));
  }

  static void _deleteFiles(File file) {
    for (final f in [file, _stagingFor(file)]) {
      if (f.existsSync()) f.deleteSync();
    }
  }

  bool exists() => _file.existsSync();

  /// Writes [databaseKey] wrapped under [passphrase], replacing any earlier
  /// backup — there is only ever one passphrase.
  ///
  /// The replacement is built next to the backup and renamed over it only
  /// once the key is inside, so a change that fails partway leaves the
  /// previous passphrase working rather than no backup at all.
  Future<void> write({
    required String databaseKey,
    required String passphrase,
  }) async {
    if (passphrase.length < minPassphraseLength) {
      throw ArgumentError.value(
        passphrase.length,
        'passphrase',
        'must be at least $minPassphraseLength characters',
      );
    }
    final staging = _stagingFor(_file);
    if (staging.existsSync()) staging.deleteSync();

    final db = _openSqlite(staging.path);
    try {
      _keyDatabase(db, passphrase);
      db.execute(
        'CREATE TABLE transfer_key ('
        'id INTEGER PRIMARY KEY CHECK (id = 1), '
        'database_key TEXT NOT NULL)',
      );
      db.execute('INSERT INTO transfer_key (id, database_key) VALUES (1, ?)', [
        databaseKey,
      ]);
    } catch (error) {
      // A half-written backup would read as "you have a passphrase" and then
      // fail to open on the new phone, which is worse than having none.
      db.dispose();
      if (staging.existsSync()) staging.deleteSync();
      if (error is SqliteException) throw _withoutBoundParameters(error);
      rethrow;
    }
    db.dispose();
    staging.renameSync(_file.path);
  }

  /// The database key the backup holds, if [passphrase] opens it.
  ///
  /// Throws [WrongTransferPassphraseException] when it does not. SQLCipher
  /// signals a wrong key the same way plain sqlite3 signals a file that is
  /// not a database at all — `SQLITE_NOTADB` on the first read — because
  /// without the right key the header does not decrypt to one.
  Future<String> read(String passphrase) async {
    if (!_file.existsSync()) {
      throw StateError('no transfer backup at ${_file.path}');
    }
    final db = _openSqlite(_file.path);
    try {
      _keyDatabase(db, passphrase);
      final rows = db.select(
        'SELECT database_key FROM transfer_key WHERE id = 1',
      );
      if (rows.isEmpty) {
        throw StateError('the transfer backup holds no key');
      }
      return rows.first['database_key'] as String;
    } on SqliteException catch (e) {
      if (isNotADatabase(e)) throw const WrongTransferPassphraseException();
      rethrow;
    } finally {
      db.dispose();
    }
  }

  /// Synchronous inside on purpose: the file is tiny, and a caller that runs
  /// under a widget test's fake clock still sees the result the moment the
  /// future completes.
  Future<void> delete() async {
    _deleteFiles(_file);
  }
}

/// The same sqlite3 failure without the statement that caused it.
///
/// sqlite3 attaches a failing statement's bound parameters to its exception
/// and prints them, and the one statement here that binds anything binds the
/// database key. This error is rethrown to a caller that shows it, so the key
/// is stripped for the same reason [SqlCipherKeyingException] exists.
SqliteException _withoutBoundParameters(SqliteException error) =>
    SqliteException(
      error.extendedResultCode,
      error.message,
      error.explanation,
      null,
      null,
      error.operation,
    );

/// Whether [error] is sqlite3 reporting `SQLITE_NOTADB` (26): the file is
/// not a database — or, under SQLCipher, not one this key opens.
///
/// Drift's same-isolate `NativeDatabase` lets the executor's exception
/// through as sqlite3 raised it, so that is the only shape to recognise.
bool isNotADatabase(Object error) {
  const sqliteNotADb = 26;
  if (error is SqliteException) {
    return error.extendedResultCode == sqliteNotADb ||
        error.resultCode == sqliteNotADb;
  }
  return false;
}
