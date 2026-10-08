import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../database/database.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/materials_provider.dart';
import '../../../providers/sync_provider.dart';
import '../widgets/material_reorder.dart';

class ManageTagsScreen extends ConsumerStatefulWidget {
  const ManageTagsScreen({super.key});

  @override
  ConsumerState<ManageTagsScreen> createState() => _ManageTagsScreenState();
}

class _ManageTagsScreenState extends ConsumerState<ManageTagsScreen> {
  final _searchCtrl = TextEditingController();
  List<TagOption>? _pendingOrder;
  List<TagOption>? _pendingBase;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Moves a row of [shown] — the list on screen, which a drag not yet saved
  /// may have reordered — and saves the whole order. [stored] is the list the
  /// stream last delivered.
  Future<void> _onReorder(
    List<TagOption> stored,
    List<TagOption> shown,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex--;
    final reordered = List<TagOption>.of(shown);
    reordered.insert(newIndex, reordered.removeAt(oldIndex));
    setState(() {
      _pendingOrder = reordered;
      _pendingBase = stored;
    });
    await ref.read(materialWriterProvider).reorderTags([
      for (final tag in reordered) tag.id,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tagsAsync = ref.watch(allTagsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.manageTags),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddDialog(l10n),
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

          final ordered = withPendingOrder(
            tags,
            pending: _pendingOrder,
            pendingBase: _pendingBase,
          );
          final query = _searchCtrl.text.toLowerCase();
          // A search shows a subset, where a drag has no well-defined place in
          // the whole list, so reordering is offered only on the full list.
          final searching = query.isNotEmpty;
          final filtered = searching
              ? ordered
                    .where((t) => t.name.toLowerCase().contains(query))
                    .toList()
              : ordered;

          Widget row(TagOption tag, int index) {
            return Card(
              key: ValueKey(tag.id),
              margin: const EdgeInsets.symmetric(vertical: AppSizes.xs),
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.xs),
                child: Row(
                  children: [
                    if (searching)
                      const SizedBox(width: AppSizes.sm)
                    else
                      MaterialDragHandle(index: index),
                    const SizedBox(width: AppSizes.sm),
                    GestureDetector(
                      onTap: () => _showColorPicker(tag),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _showEditDialog(l10n, tag),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _showDeleteDialog(l10n, tag),
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
                  placeholder: l10n.searchTags,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.md,
                  vertical: AppSizes.xs,
                ),
                child: Text(
                  l10n.manageTagsSubtitle,
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
                            _onReorder(tags, ordered, oldIndex, newIndex),
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

  Future<void> _showColorPicker(TagOption tag) async {
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
                  final isSelected =
                      currentColor != null &&
                      color.toARGB32() == currentColor.toARGB32();
                  return GestureDetector(
                    onTap: () {
                      ref
                          .read(materialsDaoProvider)
                          .updateTagColor(
                            tag.id,
                            TagColorPresets.colorToHex(color),
                          );
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
                            ? Border.all(color: AppColors.charcoal, width: 2.5)
                            : Border.all(color: AppColors.divider, width: 1),
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 20,
                            )
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
            placeholder: l10n.enterTagName,
            textCapitalization: TextCapitalization.sentences,
            autocorrect: false,
            inputFormatters: [
              LengthLimitingTextInputFormatter(AppSizes.maxTagNameLength),
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
      await ref.read(materialWriterProvider).tag(name);
    }
  }

  Future<void> _showEditDialog(AppLocalizations l10n, TagOption tag) async {
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
            inputFormatters: [
              LengthLimitingTextInputFormatter(AppSizes.maxTagNameLength),
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
        newName.trim() != tag.name) {
      await ref.read(materialsDaoProvider).updateTagName(tag.id, newName);
      await ref.read(syncTriggerProvider).afterTagWrite(tag.id);
    }
  }

  Future<void> _showDeleteDialog(AppLocalizations l10n, TagOption tag) async {
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
