import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/database/sqlcipher_guard.dart';

const _key = 'rotatedKey0123456789abcdefghijkl';

/// Fails the rekey the way sqlite3 does: with the statement — which quotes
/// the key — attached to the exception, and the key in its explanation.
class _FailsRekey extends QueryInterceptor {
  _FailsRekey({required this.wrappedByDrift});

  final bool wrappedByDrift;

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (!statement.startsWith('PRAGMA rekey')) {
      return super.runCustom(executor, statement, args);
    }
    final error = SqliteException(
      26,
      'file is not a database',
      'could not rekey with $_key',
      statement,
    );
    if (wrappedByDrift) {
      throw DriftWrappedException(
        message: 'Could not run $statement',
        cause: error,
        trace: StackTrace.current,
      );
    }
    throw error;
  }
}

void main() {
  for (final wrapped in const [false, true]) {
    test(
      'a failed rekey never reports the key '
      '(${wrapped ? "wrapped by drift" : "raw sqlite3"})',
      () async {
        final db = AppDatabase.forTesting(
          NativeDatabase.memory().interceptWith(
            _FailsRekey(wrappedByDrift: wrapped),
          ),
        );
        addTearDown(db.close);

        Object? thrown;
        try {
          await db.rekey(_key);
        } catch (e) {
          thrown = e;
        }

        expect(thrown, isA<SqlCipherKeyingException>());
        final keying = thrown as SqlCipherKeyingException;
        expect(keying.extendedResultCode, 26);
        expect(keying.message, contains('<redacted>'));
        expect(keying.toString(), isNot(contains(_key)));
        expect(keying.toString(), isNot(contains(_key.substring(4, 12))));
      },
    );
  }

  test('a rekey that sqlite3 accepts runs the statement as given', () async {
    final seen = <String>[];
    final db = AppDatabase.forTesting(
      NativeDatabase.memory().interceptWith(_Recording(seen)),
    );
    addTearDown(db.close);

    await db.rekey("it's");

    expect(seen, ["PRAGMA rekey = 'it''s'"]);
  });
}

class _Recording extends QueryInterceptor {
  _Recording(this.seen);

  final List<String> seen;

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.startsWith('PRAGMA rekey')) seen.add(statement);
    return super.runCustom(executor, statement, args);
  }
}
