import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../database/database.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/materials_provider.dart';
import '../../../providers/sync_provider.dart';
import '../widgets/material_reorder.dart';

class ManageGlazesScreen extends ConsumerStatefulWidget {
  const ManageGlazesScreen({super.key});

  @override
  ConsumerState<ManageGlazesScreen> createState() => _ManageGlazesScreenState();
}

class _ManageGlazesScreenState extends ConsumerState<ManageGlazesScreen> {
  final _searchCtrl = TextEditingController();
  List<GlazeOption>? _pendingOrder;
  List<GlazeOption>? _pendingBase;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Moves a row of [shown] — the list on screen, which a drag not yet saved
  /// may have reordered — and saves the whole order. [stored] is the list the
  /// stream last delivered.
  Future<void> _onReorder(
    List<GlazeOption> stored,
    List<GlazeOption> shown,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex--;
    final reordered = List<GlazeOption>.of(shown);
    reordered.insert(newIndex, reordered.removeAt(oldIndex));
    setState(() {
      _pendingOrder = reordered;
      _pendingBase = stored;
    });
    await ref.read(materialWriterProvider).reorderGlazes([
      for (final glaze in reordered) glaze.id,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final glazesAsync = ref.watch(allGlazesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.manageGlazes),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddDialog(l10n),
          ),
        ],
      ),
      body: glazesAsync.when(
        data: (glazes) {
          if (glazes.isEmpty) {
            return Center(
              child: Text(
                l10n.noGlazesYet,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }

          final ordered = withPendingOrder(
            glazes,
            pending: _pendingOrder,
            pendingBase: _pendingBase,
          );
          final query = _searchCtrl.text.toLowerCase();
          // A search shows a subset, where a drag has no well-defined place in
          // the whole list, so reordering is offered only on the full list.
          final searching = query.isNotEmpty;
          final filtered = searching
              ? ordered
                    .where((g) => g.name.toLowerCase().contains(query))
                    .toList()
              : ordered;

          Widget row(GlazeOption glaze, int index) {
            return Card(
              key: ValueKey(glaze.id),
              margin: const EdgeInsets.symmetric(vertical: AppSizes.xs),
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.xs),
                child: Row(
                  children: [
                    if (searching)
                      const SizedBox(width: AppSizes.sm)
                    else
                      MaterialDragHandle(index: index),
                    Expanded(
                      child: Text(
                        glaze.name,
                        style: Theme.of(context).textTheme.bodyLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _showEditDialog(l10n, glaze),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _showDeleteDialog(l10n, glaze),
                    ),
                  ],
                ),
              ),
            );
          }

          const listPadding = EdgeInsets.symmetric(
            vertical: AppSizes.xs,
            horizontal: AppSizes.md,
          );

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.md,
                  AppSizes.sm,
                  AppSizes.md,
                  0,
                ),
                child: CupertinoSearchTextField(
                  controller: _searchCtrl,
                  placeholder: l10n.searchGlazes,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.md,
                  vertical: AppSizes.xs,
                ),
                child: Text(
                  l10n.manageGlazesSubtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: searching
                    ? ListView.builder(
                        padding: listPadding,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) =>
                            row(filtered[index], index),
                      )
                    : ReorderableListView.builder(
                        padding: listPadding,
                        buildDefaultDragHandles: false,
                        itemCount: filtered.length,
                        onReorder: (oldIndex, newIndex) =>
                            _onReorder(glazes, ordered, oldIndex, newIndex),
                        proxyDecorator: materialDragProxy,
                        itemBuilder: (context, index) =>
                            row(filtered[index], index),
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Future<void> _showAddDialog(AppLocalizations l10n) async {
    final controller = TextEditingController();
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l10n.addNew),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            placeholder: l10n.enterGlazeName,
            textCapitalization: TextCapitalization.sentences,
            autocorrect: false,
            inputFormatters: [
              LengthLimitingTextInputFormatter(AppSizes.maxGlazeNameLength),
            ],
            onSubmitted: (value) => Navigator.of(ctx).pop(value),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l10n.create),
          ),
        ],
      ),
    );

    if (name != null && name.trim().isNotEmpty) {
      await ref.read(materialWriterProvider).glaze(name);
    }
  }

  Future<void> _showEditDialog(AppLocalizations l10n, GlazeOption glaze) async {
    final controller = TextEditingController(text: glaze.name);
    final newName = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l10n.editGlazeName),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            autocorrect: false,
            inputFormatters: [
              LengthLimitingTextInputFormatter(AppSizes.maxGlazeNameLength),
            ],
            onSubmitted: (value) => Navigator.of(ctx).pop(value),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );

    if (newName != null &&
        newName.trim().isNotEmpty &&
        newName.trim() != glaze.name) {
      await ref.read(materialsDaoProvider).updateGlazeName(glaze.id, newName);
      await ref.read(syncTriggerProvider).afterGlazeWrite(glaze.id);
    }
  }

  Future<void> _showDeleteDialog(
    AppLocalizations l10n,
    GlazeOption glaze,
  ) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l10n.deleteGlazeConfirmTitle),
        content: Text(l10n.deleteGlazeConfirmMessage),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(materialsDaoProvider).deleteGlaze(glaze.id);
      await ref
          .read(syncTriggerProvider)
          .afterMaterialDeletion('glazes', glaze.id);
    }
  }
}
