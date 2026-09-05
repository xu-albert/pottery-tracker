import 'package:sqlite3/common.dart';

/// Stands in for `configureSqlCipher` on plain sqlite3, where `flutter test`
/// has no SQLCipher.
///
/// It behaves the way SQLCipher does at the seam the code under test cares
/// about: the first keying of a fresh file "encrypts" it with [key] (here, by
/// recording the key in a side table), and keying an existing file with a
/// different key fails on the first read with `SQLITE_NOTADB` (26) — which is
/// exactly what a wrong SQLCipher key produces, since the header no longer
/// decrypts to a database.
void fakeSqlCipher(CommonDatabase db, String key) {
  final marked = db
      .select("SELECT name FROM sqlite_master WHERE name = 'fake_cipher'")
      .isNotEmpty;
  if (!marked) {
    db.execute('CREATE TABLE fake_cipher (k TEXT NOT NULL)');
    db.execute('INSERT INTO fake_cipher (k) VALUES (?)', [key]);
    return;
  }
  final stored = db.select('SELECT k FROM fake_cipher').first['k'] as String;
  if (stored != key) {
    throw SqliteException(26, 'file is not a database');
  }
}
