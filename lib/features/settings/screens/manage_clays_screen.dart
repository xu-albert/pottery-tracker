import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../database/database.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/materials_provider.dart';
import '../../../providers/sync_provider.dart';

class ManageClaysScreen extends ConsumerStatefulWidget {
  const ManageClaysScreen({super.key});

  @override
  ConsumerState<ManageClaysScreen> createState() => _ManageClaysScreenState();
}

class _ManageClaysScreenState extends ConsumerState<ManageClaysScreen> {
  final _searchCtrl = TextEditingController();
  List<String> _recentClayNames = [];

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    final names = await ref
        .read(materialsDaoProvider)
        .getRecentClayNames(limit: 100);
    if (mounted) setState(() => _recentClayNames = names);
  }

  List<ClayOption> _sortByRecency(List<ClayOption> clays) {
    final recentSet = _recentClayNames.toSet();
    final sorted = List<ClayOption>.of(clays);
    sorted.sort((a, b) {
      final aRecent = recentSet.contains(a.name);
      final bRecent = recentSet.contains(b.name);
      if (aRecent && !bRecent) return -1;
      if (!aRecent && bRecent) return 1;
      if (aRecent && bRecent) {
        return _recentClayNames.indexOf(a.name)
            .compareTo(_recentClayNames.indexOf(b.name));
      }
      return a.sortOrder.compareTo(b.sortOrder);
    });
    return sorted;
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

          final query = _searchCtrl.text.toLowerCase();
          final sorted = _sortByRecency(clays);
          final filtered = query.isEmpty
              ? sorted
              : sorted
                  .where((c) => c.name.toLowerCase().contains(query))
                  .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.md, AppSizes.sm, AppSizes.md, 0,
                ),
                child: CupertinoSearchTextField(
                  controller: _searchCtrl,
                  placeholder: l10n.searchClays,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.md, vertical: AppSizes.xs,
                ),
                child: Text(
                  l10n.manageClaysSubtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSizes.xs,
                    horizontal: AppSizes.md,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final clay = filtered[index];
                    return Card(
                      key: ValueKey(clay.id),
                      margin: const EdgeInsets.symmetric(vertical: AppSizes.xs),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSizes.xs),
                        child: Row(
                          children: [
                            const SizedBox(width: AppSizes.sm),
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
                              onPressed: () =>
                                  _showEditDialog(l10n, clay),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  _showDeleteDialog(l10n, clay),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
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
      final clay = await ref.read(materialsDaoProvider).findOrCreateClay(name);
      await ref.read(syncTriggerProvider).afterClayWrite(clay.id);
    }
  }

  Future<void> _showEditDialog(
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
      await ref.read(materialsDaoProvider).updateClayName(clay.id, newName);
      await ref.read(syncTriggerProvider).afterClayWrite(clay.id);
    }
  }

  Future<void> _showDeleteDialog(
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
