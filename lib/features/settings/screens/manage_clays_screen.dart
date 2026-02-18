import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../database/database.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/materials_provider.dart';
import '../../../providers/sync_provider.dart';

class ManageClaysScreen extends ConsumerWidget {
  const ManageClaysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final claysAsync = ref.watch(allClaysProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.manageClays),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddDialog(context, ref, l10n),
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
          return ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(
              vertical: AppSizes.sm,
              horizontal: AppSizes.md,
            ),
            itemCount: clays.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex--;
              final reordered = List<ClayOption>.of(clays);
              final item = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, item);
              final updates = <({String id, int sortOrder})>[];
              for (var i = 0; i < reordered.length; i++) {
                updates.add((id: reordered[i].id, sortOrder: i));
              }
              ref.read(materialsDaoProvider).updateSortOrders(updates);
              final trigger = ref.read(syncTriggerProvider);
              for (final entry in updates) {
                trigger.afterClayWrite(entry.id);
              }
            },
            proxyDecorator: (child, index, animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  final scale = 1.0 + 0.02 * animation.value;
                  return Transform.scale(
                    scale: scale,
                    child: Material(
                      elevation: 6 * animation.value,
                      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      shadowColor: AppColors.charcoal.withValues(alpha: 0.3),
                      child: child,
                    ),
                  );
                },
                child: child,
              );
            },
            itemBuilder: (context, index) {
              final clay = clays[index];
              return Card(
                key: ValueKey(clay.id),
                margin: const EdgeInsets.symmetric(vertical: AppSizes.xs),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: AppSizes.xs,
                    right: AppSizes.xs,
                    top: AppSizes.xs,
                    bottom: AppSizes.xs,
                  ),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(AppSizes.sm),
                          child: Icon(
                            Icons.drag_handle,
                            color: AppColors.inputText,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSizes.sm),
                      Expanded(
                        child: Text(
                          clay.name,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () =>
                            _showEditDialog(context, ref, l10n, clay),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () =>
                            _showDeleteDialog(context, ref, l10n, clay),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Future<void> _showAddDialog(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
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
      final clay = await ref.read(materialsDaoProvider).findOrCreateClay(name);
      await ref.read(syncTriggerProvider).afterClayWrite(clay.id);
    }
  }

  Future<void> _showEditDialog(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ClayOption clay,
  ) async {
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
      await ref.read(materialsDaoProvider).updateClayName(clay.id, newName);
      await ref.read(syncTriggerProvider).afterClayWrite(clay.id);
    }
  }

  Future<void> _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ClayOption clay,
  ) async {
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
