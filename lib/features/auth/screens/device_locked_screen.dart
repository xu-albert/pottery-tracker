import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../widgets/app_snackbar.dart';

/// Shown instead of the app whenever the device is locked read-only.
///
/// The device is read-only in the strongest sense available: the refused
/// account never reaches a screen that can write. That is deliberate. The
/// earlier design let a refused account edit freely and then tried to track
/// which rows it had touched, which cost the owner data twice over — a
/// deletion could destroy the owner's piece permanently while the app still
/// reported a clean backup.
///
/// [DeviceLockReason] decides what this says and what it offers, because the
/// two locks are opposite situations. Foreign pottery is somebody else's and
/// must not be destroyed on their behalf, so the way out is the owner signing
/// back in and the erase is the last resort. An owed wipe is the signed-in
/// user's *own* unfinished erase, so finishing it is the way out — offering
/// to leave the session instead would tell them their own pottery belongs to
/// a stranger and hand them a button that deliberately keeps it.
class DeviceLockedScreen extends ConsumerStatefulWidget {
  const DeviceLockedScreen({super.key});

  @override
  ConsumerState<DeviceLockedScreen> createState() => _DeviceLockedScreenState();
}

class _DeviceLockedScreenState extends ConsumerState<DeviceLockedScreen> {
  bool _busy = false;

  /// Leaves without destroying anything: none of the pottery here belongs to
  /// the account being signed out, so there is nothing of theirs to delete.
  Future<void> _switchAccount() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(syncStateProvider.notifier)
          .endForeignSession(ref.read(authServiceProvider).signOut);
      await ref.read(authProvider.notifier).signOut();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _eraseDevice() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CupertinoAlertDialog(
        title: Text(l10n.eraseLocalDataConfirmTitle),
        content: Text(l10n.eraseLocalDataConfirmMessage),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.eraseLocalDataConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await ref
          .read(syncStateProvider.notifier)
          .eraseLocalDataNow();
      if (!mounted) return;
      switch (result) {
        case EraseLocalDataResult.erased:
          break;
        case EraseLocalDataResult.busy:
          AppSnackbar.show(context, message: l10n.eraseLocalDataBusy);
        case EraseLocalDataResult.failed:
          AppSnackbar.show(context, message: l10n.eraseLocalDataFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final reason = ref.watch(deviceLockReasonProvider);
    final owedWipe = reason == DeviceLockReason.pendingWipe;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_outline, size: 56),
                const SizedBox(height: AppSizes.lg),
                Text(
                  owedWipe
                      ? l10n.syncBlockedWipePending
                      : l10n.deviceLockedTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSizes.md),
                // The explanation carries the only recovery instruction the
                // user gets, so it wraps in full however long it runs.
                Text(
                  owedWipe
                      ? l10n.syncBlockedWipePendingDetail
                      : l10n.deviceLockedMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSizes.xl),
                if (owedWipe)
                  FilledButton(
                    onPressed: _busy ? null : _eraseDevice,
                    child: Text(l10n.deviceLockedErase),
                  )
                else ...[
                  FilledButton(
                    onPressed: _busy ? null : _switchAccount,
                    child: Text(l10n.deviceLockedSwitchAccount),
                  ),
                  const SizedBox(height: AppSizes.sm),
                  TextButton(
                    onPressed: _busy ? null : _eraseDevice,
                    child: Text(
                      l10n.deviceLockedErase,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
