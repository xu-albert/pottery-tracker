import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pottery_tracker/database/sqlcipher_guard.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;
import 'package:sqlite3/sqlite3.dart';

class _RecordingDatabase extends Mock implements CommonDatabase {}

void main() {
  group('assertSqlCipherBacksSqlite3', () {
    test('accepts the version string SQLCipher reports', () {
      expect(
        () => assertSqlCipherBacksSqlite3([
          ['4.10.0 community'],
        ]),
        returnsNormally,
      );
    });

    test('accepts any non-blank version, not one specific release', () {
      for (final version in ['4.5.7', '4.10.0 community', '5.0.0', '9.9.9']) {
        expect(
          () => assertSqlCipherBacksSqlite3([
            [version],
          ]),
          returnsNormally,
          reason: '$version must not be rejected',
        );
      }
    });

    test('throws when the probe returned no rows at all', () {
      expect(
        () => assertSqlCipherBacksSqlite3(const []),
        throwsA(isA<SqlCipherUnavailableException>()),
      );
    });

    test('throws when the probe row is empty', () {
      expect(
        () => assertSqlCipherBacksSqlite3(const [[]]),
        throwsA(isA<SqlCipherUnavailableException>()),
      );
    });

    test('throws when the reported version is null or blank', () {
      for (final value in [null, '', '   ']) {
        expect(
          () => assertSqlCipherBacksSqlite3([
            [value],
          ]),
          throwsA(isA<SqlCipherUnavailableException>()),
          reason: '${value == null ? 'null' : '"$value"'} must be rejected',
        );
      }
    });

    test('says plainly that the database is not encrypted', () {
      final message = const SqlCipherUnavailableException().toString();
      expect(message, contains('NOT encrypted'));
      expect(message.toLowerCase(), contains('sqlcipher'));
    });
  });

  group('against a real plain-sqlite3 build', () {
    late Database rawDb;

    setUp(() => rawDb = sqlite3.openInMemory());
    tearDown(() => rawDb.dispose());

    test('PRAGMA key is silently ignored — the failure this guard catches', () {
      expect(
        () => rawDb.execute("PRAGMA key = 'not-a-real-key'"),
        returnsNormally,
      );
      expect(rawDb.select('PRAGMA cipher_version').rows, isEmpty);
    });

    test('the guard turns that silent plaintext outcome into a throw', () {
      rawDb.execute("PRAGMA key = 'not-a-real-key'");

      expect(
        () => assertSqlCipherBacksSqlite3(
          rawDb.select('PRAGMA cipher_version').rows,
        ),
        throwsA(isA<SqlCipherUnavailableException>()),
      );
    });

    test('the thrown message never carries the encryption key', () {
      const key = 'super-secret-encryption-key-value';
      rawDb.execute("PRAGMA key = '$key'");

      Object? thrown;
      try {
        assertSqlCipherBacksSqlite3(rawDb.select('PRAGMA cipher_version').rows);
      } catch (error) {
        thrown = error;
      }

      expect(thrown, isA<SqlCipherUnavailableException>());
      expect(thrown.toString(), isNot(contains(key)));
      expect(thrown.toString(), isNot(contains('super-secret')));
    });
  });

  group('configureSqlCipher', () {
    test('rejects a real plain-sqlite3 connection it just tried to key', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);

      expect(
        () => configureSqlCipher(db, 'not-a-real-key'),
        throwsA(isA<SqlCipherUnavailableException>()),
      );
    });

    test('never names the key it was given when it refuses', () {
      const key = 'super-secret-encryption-key-value';
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);

      Object? thrown;
      try {
        configureSqlCipher(db, key);
      } catch (error) {
        thrown = error;
      }

      expect(thrown, isA<SqlCipherUnavailableException>());
      expect(thrown.toString(), isNot(contains(key)));
    });

    test('keys the connection first, then probes for SQLCipher', () {
      final db = _RecordingDatabase();
      when(() => db.execute(any())).thenAnswer((_) {});
      when(() => db.select(any())).thenReturn(
        ResultSet(
          ['cipher_version'],
          null,
          [
            ['4.10.0 community'],
          ],
        ),
      );

      expect(() => configureSqlCipher(db, 'k3y'), returnsNormally);

      verifyInOrder([
        () => db.execute("PRAGMA key = 'k3y'"),
        () => db.select('PRAGMA cipher_version'),
      ]);
    });

    test('still refuses when a keyed connection reports no cipher version', () {
      final db = _RecordingDatabase();
      when(() => db.execute(any())).thenAnswer((_) {});
      when(() => db.select(any()))
          .thenReturn(ResultSet(['cipher_version'], null, const []));

      expect(
        () => configureSqlCipher(db, 'k3y'),
        throwsA(isA<SqlCipherUnavailableException>()),
      );
      verify(() => db.execute("PRAGMA key = 'k3y'")).called(1);
    });
  });
}
