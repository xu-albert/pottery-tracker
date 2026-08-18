import 'package:sqlite3/common.dart';

/// Thrown when the sqlite3 library backing the app is not SQLCipher, which
/// means `PRAGMA key` was silently ignored and the database is plaintext.
class SqlCipherUnavailableException implements Exception {
  const SqlCipherUnavailableException();

  @override
  String toString() =>
      'SqlCipherUnavailableException: the local database is NOT encrypted. '
      'SQLCipher is not backing sqlite3 — PRAGMA cipher_version reported no '
      'version, so PRAGMA key was silently ignored. Continuing would store '
      'every piece, photo and note in the clear.';
}

/// Verifies that SQLCipher, and not plain sqlite3, answered the
/// `PRAGMA cipher_version` probe.
///
/// [cipherVersionRows] is the raw row data of that probe. SQLCipher answers
/// with a single row holding its version string; plain sqlite3 ignores the
/// unknown pragma and yields no rows at all. Any non-blank version passes —
/// the question is whether SQLCipher is present, never which release it is.
void assertSqlCipherBacksSqlite3(List<List<Object?>> cipherVersionRows) {
  final firstRow = cipherVersionRows.isEmpty ? null : cipherVersionRows.first;
  final version = (firstRow == null || firstRow.isEmpty) ? null : firstRow.first;

  if (version != null && version.toString().trim().isNotEmpty) return;

  throw const SqlCipherUnavailableException();
}

/// Keys [db] and then refuses to hand back a connection that is not encrypted.
///
/// The two statements belong together: `PRAGMA key` is silently ignored by a
/// plain sqlite3 build, so without the probe that follows it the database would
/// be created in the clear with nothing to signal it.
void configureSqlCipher(CommonDatabase db, String key) {
  db.execute("PRAGMA key = '$key'");
  assertSqlCipherBacksSqlite3(db.select('PRAGMA cipher_version').rows);
}
