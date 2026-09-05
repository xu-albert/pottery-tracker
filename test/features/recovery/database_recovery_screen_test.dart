import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart' show CupertinoAlertDialog;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/database/local_database_bootstrap.dart';
import 'package:pottery_tracker/database/transfer_key_backup.dart';
import 'package:pottery_tracker/features/recovery/pre_launch_app.dart';
import 'package:pottery_tracker/features/recovery/screens/database_recovery_screen.dart';
import 'package:pottery_tracker/l10n/app_localizations_en.dart';

final _l10n = AppLocalizationsEn();

class _FakeRecovery implements LocalDatabaseRecovery {
  _FakeRecovery({
    this.cause = UnreadableDatabaseCause.keyMissing,
    this.hasTransferBackup = false,
    this.stampedOwnerUid,
    this.failure,
  });

  @override
  final UnreadableDatabaseCause cause;
  @override
  final bool hasTransferBackup;
  @override
  final String? stampedOwnerUid;
  static const passphrase = 'correct horse';

  /// When set, every action throws it.
  final Object? failure;

  final calls = <String>[];
  final List<AppDatabase> handedOut = [];

  Future<AppDatabase> _open() async {
    if (failure != null) throw failure!;
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    handedOut.add(db);
    return db;
  }

  @override
  Future<AppDatabase> unlockWithPassphrase(String passphrase) async {
    calls.add('unlock:$passphrase');
    if (passphrase == 'right key wrong db') {
      throw const TransferKeyMismatchException();
    }
    if (passphrase != _FakeRecovery.passphrase) {
      throw const WrongTransferPassphraseException();
    }
    return _open();
  }

  @override
  Future<AppDatabase> redownloadFromCloud() {
    calls.add('redownload');
    return _open();
  }

  @override
  Future<AppDatabase> startFresh() {
    calls.add('startFresh');
    return _open();
  }
}

