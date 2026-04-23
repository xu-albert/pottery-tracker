import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/pieces_provider.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../providers/sync_provider.dart';

class ShellScreen extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const ShellScreen({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // Initialize sync provider early so it starts on auth change
    ref.watch(syncStateProvider);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex >= 1
            ? navigationShell.currentIndex + 1
            : navigationShell.currentIndex,
        onTap: (index) {
          AppSnackbar.hide();
          if (index == 1) {
            ref.read(archivedFilterProvider.notifier).state = false;
            context.push('/create');
          } else {
            navigationShell.goBranch(
              index > 1 ? index - 1 : index,
              initialLocation: index == navigationShell.currentIndex,
            );
          }
        },
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home_outlined),
            activeIcon: const Icon(Icons.home),
            label: l10n.homeTab,
          ),
          BottomNavigationBarItem(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: AppColors.teal,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 24),
            ),
            label: l10n.addPiece,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_outlined),
            activeIcon: const Icon(Icons.settings),
            label: l10n.settingsTab,
          ),
        ],
      ),
    );
  }
}
