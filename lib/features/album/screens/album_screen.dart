import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/pieces_provider.dart';
import '../widgets/album_grid.dart';
import '../widgets/search_bar.dart' as app;
import '../widgets/filter_chips.dart';
import '../widgets/empty_state.dart';

class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final piecesAsync = ref.watch(filteredPiecesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: Column(
        children: [
          const app.PiecesSearchBar(),
          const FilterChips(),
          Expanded(
            child: piecesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (pieces) {
                if (pieces.isEmpty) return const EmptyState();
                return AlbumGrid(pieces: pieces);
              },
            ),
          ),
        ],
      ),
    );
  }
}
