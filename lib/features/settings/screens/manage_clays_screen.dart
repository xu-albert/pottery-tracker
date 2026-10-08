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

class ManageClaysScreen extends ConsumerStatefulWidget {
  const ManageClaysScreen({super.key});

  @override
  ConsumerState<ManageClaysScreen> createState() => _ManageClaysScreenState();
}

class _ManageClaysScreenState extends ConsumerState<ManageClaysScreen> {
  final _searchCtrl = TextEditingController();
  List<ClayOption>? _pendingOrder;
  List<ClayOption>? _pendingBase;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Moves a row of [shown] — the list on screen, which a drag not yet saved
  /// may have reordered — and saves the whole order. [stored] is the list the
  /// stream last delivered.
  Future<void> _onReorder(
    List<ClayOption> stored,
    List<ClayOption> shown,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex--;
    final reordered = List<ClayOption>.of(shown);
    reordered.insert(newIndex, reordered.removeAt(oldIndex));
    setState(() {
      _pendingOrder = reordered;
      _pendingBase = stored;
    });
    await ref.read(materialWriterProvider).reorderClays([
      for (final clay in reordered) clay.id,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final claysAsync = ref.watch(allClaysProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.manageClays),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddDialog(l10n),
          ),
        ],
      ),
      body: claysAsync.when(
        data: (clays) {
          if (clays.isEmpty) {
            return Center(
              child: Text(
                l10n.noClaysYet,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }

          final ordered = withPendingOrder(
            clays,
            pending: _pendingOrder,
            pendingBase: _pendingBase,
          );
          final query = _searchCtrl.text.toLowerCase();
          // A search shows a subset, where a drag has no well-defined place in
          // the whole list, so reordering is offered only on the full list.
          final searching = query.isNotEmpty;
          final filtered = searching
              ? ordered
                    .where((c) => c.name.toLowerCase().contains(query))
                    .toList()
              : ordered;

          Widget row(ClayOption clay, int index) {
            return Card(
              key: ValueKey(clay.id),
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
                        clay.name,
                        style: Theme.of(context).textTheme.bodyLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _showEditDialog(l10n, clay),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _showDeleteDialog(l10n, clay),
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
                  placeholder: l10n.searchClays,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.md,
                  vertical: AppSizes.xs,
                ),
                child: Text(
                  l10n.manageClaysSubtitle,
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
                            _onReorder(clays, ordered, oldIndex, newIndex),
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
            placeholder: l10n.enterClayName,
            textCapitalization: TextCapitalization.sentences,
            autocorrect: false,
            inputFormatters: [
              LengthLimitingTextInputFormatter(AppSizes.maxClayNameLength),
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
      await ref.read(materialWriterProvider).clay(name);
    }
  }

  Future<void> _showEditDialog(AppLocalizations l10n, ClayOption clay) async {
    final controller = TextEditingController(text: clay.name);
    final newName = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l10n.editClayName),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            autocorrect: false,
            inputFormatters: [
              LengthLimitingTextInputFormatter(AppSizes.maxClayNameLength),
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
        newName.trim() != clay.name) {
      await ref.read(materialWriterProvider).renameClay(clay.id, newName);
    }
  }

  Future<void> _showDeleteDialog(AppLocalizations l10n, ClayOption clay) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l10n.deleteClayConfirmTitle),
        content: Text(l10n.deleteClayConfirmMessage),
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
      await ref.read(materialsDaoProvider).deleteClay(clay.id);
      await ref
          .read(syncTriggerProvider)
          .afterMaterialDeletion('clays', clay.id);
    }
  }
}
