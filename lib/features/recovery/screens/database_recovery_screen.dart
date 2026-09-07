import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../database/database.dart';
import '../../../database/local_database_bootstrap.dart';
import '../../../database/transfer_key_backup.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_snackbar.dart';

/// Shown instead of the app when a database file is on the device but no key
/// here opens it — a backup restored onto a new phone.
///
/// Nothing the app proper does is safe over that file, so this runs before the
/// app, outside its providers and router, and hands back a database through
/// [onRecovered] only once one can actually be opened. What it offers depends
/// on what came along in the restore, in this order of preference:
///
/// * a **transfer backup** — the passphrase unlocks the restored journal in
///   place; nothing is lost;
/// * a **synced account** stamp — the pieces live in the cloud, so the
///   unreadable copy is removed and sign-in downloads them again, reusing the
///   photo files that restored fine;
/// * neither — the pottery existed on the old phone only, and the screen
///   says so plainly before it lets the user delete it and start over.
///
/// The third is the cost the hardening was known to carry for local-only
/// users; the first is what was built so they need not pay it. Both
/// destructive actions are confirmed, and their result is reported.
class DatabaseRecoveryScreen extends StatefulWidget {
  const DatabaseRecoveryScreen({
    super.key,
    required this.recovery,
    required this.onRecovered,
  });

  final LocalDatabaseRecovery recovery;
  final Future<void> Function(AppDatabase database) onRecovered;

  @override
  State<DatabaseRecoveryScreen> createState() => _DatabaseRecoveryScreenState();
}

class _DatabaseRecoveryScreenState extends State<DatabaseRecoveryScreen> {
  final _passphrase = TextEditingController();
  bool _busy = false;
  String? _passphraseError;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _run(Future<AppDatabase> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final db = await action();
      await widget.onRecovered(db);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.show(
        context,
        message: AppLocalizations.of(context)!.recoveryFailed(e.toString()),
        duration: const Duration(seconds: 6),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlock() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    final passphrase = _passphrase.text;
    setState(() {
      _passphraseError = null;
      _busy = true;
    });
    try {
      final db = await widget.recovery.unlockWithPassphrase(passphrase);
      await widget.onRecovered(db);
    } on WrongTransferPassphraseException {
      if (mounted) {
        setState(() => _passphraseError = l10n.recoveryWrongPassphrase);
      }
    } on TransferKeyMismatchException {
      if (mounted) {
        setState(() => _passphraseError = l10n.recoveryTransferKeyMismatch);
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(
          context,
          message: l10n.recoveryFailed(e.toString()),
          duration: const Duration(seconds: 6),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The transfer passphrase is iOS-only — Android opts out of backups and of
  /// device transfer entirely — so the copy that offers it, and the copy that
  /// explains a restore, must not be shown there.
  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    required bool destructive,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true && mounted;
  }

  Future<void> _redownload() async {
    final l10n = AppLocalizations.of(context)!;
    if (!await _confirm(
      title: l10n.recoveryRedownloadConfirmTitle,
      message: l10n.recoveryRedownloadConfirmMessage,
      action: l10n.recoveryRedownloadConfirm,
      destructive: false,
    )) {
      return;
    }
    await _run(widget.recovery.redownloadFromCloud);
  }

  Future<void> _startFresh() async {
    final l10n = AppLocalizations.of(context)!;
    if (!await _confirm(
      title: l10n.recoveryStartFreshConfirmTitle,
      message: _isIOS
          ? l10n.recoveryStartFreshConfirmMessage
          : l10n.recoveryStartFreshConfirmMessageAndroid,
      action: l10n.recoveryStartFreshConfirm,
      destructive: true,
    )) {
      return;
    }
    await _run(widget.recovery.startFresh);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final recovery = widget.recovery;
    final cloud = recovery.stampedOwnerUid != null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.phonelink_lock_outlined, size: 56),
                const SizedBox(height: AppSizes.lg),
                Text(
                  l10n.recoveryTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSizes.md),
                Text(
                  switch (recovery.cause) {
                    UnreadableDatabaseCause.keyMissing when _isIOS =>
                      l10n.recoveryMessageKeyMissing,
                    UnreadableDatabaseCause.keyMissing =>
                      l10n.recoveryMessageKeyMissingAndroid,
                    UnreadableDatabaseCause.keyMismatch =>
                      l10n.recoveryMessageKeyMismatch,
                  },
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSizes.md),
                Text(
                  cloud
                      ? l10n.recoveryCloudHint
                      : _isIOS
                      ? l10n.recoveryLocalOnlyHint
                      : l10n.recoveryLocalOnlyHintAndroid,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSizes.xl),
                if (recovery.hasTransferBackup) ...[
                  Text(
                    l10n.recoveryPassphraseSection,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSizes.sm),
                  TextField(
                    controller: _passphrase,
                    enabled: !_busy,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _unlock(),
                    decoration: InputDecoration(
                      labelText: l10n.recoveryPassphraseLabel,
                      errorText: _passphraseError,
                    ),
                  ),
                  const SizedBox(height: AppSizes.sm),
                  FilledButton(
                    onPressed: _busy ? null : _unlock,
                    child: Text(l10n.recoveryUnlock),
                  ),
                  const SizedBox(height: AppSizes.lg),
                ],
                if (cloud) ...[
                  // Primary only when no passphrase can do better: the
                  // passphrase keeps everything in place, the re-download
                  // merely costs a sign-in.
                  if (recovery.hasTransferBackup)
                    OutlinedButton(
                      onPressed: _busy ? null : _redownload,
                      child: Text(l10n.recoveryRedownload),
                    )
                  else
                    FilledButton(
                      onPressed: _busy ? null : _redownload,
                      child: Text(l10n.recoveryRedownload),
                    ),
                  const SizedBox(height: AppSizes.sm),
                ],
                TextButton(
                  onPressed: _busy ? null : _startFresh,
                  child: Text(
                    l10n.recoveryStartFresh,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
                if (_busy) ...[
                  const SizedBox(height: AppSizes.md),
                  const Center(child: CircularProgressIndicator()),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
