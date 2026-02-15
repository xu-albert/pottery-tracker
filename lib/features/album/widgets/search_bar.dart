import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/pieces_provider.dart';
import '../../../core/constants/app_sizes.dart';

class PiecesSearchBar extends ConsumerWidget {
  const PiecesSearchBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.md,
        AppSizes.sm,
        AppSizes.md,
        0,
      ),
      child: TextField(
        autocorrect: false,
        decoration: InputDecoration(
          hintText: l10n.searchPieces,
          prefixIcon: const Icon(Icons.search),
          isDense: true,
        ),
        onChanged: (value) =>
            ref.read(searchQueryProvider.notifier).state = value,
      ),
    );
  }
}
