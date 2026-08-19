import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../services/auth_service.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../widgets/app_snackbar.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  AuthService get _authService => ref.read(authServiceProvider);
  bool _isLinking = false;
  bool _isSigningOut = false;
  bool _isDeletingAccount = false;

  Future<void> _linkProvider({
    required Future<void> Function() linkFn,
    required String successMessage,
  }) async {
    if (_isLinking) return;
    setState(() => _isLinking = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      await linkFn();
      ref.read(authProvider.notifier).refreshProviders();
      if (mounted) {
        AppSnackbar.show(context, message: successMessage);
      }
    } on SignInCancelledException {
      if (mounted) {
        AppSnackbar.show(context, message: l10n.signInCancelled);
      }
    } on AccountAlreadyLinkedException {
      if (mounted) {
        AppSnackbar.show(context, message: l10n.accountAlreadyLinked);
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(context, message: e.toString());
      }
    } finally {
      if (mounted) setState(() => _isLinking = false);
    }
  }

  Future<void> _unlinkProvider({
    required Future<void> Function() unlinkFn,
    required String providerName,
    required String successMessage,
  }) async {
    if (_isLinking) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(l10n.disconnectConfirmTitle(providerName)),
        content: Text(l10n.disconnectConfirmMessage),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.disconnect),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isLinking = true);
    try {
      await unlinkFn();
      ref.read(authProvider.notifier).refreshProviders();
      if (mounted) {
        AppSnackbar.show(context, message: successMessage);
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(context, message: e.toString());
      }
    } finally {
      if (mounted) setState(() => _isLinking = false);
    }
  }

  Future<void> _signInWith({required Future<User> Function() signInFn}) async {
    if (_isLinking) return;
    setState(() => _isLinking = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      final user = await signInFn();
      if (mounted) {
        ref.read(authProvider.notifier).signIn(user);
      }
    } on SignInCancelledException {
      if (mounted) {
        AppSnackbar.show(context, message: l10n.signInCancelled);
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(context, message: e.toString());
      }
    } finally {
      if (mounted) setState(() => _isLinking = false);
    }
  }

  /// Signs out, which also destroys this device's local pottery data.
  ///
  /// The wipe is not optional: anything left behind is uploaded into the next
  /// account's cloud tree on its first sync. Because it is destructive, the
  /// confirmation says so in full and cannot be dismissed into a sign-out by
  /// accident — the barrier is inert, Cancel is the default action, and a
  /// dismissed dialog resolves to "cancel".
  Future<void> _confirmSignOut() async {
    if (_isSigningOut) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CupertinoAlertDialog(
        title: Text(l10n.signOutConfirmTitle),
        content: Text(l10n.signOutConfirmMessage),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.signOutAndErase),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSigningOut = true);
    try {
      await ref
          .read(syncStateProvider.notifier)
          .signOutAndWipeLocalData(_authService.signOut);
    } catch (e) {
      // The session is already gone and the wipe is still flagged pending, so
      // it will be finished on the next sign-in. Say so rather than implying
      // the device is clean.
      debugPrint('SettingsScreen: sign-out wipe failed: $e');
      if (mounted) {
        AppSnackbar.show(context, message: l10n.signOutWipeFailed);
      }
    } finally {
      await ref.read(authProvider.notifier).signOut();
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  /// Erasing is destructive and the user did not ask for the situation that
  /// led here, so it is never a bare tap: the dialog says exactly what goes,
  /// Cancel is the default action, and the barrier is inert.
  Future<void> _confirmEraseLocalData() async {
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
  }

  Widget _providerTile({
    required IconData icon,
    required String name,
    required bool isLinked,
    required int providerCount,
    required VoidCallback onConnect,
    required VoidCallback onDisconnect,
  }) {
    final l10n = AppLocalizations.of(context)!;
    const linkedColor = Color(0xFF2E7D32);
    const notLinkedColor = Color(0xFFE91E63);

    // Unlinking the only remaining provider leaves an account nobody can ever
    // sign into again — Firebase keeps the data and hands out no way back to
    // it. Refuse the tap and say why, rather than offering a dead one.
    final isOnlyProvider = isLinked && providerCount <= 1;

    final VoidCallback? onTap;
    if (_isLinking || isOnlyProvider) {
      onTap = null;
    } else if (!isLinked) {
      onTap = onConnect;
    } else {
      onTap = onDisconnect;
    }

    return ListTile(
      leading: Icon(icon),
      title: Text(name),
      subtitle: isOnlyProvider ? Text(l10n.lastProviderCannotDisconnect) : null,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isLinked ? l10n.linked : l10n.notLinked,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: isLinked ? linkedColor : notLinkedColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isLinked ? linkedColor : notLinkedColor,
                width: 2,
              ),
              color: isLinked ? linkedColor : Colors.transparent,
            ),
            child: isLinked
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSyncTile(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    AuthState auth,
  ) {
    if (!auth.isSignedIn) {
      return ListTile(
        leading: const Icon(Icons.cloud_off),
        title: Text(l10n.syncDisabled),
      );
    }

    final syncState = ref.watch(syncStateProvider);

    final IconData icon;
    final String title;
    String? subtitle;
    Widget? trailing;

    switch (syncState.status) {
      case SyncStatus.syncing:
        icon = Icons.cloud_sync;
        title = l10n.syncSyncing;
        trailing = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case SyncStatus.idle:
        if (syncState.pendingCount > 0) {
          icon = Icons.cloud_upload;
          title = l10n.syncPending(syncState.pendingCount);
        } else {
          icon = Icons.cloud_done;
          title = l10n.syncBackedUp;
        }
        if (syncState.lastSyncedAt != null) {
          subtitle = l10n.syncLastSynced(
            DateFormat.yMMMd().add_jm().format(syncState.lastSyncedAt!),
          );
        }
        trailing = GestureDetector(
          onLongPress: () =>
              ref.read(syncStateProvider.notifier).syncNow(forceFullSync: true),
          child: TextButton(
            onPressed: () => ref.read(syncStateProvider.notifier).syncNow(),
            child: Text(l10n.syncNow),
          ),
        );
      case SyncStatus.error:
        icon = Icons.cloud_off;
        title = l10n.syncError;
        subtitle = syncState.errorMessage;
        trailing = GestureDetector(
          onLongPress: () =>
              ref.read(syncStateProvider.notifier).syncNow(forceFullSync: true),
          child: TextButton(
            onPressed: () => ref.read(syncStateProvider.notifier).syncNow(),
            child: Text(l10n.syncNow),
          ),
        );
      case SyncStatus.blocked:
        // Not an error the user caused: this device is holding data it is not
        // allowed to upload. The two reasons need different ways out.
        icon = Icons.cloud_off;
        // Only the owed-wipe case can be seen from here: a device holding
        // another account's pottery is locked read-only at the router, so
        // Settings is not reachable on it at all.
        // "Sync Now" no longer carries the retry — a delete on the push path
        // could land mid-session — so the retry is this button, and it
        // confirms first.
        title = l10n.syncBlockedWipePending;
        subtitle = l10n.syncBlockedWipePendingDetail;
        trailing = TextButton(
          onPressed: _confirmEraseLocalData,
          child: Text(l10n.syncBlockedRetry),
        );
      case SyncStatus.disabled:
        icon = Icons.cloud_off;
        title = l10n.syncDisabled;
    }

    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null
          // The blocked explanation carries the only recovery instruction the
          // user gets, so it wraps in full rather than being ellipsized; the
          // taller tile in that rare state is deliberate.
          ? Text(
              subtitle,
              maxLines: syncState.status == SyncStatus.blocked ? null : 3,
              overflow: syncState.status == SyncStatus.blocked
                  ? TextOverflow.clip
                  : TextOverflow.ellipsis,
            )
          : null,
      trailing: trailing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          // Materials section
          _SectionHeader(title: l10n.manageMaterials),
          ListTile(
            leading: const Icon(Icons.terrain),
            title: Text(l10n.manageClays),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/clays'),
          ),
          ListTile(
            leading: const Icon(Icons.format_paint),
            title: Text(l10n.manageGlazes),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/glazes'),
          ),
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: Text(l10n.manageTags),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/tags'),
          ),
          const Divider(),

          // Account section
          _SectionHeader(title: l10n.connectedAccounts),
          _providerTile(
            icon: Icons.g_mobiledata,
            name: l10n.google,
            isLinked: auth.isGoogleLinked,
            providerCount: auth.linkedProviders.length,
            onConnect: auth.isSignedIn
                ? () => _linkProvider(
                    linkFn: _authService.linkGoogle,
                    successMessage: l10n.googleLinkedSuccess,
                  )
                : () => _signInWith(signInFn: _authService.signInWithGoogle),
            onDisconnect: () => _unlinkProvider(
              unlinkFn: _authService.unlinkGoogle,
              providerName: l10n.google,
              successMessage: l10n.googleDisconnected,
            ),
          ),
          if (Platform.isIOS)
            _providerTile(
              icon: Icons.apple,
              name: l10n.apple,
              isLinked: auth.isAppleLinked,
              providerCount: auth.linkedProviders.length,
              onConnect: auth.isSignedIn
                  ? () => _linkProvider(
                      linkFn: _authService.linkApple,
                      successMessage: l10n.appleLinkedSuccess,
                    )
                  : () => _signInWith(signInFn: _authService.signInWithApple),
              onDisconnect: () => _unlinkProvider(
                unlinkFn: _authService.unlinkApple,
                providerName: l10n.apple,
                successMessage: l10n.appleDisconnected,
              ),
            ),
          if (auth.isSignedIn)
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(_isSigningOut ? l10n.signingOut : l10n.signOut),
              trailing: _isSigningOut
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              // Both wipe owners have to exclude each other, or two deletes
              // run at once and each clears the other's guard.
              onTap: (_isSigningOut || _isDeletingAccount)
                  ? null
                  : _confirmSignOut,
            ),
          const Divider(),

          // Cloud Backup section
          _SectionHeader(title: l10n.syncStatus),
          _buildSyncTile(context, ref, l10n, auth),
          const Divider(),

          // Support
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: Text(l10n.supportDeveloper),
            onTap: () => launchUrl(
              Uri.parse('https://ko-fi.com/albertxu451'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(l10n.sendFeedback),
            onTap: () => context.push('/feedback'),
          ),
          const Divider(),

          // About
          _SectionHeader(title: l10n.about),
          const AppVersionTile(),

          // Debug
          const Divider(),
          _SectionHeader(title: 'Account'),
          ListTile(
            // Excludes itself as well as sign-out: a second tap lands in the
            // busy early return, and its finally would otherwise re-enable the
            // sign-out tile while the first delete is still running.
            enabled: !_isSigningOut && !_isDeletingAccount,
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text(
              'Delete Account & Data',
              style: TextStyle(color: Colors.red),
            ),
            subtitle: const Text(
              'Permanently deletes your account and all data',
            ),
            onTap: () async {
              final confirmed = await showCupertinoDialog<bool>(
                context: context,
                builder: (context) => CupertinoAlertDialog(
                  title: const Text('Delete Account & Data?'),
                  content: const Text(
                    'This will permanently delete your account and ALL pieces, photos, and materials from this device and the cloud. This cannot be undone.',
                  ),
                  actions: [
                    CupertinoDialogAction(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    CupertinoDialogAction(
                      isDestructiveAction: true,
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete Everything'),
                    ),
                  ],
                ),
              );
              if (confirmed != true || !context.mounted) return;
              setState(() => _isDeletingAccount = true);
              try {
                final result = await ref
                    .read(syncStateProvider.notifier)
                    .deleteAllData();
                if (!context.mounted) return;
                switch (result) {
                  case DeleteAllDataResult.deleted:
                    break;
                  case DeleteAllDataResult.busy:
                    AppSnackbar.show(context, message: l10n.deleteAccountBusy);
                  case DeleteAllDataResult.failed:
                    AppSnackbar.show(
                      context,
                      message: l10n.deleteAccountFailed,
                    );
                  // Partial outcomes get their own words: "nothing was
                  // deleted" would be a lie once the cloud tree is gone.
                  case DeleteAllDataResult.accountSurvived:
                    AppSnackbar.show(
                      context,
                      message: l10n.deleteAccountSurvived,
                    );
                  case DeleteAllDataResult.localDataSurvived:
                    AppSnackbar.show(
                      context,
                      message: l10n.deleteAccountLocalSurvived,
                    );
                }
              } finally {
                if (mounted) setState(() => _isDeletingAccount = false);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// The About row's version line, read from the running build rather than a
/// literal so it can never drift from `version:` in `pubspec.yaml`, which owns
/// it. Public only so a widget test can pump it without SettingsScreen's
/// Firebase-backed AuthService.
class AppVersionTile extends StatefulWidget {
  const AppVersionTile({super.key});

  @override
  State<AppVersionTile> createState() => _AppVersionTileState();
}

class _AppVersionTileState extends State<AppVersionTile> {
  // Resolved once, not per build, so a rebuild cannot drop the row back to its
  // pre-load state.
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return FutureBuilder<PackageInfo>(
      future: _packageInfo,
      builder: (context, snapshot) {
        final info = snapshot.data;
        // Show nothing until the real version is known: a placeholder here
        // would be a wrong version on screen.
        if (info == null) return const SizedBox.shrink();
        return ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.version(info.version)),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.md,
        AppSizes.md,
        AppSizes.md,
        AppSizes.xs,
      ),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}
