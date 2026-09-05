import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../database/transfer_key_backup.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/transfer_provider.dart';
import '../../../widgets/app_snackbar.dart';

/// Opens the sheet that sets, changes or removes the transfer passphrase.
Future<void> showTransferPassphraseSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const TransferPassphraseSheet(),
  );
}

/// Sets the passphrase that wraps this device's database key into a
/// backup-restorable file — see [TransferKeyBackup].
///
/// Validation is the sheet's: length and a matching repeat. Writing the file
/// needs the current key, read from the key store on save so the sheet never
/// holds it longer than the write. The "set" flag the settings tile shows is
/// updated here, from what actually happened on disk.
class TransferPassphraseSheet extends ConsumerStatefulWidget {
  const TransferPassphraseSheet({super.key});

  @override
  ConsumerState<TransferPassphraseSheet> createState() =>
      _TransferPassphraseSheetState();
}

class _TransferPassphraseSheetState
    extends ConsumerState<TransferPassphraseSheet> {
  final _passphrase = TextEditingController();
  final _repeat = TextEditingController();
  String? _passphraseError;
  String? _repeatError;
  bool _busy = false;

  @override
  void dispose() {
    _passphrase.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    final passphrase = _passphrase.text;
    final tooShort = passphrase.length < TransferKeyBackup.minPassphraseLength;
    final mismatch = _repeat.text != passphrase;
    setState(() {
      _passphraseError = tooShort
          ? l10n.transferPassphraseTooShort(
              TransferKeyBackup.minPassphraseLength,
            )
          : null;
      _repeatError = !tooShort && mismatch
          ? l10n.transferPassphraseMismatch
          : null;
    });
    if (tooShort || mismatch) return;

    setState(() => _busy = true);
    try {
      final key = await ref.read(encryptionKeyServiceProvider).readKey();
      if (key == null) {
        // The app is running, so a database is open, so a key exists. Not
        // being able to read it is a store failure, reported as one.
        throw StateError('no database key is stored on this device');
      }
      await ref
          .read(transferKeyBackupProvider)
          .write(databaseKey: key, passphrase: passphrase);
      ref.read(transferPassphraseSetProvider.notifier).state = true;
      if (!mounted) return;
      Navigator.of(context).pop();
      AppSnackbar.show(context, message: l10n.transferPassphraseSaved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppSnackbar.show(
        context,
        message: l10n.transferPassphraseFailed(e.toString()),
        duration: const Duration(seconds: 6),
      );
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CupertinoAlertDialog(
        title: Text(l10n.transferPassphraseRemoveConfirmTitle),
        content: Text(l10n.transferPassphraseRemoveConfirmMessage),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.remove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(transferKeyBackupProvider).delete();
      ref.read(transferPassphraseSetProvider.notifier).state = false;
      if (!mounted) return;
      Navigator.of(context).pop();
      AppSnackbar.show(context, message: l10n.transferPassphraseRemoved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppSnackbar.show(
        context,
        message: l10n.transferPassphraseFailed(e.toString()),
        duration: const Duration(seconds: 6),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final alreadySet = ref.watch(transferPassphraseSetProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSizes.lg,
        right: AppSizes.lg,
        top: AppSizes.lg,
        bottom: AppSizes.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            alreadySet
                ? l10n.changeTransferPassphrase
                : l10n.setTransferPassphrase,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            l10n.transferPassphraseSheetMessage(
              TransferKeyBackup.minPassphraseLength,
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSizes.md),
          TextField(
            controller: _passphrase,
            enabled: !_busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.transferPassphraseHint,
              errorText: _passphraseError,
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          TextField(
            controller: _repeat,
            enabled: !_busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: l10n.transferPassphraseConfirmHint,
              errorText: _repeatError,
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          FilledButton(onPressed: _busy ? null : _save, child: Text(l10n.save)),
          if (alreadySet) ...[
            const SizedBox(height: AppSizes.sm),
            TextButton(
              onPressed: _busy ? null : _remove,
              child: Text(
                l10n.removeTransferPassphrase,
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
