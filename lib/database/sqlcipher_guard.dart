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

/// Thrown when sqlite3 rejects the keying statement itself.
///
/// Distinct from [SqlCipherUnavailableException]: SQLCipher may well be
/// present, the key just could not be applied. The sqlite3 result code and
/// message are preserved, but the statement that caused them never is — it
/// contains the database key, and this error is rendered on screen and
/// reported to Crashlytics.
class SqlCipherKeyingException implements Exception {
  const SqlCipherKeyingException({
    required this.extendedResultCode,
    required this.message,
  });

  /// The sqlite3 extended result code of the underlying failure.
  final int extendedResultCode;

  /// The underlying failure's description, with any key material removed.
  final String message;

  @override
  String toString() =>
      'SqlCipherKeyingException($extendedResultCode): $message '
      '(causing statement withheld — it carries the database key)';
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
  final version = (firstRow == null || firstRow.isEmpty)
      ? null
      : firstRow.first;

  if (version != null && version.toString().trim().isNotEmpty) return;

  throw const SqlCipherUnavailableException();
}

/// Keys [db] and then refuses to hand back a connection that is not encrypted.
///
/// The two statements belong together: `PRAGMA key` is silently ignored by a
/// plain sqlite3 build, so without the probe that follows it the database would
/// be created in the clear with nothing to signal it.
///
/// sqlite3 offers no way to bind [key] as a parameter — its pragma parser
/// rejects `PRAGMA key = ?` at prepare time — so the key has to be a literal,
/// and every sqlite3 failure of that one statement is rewritten into a
/// [SqlCipherKeyingException] that cannot carry it. Anything else thrown here,
/// including from the probe, propagates untouched.
void configureSqlCipher(CommonDatabase db, String key) {
  try {
    db.execute('PRAGMA key = ${sqlKeyLiteral(key)}');
  } on SqliteException catch (error) {
    throw keyingFailure(error, key);
  }

  assertSqlCipherBacksSqlite3(db.select('PRAGMA cipher_version').rows);
}

/// [key] as the SQL string literal a keying pragma needs — sqlite3 cannot
/// bind one, so the key has to be quoted into the statement.
String sqlKeyLiteral(String key) => "'${key.replaceAll("'", "''")}'";

/// A sqlite3 failure of a statement that quotes [key], rewritten into a
/// [SqlCipherKeyingException] that cannot carry it.
///
/// sqlite3 attaches the failing statement to its exception and prints it, so
/// the original must never reach a log, the screen or Crashlytics. Shared by
/// [configureSqlCipher] and `AppDatabase.rekey`.
SqlCipherKeyingException keyingFailure(SqliteException error, String key) =>
    SqlCipherKeyingException(
      extendedResultCode: error.extendedResultCode,
      message: _withoutKeyMaterial(
        [error.message, error.explanation].whereType<String>().join(', '),
        key,
      ),
    );

const _withheldMessage =
    'sqlite3 rejected the keying statement; its description is withheld '
    'because it quotes the database key';

String _withoutKeyMaterial(String text, String key) {
  final redacted = text.replaceAll(key, '<redacted>');
  return _containsFragmentOf(redacted, key) ? _withheldMessage : redacted;
}

bool _containsFragmentOf(String text, String key, {int shortestRun = 8}) {
  if (key.isEmpty) return false;
  if (key.length <= shortestRun) return text.contains(key);

  for (var start = 0; start + shortestRun <= key.length; start++) {
    if (text.contains(key.substring(start, start + shortestRun))) return true;
  }
  return false;
}
