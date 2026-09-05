import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoAlertDialog;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/transfer_key_backup.dart';
import 'package:pottery_tracker/features/settings/widgets/transfer_passphrase_sheet.dart';
import 'package:pottery_tracker/l10n/app_localizations_en.dart';
import 'package:pottery_tracker/providers/transfer_provider.dart';
import 'package:pottery_tracker/services/encryption_key_service.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_sqlcipher.dart';
import '../../helpers/test_helpers.dart';

final _l10n = AppLocalizationsEn();
const _dbKey = 'thisDevicesKey0123456789abcdefgh';

void main() {
  late Directory docs;
  late FakeSecureStoragePlatform platform;
  late TransferKeyBackup backup;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('passphrase_sheet_');
    platform = FakeSecureStoragePlatform();
    platform.values['db_encryption_key'] = _dbKey;
    FlutterSecureStoragePlatform.instance = platform;
    backup = TransferKeyBackup(documentsDir: docs, keyDatabase: fakeSqlCipher);
  });

  tearDown(() => docs.deleteSync(recursive: true));

  Future<void> pumpSheet(WidgetTester tester) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showTransferPassphraseSheet(context),
          child: const Text('open'),
        ),
      ),
      overrides: [
        encryptionKeyServiceProvider.overrideWithValue(
          EncryptionKeyService(
            storage: const FlutterSecureStorage(
              iOptions: EncryptionKeyService.iosOptions,
              aOptions: EncryptionKeyService.androidOptions,
            ),
          ),
        ),
        transferKeyBackupProvider.overrideWithValue(backup),
      ],
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> enterBoth(WidgetTester tester, String a, String b) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), a);
    await tester.enterText(fields.at(1), b);
    await tester.tap(find.text(_l10n.save));
    await tester.pumpAndSettle();
  }

  testWidgets('states the threat model and the floor', (tester) async {
    await pumpSheet(tester);
    expect(find.text(_l10n.setTransferPassphrase), findsOneWidget);
    expect(
      find.text(
        _l10n.transferPassphraseSheetMessage(
          TransferKeyBackup.minPassphraseLength,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text(_l10n.removeTransferPassphrase), findsNothing);
  });

  testWidgets('rejects a short passphrase without writing', (tester) async {
    await pumpSheet(tester);
    await enterBoth(tester, 'short', 'short');
    expect(find.text(_l10n.transferPassphraseTooShort(8)), findsOneWidget);
    expect(backup.exists(), isFalse);
  });

  testWidgets('rejects a mismatched repeat without writing', (tester) async {
    await pumpSheet(tester);
    await enterBoth(tester, 'correct horse', 'correct house');
    expect(find.text(_l10n.transferPassphraseMismatch), findsOneWidget);
    expect(backup.exists(), isFalse);
  });

  testWidgets(
    'a valid passphrase writes the backup with this device\'s key and closes',
    (tester) async {
      await pumpSheet(tester);
      await enterBoth(tester, 'correct horse', 'correct horse');

      expect(backup.exists(), isTrue);
      expect(await backup.read('correct horse'), _dbKey);
      expect(find.text(_l10n.save), findsNothing);
      expect(find.text(_l10n.transferPassphraseSaved), findsOneWidget);
    },
  );

  testWidgets('a store that cannot produce the key is reported', (
    tester,
  ) async {
    platform.values.clear();
    await pumpSheet(tester);
    await enterBoth(tester, 'correct horse', 'correct horse');

    expect(backup.exists(), isFalse);
    expect(
      find.textContaining('no database key', findRichText: true),
      findsOneWidget,
    );
  });

  group('when one is already set', () {
    setUp(() => backup.write(databaseKey: _dbKey, passphrase: 'old phrase'));

    testWidgets('offers to change or remove, read from the file itself', (tester) async {
      await pumpSheet(tester);
      expect(find.text(_l10n.changeTransferPassphrase), findsOneWidget);
      expect(find.text(_l10n.removeTransferPassphrase), findsOneWidget);
    });

    testWidgets('changing replaces the passphrase', (tester) async {
      await pumpSheet(tester);
      await enterBoth(tester, 'new phrase here', 'new phrase here');
      expect(await backup.read('new phrase here'), _dbKey);
    });

    testWidgets('removing asks first; cancelling keeps it', (tester) async {
      await pumpSheet(tester);
      await tester.tap(find.text(_l10n.removeTransferPassphrase));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(
        find.text(_l10n.transferPassphraseRemoveConfirmMessage),
        findsOneWidget,
      );
      await tester.tap(find.text(_l10n.cancel));
      await tester.pumpAndSettle();
      expect(backup.exists(), isTrue);
    });

    testWidgets('confirming removes the file', (
      tester,
    ) async {
      await pumpSheet(tester);
      await tester.tap(find.text(_l10n.removeTransferPassphrase));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_l10n.remove));
      await tester.pumpAndSettle();
      expect(backup.exists(), isFalse);
        expect(find.text(_l10n.transferPassphraseRemoved), findsOneWidget);
    });
  });
}
