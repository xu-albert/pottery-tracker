import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/pieces_provider.dart';
import '../../../core/constants/app_sizes.dart';

class PiecesSearchBar extends ConsumerStatefulWidget {
  final bool isArchived;

  const PiecesSearchBar({super.key, required this.isArchived});

  @override
  ConsumerState<PiecesSearchBar> createState() => _PiecesSearchBarState();
}

class _PiecesSearchBarState extends ConsumerState<PiecesSearchBar> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).state = value;
    });
  }

  @override
  Widget build(BuildContext context) {
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
          hintText: widget.isArchived ? l10n.searchArchive : l10n.searchActive,
          prefixIcon: const Icon(Icons.search),
          isDense: true,
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }
}
