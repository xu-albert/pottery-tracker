import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/pieces_provider.dart';
import '../../../core/constants/app_sizes.dart';

class FilterChips extends ConsumerWidget {
  const FilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final archivedOnly = ref.watch(archivedFilterProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md, vertical: AppSizes.sm),
      child: Row(
        children: [
          ChoiceChip(
            label: Text(l10n.filterAll),
            selected: !archivedOnly,
            onSelected: (_) =>
                ref.read(archivedFilterProvider.notifier).state = false,
          ),
          const SizedBox(width: AppSizes.sm),
          ChoiceChip(
            label: Text(l10n.filterArchived),
            selected: archivedOnly,
            onSelected: (_) =>
                ref.read(archivedFilterProvider.notifier).state = true,
          ),
        ],
      ),
    );
  }
}
