import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/auth_service.dart';
import '../../../core/constants/app_sizes.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _authService = AuthService();
  bool _isLinking = false;

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
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } on SignInCancelledException {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(l10n.signInCancelled)));
      }
    } on AccountAlreadyLinkedException {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(l10n.accountAlreadyLinked)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(e.toString())));
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.disconnectConfirmTitle(providerName)),
        content: Text(l10n.disconnectConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(e.toString())));
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
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(l10n.signInCancelled)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isLinking = false);
    }
  }

  Future<void> _confirmSignOut() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.signOutConfirmTitle),
        content: Text(l10n.signOutConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.signOut),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _authService.signOut();
    ref.read(authProvider.notifier).signOut();
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

    final VoidCallback? onTap;
    if (_isLinking) {
      onTap = null;
    } else if (!isLinked) {
      onTap = onConnect;
    } else if (providerCount > 1) {
      onTap = onDisconnect;
    } else {
      onTap = null;
    }

    return ListTile(
      leading: Icon(icon),
      title: Text(name),
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
      BuildContext context, WidgetRef ref, AppLocalizations l10n, AuthState auth) {
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
              DateFormat.yMMMd().add_jm().format(syncState.lastSyncedAt!));
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
      case SyncStatus.disabled:
        icon = Icons.cloud_off;
        title = l10n.syncDisabled;
    }

    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis) : null,
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
              title: Text(l10n.signOut),
              onTap: _confirmSignOut,
            ),
          const Divider(),

          // Cloud Backup section
          _SectionHeader(title: l10n.syncStatus),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: Text(l10n.syncComingSoon),
          ),
          const Divider(),

          // Support
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: Text(l10n.supportDeveloper),
            subtitle: Text(l10n.comingSoon),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(l10n.sendFeedback),
            onTap: () {
              final uri = Uri(
                scheme: 'mailto',
                path: 'pottery.tracker.app@gmail.com',
                queryParameters: {'subject': 'Pottery Tracker Feedback'},
              );
              launchUrl(uri);
            },
          ),
          const Divider(),

          // About
          _SectionHeader(title: l10n.about),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.version('1.0.0')),
          ),

          // Debug
          const Divider(),
          _SectionHeader(title: 'Debug'),
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('Test Crash'),
            onTap: () => FirebaseCrashlytics.instance.crash(),
          ),
        ],
      ),
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
