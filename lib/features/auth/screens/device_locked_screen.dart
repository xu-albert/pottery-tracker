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

  /// Whether a retry was asked for while an attempt was already running.
  ///
  /// The sync that blocks a wipe most often ends *during* the attempt it
  /// refused — that attempt captured the blocked condition when it started,
  /// so it keeps the flag, and a signal dropped at that moment would never
  /// come again. One flag rather than a count: any number of signals during
  /// one attempt owe exactly one follow-up, and a follow-up that no signal
  /// reached settles instead of re-arming.
  bool _retryOwed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumeOwedWipe());
  }

  /// Runs [action] as the screen's one action in flight, then pays a retry
  /// that was asked for while it ran.
  Future<void> _whileBusy(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted || !_retryOwed) return;
    _retryOwed = false;
    await _resumeOwedWipe();
  }

  /// Finishes an owed wipe without asking, because the user already said yes.
  ///
  /// This screen is the only place the retry can still happen: the owed-wipe
  /// flag locks the router on the first frame, so the shell never mounts and
  /// the auth transition that used to carry it never runs. A wipe that failed
  /// on something transient therefore still heals itself, and the erase below
  /// is what is left when it does not.
  ///
  /// Reached more than once, because once was not enough. A wipe that landed
  /// while a sync outlived it keeps the flag deliberately, and this screen
  /// opens while that sync is still running — so the mount-time attempt read
  /// the same blocked condition and kept the flag again, leaving the device
  /// locked long after the sync had unwound. [build] watches for that to
  /// clear and comes back here; if it arrives while an attempt is running it
  /// is remembered in [_retryOwed] and paid when that attempt settles. The
  /// retry stays on this screen either way: it is never fired from `syncNow`,
  /// from the debounced push, or from the sync's own completion, so no delete
  /// can land behind an edit.
  Future<void> _resumeOwedWipe() async {
    if (!mounted) return;
    if (_busy) {
      _retryOwed = true;
      return;
    }
    if (ref.read(deviceLockReasonProvider) != DeviceLockReason.pendingWipe) {
      return;
    }
    await _whileBusy(
      () => ref.read(syncStateProvider.notifier).retryOwedWipe(),
    );
  }

  /// Drops to the sign-in screen without destroying anything.
  ///
  /// Nothing here is the leaving session's to delete — and on a session-less
  /// launch there is no session to leave at all, only the sign-in screen to
  /// reach, which is where the owner signs back in.
  Future<void> _switchAccount() async {
    if (_busy) return;
    await _whileBusy(() async {
      await ref
          .read(syncStateProvider.notifier)
          .endForeignSession(ref.read(authServiceProvider).signOut);
      // Recorded before the session ends, and read by the redirect rather
      // than navigated to here: signing out rebuilds the router, which would
      // discard a push and leave the user looking at the same lock. The
      // refusal itself outlives the session — only the owner may lift it — so
      // without this the way out would do nothing at all.
      ref.read(lockExitRequestedProvider.notifier).state = ref.read(
        deviceLockReasonProvider,
      );
      await ref.read(authProvider.notifier).signOut();
    });
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

    await _whileBusy(() async {
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
        case EraseLocalDataResult.photosSurvived:
          AppSnackbar.show(context, message: l10n.eraseLocalDataPhotosSurvived);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // The sync that was blocking the wipe has finished, so the attempt that
    // was refused is worth making again — after the one in flight, if any.
    ref.listen<bool>(staleSyncBlockingWipeProvider, (was, isBlocking) {
      if (was == true && !isBlocking) _resumeOwedWipe();
    });
    final reason = ref.watch(deviceLockReasonProvider);
    final owedWipe = reason == DeviceLockReason.pendingWipe;
    // A "Delete Account & Data" whose local wipe failed lands here, and the
    // message that said the account survived is long gone. The fact is
    // persisted, so this screen can still say it.
    final accountOwed = ref.watch(accountDeletionOwedForSessionProvider);

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
                      ? l10n.deviceLockedWipeTitle
                      : l10n.deviceLockedTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSizes.md),
                // The explanation carries the only recovery instruction the
                // user gets, so it wraps in full however long it runs.
                Text(
                  owedWipe
                      ? l10n.deviceLockedWipeMessage
                      : l10n.deviceLockedMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (owedWipe && accountOwed) ...[
                  const SizedBox(height: AppSizes.md),
                  Text(
                    l10n.deviceLockedAccountStillExists,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
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
