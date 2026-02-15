import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../database/database.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/materials_provider.dart';
import '../../../providers/sync_provider.dart';

class ManageTagsScreen extends ConsumerWidget {
  const ManageTagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final tagsAsync = ref.watch(allTagsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.manageTags),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddDialog(context, ref, l10n),
          ),
        ],
      ),
      body: tagsAsync.when(
        data: (tags) {
          if (tags.isEmpty) {
            return Center(
              child: Text(
                l10n.noTagsYet,
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
            itemCount: tags.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex--;
              final reordered = List<TagOption>.of(tags);
              final item = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, item);
              final updates = <({String id, int sortOrder})>[];
              for (var i = 0; i < reordered.length; i++) {
                updates.add((id: reordered[i].id, sortOrder: i));
              }
              ref.read(materialsDaoProvider).updateTagSortOrders(updates);
              final trigger = ref.read(syncTriggerProvider);
              for (final entry in updates) {
                trigger.afterTagWrite(entry.id);
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
              final tag = tags[index];
              return Card(
                key: ValueKey(tag.id),
                margin: const EdgeInsets.symmetric(vertical: AppSizes.xs),
                child: Padding(
                  padding: const EdgeInsets.all(AppSizes.xs),
                  child: Row(
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(AppSizes.sm),
                          child: Icon(Icons.drag_handle,
                              color: AppColors.inputText),
                        ),
                      ),
                      const SizedBox(width: AppSizes.sm),
                      GestureDetector(
                        onTap: () =>
                            _showColorPicker(context, ref, tag),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: tag.color != null
                                ? TagColorPresets.hexToColor(tag.color!)
                                : AppColors.inputText.withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.divider,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSizes.sm),
                      Expanded(
                        child: Text(
                          tag.name,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () =>
                            _showEditDialog(context, ref, l10n, tag),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () =>
                            _showDeleteDialog(context, ref, l10n, tag),
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

  Future<void> _showColorPicker(
      BuildContext context, WidgetRef ref, TagOption tag) async {
    final currentColor = tag.color != null
        ? TagColorPresets.hexToColor(tag.color!)
        : null;

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.tagColor,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSizes.md),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: TagColorPresets.colors.map((color) {
                  final isSelected = currentColor != null &&
                      color.toARGB32() == currentColor.toARGB32();
                  return GestureDetector(
                    onTap: () {
                      ref.read(materialsDaoProvider).updateTagColor(
                            tag.id, TagColorPresets.colorToHex(color));
                      ref.read(syncTriggerProvider).afterTagWrite(tag.id);
                      Navigator.of(ctx).pop();
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(
                                color: AppColors.charcoal, width: 2.5)
                            : Border.all(
                                color: AppColors.divider, width: 1),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 20)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSizes.md),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddDialog(
      BuildContext context, WidgetRef ref, AppLocalizations l10n) async {
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
            placeholder: l10n.enterTagName,
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
      final tag = await ref.read(materialsDaoProvider).findOrCreateTag(name);
      await ref.read(syncTriggerProvider).afterTagWrite(tag.id);
    }
  }

  Future<void> _showEditDialog(BuildContext context, WidgetRef ref,
      AppLocalizations l10n, TagOption tag) async {
    final controller = TextEditingController(text: tag.name);
    final newName = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l10n.editTagName),
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
        newName.trim() != tag.name) {
      await ref.read(materialsDaoProvider).updateTagName(tag.id, newName);
      await ref.read(syncTriggerProvider).afterTagWrite(tag.id);
    }
  }

  Future<void> _showDeleteDialog(BuildContext context, WidgetRef ref,
      AppLocalizations l10n, TagOption tag) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l10n.deleteTagConfirmTitle),
        content: Text(l10n.deleteTagConfirmMessage),
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
      await ref.read(materialsDaoProvider).deleteTag(tag.id);
      await ref.read(syncTriggerProvider).afterMaterialDeletion('tags', tag.id);
    }
  }
}