void main() {
  late List<AppDatabase> recovered;

  setUp(() => recovered = []);

  tearDown(() async {
    for (final db in recovered) {
      await db.close();
    }
  });

  Future<void> pump(WidgetTester tester, _FakeRecovery recovery) async {
    await tester.pumpWidget(
      PreLaunchApp(
        child: DatabaseRecoveryScreen(
          recovery: recovery,
          onRecovered: (db) async => recovered.add(db),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      for (final db in recovery.handedOut) {
        if (!recovered.contains(db)) await db.close();
      }
    });
  }

  Future<void> confirmDialog(WidgetTester tester, String action) async {
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  group('what it says', () {
    testWidgets('a restore with no key: the backup explanation', (
      tester,
    ) async {
      await pump(tester, _FakeRecovery());
      expect(find.text(_l10n.recoveryTitle), findsOneWidget);
      expect(find.text(_l10n.recoveryMessageKeyMissing), findsOneWidget);
      expect(find.text(_l10n.recoveryMessageKeyMismatch), findsNothing);
    });

    testWidgets('a key that does not fit: the mismatch explanation', (
      tester,
    ) async {
      await pump(
        tester,
        _FakeRecovery(cause: UnreadableDatabaseCause.keyMismatch),
      );
      expect(find.text(_l10n.recoveryMessageKeyMismatch), findsOneWidget);
    });

    testWidgets(
      'local-only, no backup: says the pieces cannot be recovered here and '
      'offers only a fresh start',
      (tester) async {
        await pump(tester, _FakeRecovery());
        expect(find.text(_l10n.recoveryLocalOnlyHint), findsOneWidget);
        expect(find.text(_l10n.recoveryCloudHint), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(find.text(_l10n.recoveryRedownload), findsNothing);
        expect(find.text(_l10n.recoveryStartFresh), findsOneWidget);
      },
    );

    testWidgets('a synced account: says the pieces are in the cloud and makes '
        're-downloading the primary action', (tester) async {
      await pump(tester, _FakeRecovery(stampedOwnerUid: 'uid'));
      expect(find.text(_l10n.recoveryCloudHint), findsOneWidget);
      expect(find.text(_l10n.recoveryLocalOnlyHint), findsNothing);
      expect(
        find.widgetWithText(FilledButton, _l10n.recoveryRedownload),
        findsOneWidget,
      );
      expect(find.text(_l10n.recoveryStartFresh), findsOneWidget);
    });

    testWidgets(
      'a transfer backup: the passphrase field leads, and re-downloading '
      'steps down to secondary',
      (tester) async {
        await pump(
          tester,
          _FakeRecovery(hasTransferBackup: true, stampedOwnerUid: 'uid'),
        );
        expect(find.text(_l10n.recoveryPassphraseSection), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, _l10n.recoveryUnlock),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(OutlinedButton, _l10n.recoveryRedownload),
          findsOneWidget,
        );
      },
    );
  });

  group('unlocking with the passphrase', () {
    testWidgets('the right passphrase hands the database to the app', (
      tester,
    ) async {
      final recovery = _FakeRecovery(hasTransferBackup: true);
      await pump(tester, recovery);

      await tester.enterText(find.byType(TextField), 'correct horse');
      await tester.tap(find.text(_l10n.recoveryUnlock));
      await tester.pumpAndSettle();

      expect(recovery.calls, ['unlock:correct horse']);
      expect(recovered, hasLength(1));
    });

    testWidgets('the wrong passphrase is an inline error, and nothing moves', (
      tester,
    ) async {
      final recovery = _FakeRecovery(hasTransferBackup: true);
      await pump(tester, recovery);

      await tester.enterText(find.byType(TextField), 'nope');
      await tester.tap(find.text(_l10n.recoveryUnlock));
      await tester.pumpAndSettle();

      expect(find.text(_l10n.recoveryWrongPassphrase), findsOneWidget);
      expect(recovered, isEmpty);
      // Still here, still usable.
      expect(find.text(_l10n.recoveryUnlock), findsOneWidget);
    });

    testWidgets('a backup whose key does not fit says so', (tester) async {
      final recovery = _FakeRecovery(hasTransferBackup: true);
      await pump(tester, recovery);

      await tester.enterText(find.byType(TextField), 'right key wrong db');
      await tester.tap(find.text(_l10n.recoveryUnlock));
      await tester.pumpAndSettle();

      expect(find.text(_l10n.recoveryTransferKeyMismatch), findsOneWidget);
      expect(recovered, isEmpty);
    });

    testWidgets('submitting the field unlocks too', (tester) async {
      final recovery = _FakeRecovery(hasTransferBackup: true);
      await pump(tester, recovery);

      await tester.enterText(find.byType(TextField), 'correct horse');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(recovered, hasLength(1));
    });
  });

  group('re-downloading', () {
    testWidgets('asks first, and cancelling does nothing', (tester) async {
      final recovery = _FakeRecovery(stampedOwnerUid: 'uid');
      await pump(tester, recovery);

      await tester.tap(find.text(_l10n.recoveryRedownload));
      await tester.pumpAndSettle();
      expect(find.text(_l10n.recoveryRedownloadConfirmTitle), findsOneWidget);
      expect(find.text(_l10n.recoveryRedownloadConfirmMessage), findsOneWidget);
      await confirmDialog(tester, _l10n.cancel);

      expect(recovery.calls, isEmpty);
      expect(recovered, isEmpty);
    });

    testWidgets('confirming discards and hands over the fresh database', (
      tester,
    ) async {
      final recovery = _FakeRecovery(stampedOwnerUid: 'uid');
      await pump(tester, recovery);

      await tester.tap(find.text(_l10n.recoveryRedownload));
      await tester.pumpAndSettle();
      await confirmDialog(tester, _l10n.recoveryRedownloadConfirm);

      expect(recovery.calls, ['redownload']);
      expect(recovered, hasLength(1));
    });
  });

  group('starting fresh', () {
    testWidgets('warns that it deletes, and cancelling does nothing', (
      tester,
    ) async {
      final recovery = _FakeRecovery();
      await pump(tester, recovery);

      await tester.tap(find.text(_l10n.recoveryStartFresh));
      await tester.pumpAndSettle();
      expect(find.text(_l10n.recoveryStartFreshConfirmTitle), findsOneWidget);
      expect(find.text(_l10n.recoveryStartFreshConfirmMessage), findsOneWidget);
      await confirmDialog(tester, _l10n.cancel);

      expect(recovery.calls, isEmpty);
    });

    testWidgets('confirming deletes and hands over the fresh database', (
      tester,
    ) async {
      final recovery = _FakeRecovery();
      await pump(tester, recovery);

      await tester.tap(find.text(_l10n.recoveryStartFresh));
      await tester.pumpAndSettle();
      await confirmDialog(tester, _l10n.recoveryStartFreshConfirm);

      expect(recovery.calls, ['startFresh']);
      expect(recovered, hasLength(1));
    });
  });

  testWidgets('an action that fails is reported, never silent', (tester) async {
    final recovery = _FakeRecovery(failure: StateError('disk full'));
    await pump(tester, recovery);

    await tester.tap(find.text(_l10n.recoveryStartFresh));
    await tester.pumpAndSettle();
    await confirmDialog(tester, _l10n.recoveryStartFreshConfirm);

    expect(recovered, isEmpty);
    expect(
      find.textContaining('disk full', findRichText: true),
      findsOneWidget,
    );
    // And the screen is still standing, so it can be tried again.
    expect(find.text(_l10n.recoveryStartFresh), findsOneWidget);
  });
}
