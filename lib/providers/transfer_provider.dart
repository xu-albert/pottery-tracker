import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/transfer_key_backup.dart';
import '../services/encryption_key_service.dart';

/// The key store the database key lives in. One instance, pinned options.
final encryptionKeyServiceProvider = Provider<EncryptionKeyService>(
  (ref) => EncryptionKeyService(),
);

/// The transfer backup for this device's documents directory.
///
/// Overridden in `main` with the instance the bootstrap used, the same way
/// `databaseProvider` is, so it needs no async directory lookup at read time.
final transferKeyBackupProvider = Provider<TransferKeyBackup>((ref) {
  throw UnimplementedError('TransferKeyBackup must be provided before runApp');
});
