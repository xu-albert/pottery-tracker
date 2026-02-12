import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../core/constants/app_sizes.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          // Account section
          _SectionHeader(title: l10n.account),
          ListTile(
            leading: const Icon(Icons.person),
            title: Text(auth.displayName != null
                ? l10n.signedInAs(auth.displayName!)
                : l10n.notSignedIn),
          ),
          if (auth.displayName != null)
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(l10n.signOut),
              onTap: () => ref.read(authProvider.notifier).signOut(),
            ),
          const Divider(),

          // Sync section
          _SectionHeader(title: l10n.syncStatus),
          ListTile(
            leading: const Icon(Icons.cloud_off),
            title: Text(l10n.syncComingSoon),
          ),
          const Divider(),

          // Support
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: Text(l10n.supportDeveloper),
            subtitle: const Text('Coming soon'),
          ),
          const Divider(),

          // About
          _SectionHeader(title: l10n.about),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.version('1.0.0')),
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
          AppSizes.md, AppSizes.md, AppSizes.md, AppSizes.xs),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
