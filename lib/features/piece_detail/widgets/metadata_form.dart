import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../database/database.dart';
import '../../../database/daos/materials_dao.dart';
import '../../../models/piece_stage.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../services/sync_trigger.dart';

class MetadataForm extends StatefulWidget {
  final Piece piece;
  final MaterialsDao materialsDao;
  final List<GlazeOption> selectedGlazes;
  final List<TagOption> selectedTags;
  final void Function({
    String? title,
    PieceStage? stage,
    bool clearStage,
    String? clayType,
    String? notes,
  })
  onUpdateField;
  final Future<void> Function(List<String> glazeOptionIds) onUpdateGlazes;
  final Future<void> Function(List<String> tagOptionIds) onUpdateTags;
  final SyncTrigger syncTrigger;

  const MetadataForm({
    super.key,
    required this.piece,
    required this.materialsDao,
    required this.selectedGlazes,
    required this.selectedTags,
    required this.onUpdateField,
    required this.onUpdateGlazes,
    required this.onUpdateTags,
    required this.syncTrigger,
  });

  @override
  State<MetadataForm> createState() => MetadataFormState();
}

class MetadataFormState extends State<MetadataForm> {
  late final TextEditingController _notesCtrl;
  List<String> _recentClayNames = [];
  List<GlazeOption> _recentGlazes = [];
  List<TagOption> _recentTags = [];

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController(text: widget.piece.notes ?? '');
    _loadRecents();
  }

  @override
  void didUpdateWidget(MetadataForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.piece.id != widget.piece.id) {
      _notesCtrl.text = widget.piece.notes ?? '';
      _loadRecents();
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    final recentClayNames = await widget.materialsDao.getRecentClayNames();
    final recentGlazeIds = await widget.materialsDao.getRecentGlazeIds();
    final recentTagIds = await widget.materialsDao.getRecentTagIds();
    final allGlazes = await widget.materialsDao.getAllGlazes();
    final allTags = await widget.materialsDao.getAllTags();

    if (!mounted) return;
    setState(() {
      _recentClayNames = recentClayNames;
      _recentGlazes = recentGlazeIds
          .map((id) => allGlazes.where((g) => g.id == id).firstOrNull)
          .whereType<GlazeOption>()
          .toList();
      _recentTags = recentTagIds
          .map((id) => allTags.where((t) => t.id == id).firstOrNull)
          .whereType<TagOption>()
          .toList();
    });
  }

  PieceStage? get _currentStage {
    final s = widget.piece.stage;
    if (s == null) return null;
    return PieceStage.values.where((e) => e.name == s).firstOrNull;
  }

  Future<void> saveAll() async {
    widget.onUpdateField(
      clayType: widget.piece.clayType,
      notes: _notesCtrl.text,
    );
  }

  // ── Clay Picker ──

  Future<void> _showClayPicker() async {
    final l10n = AppLocalizations.of(context)!;
    final clays = await widget.materialsDao.getAllClays();

    if (!mounted) return;

    // Sort by recency: recently used clays first, then the rest
    final recentNames = _recentClayNames.toSet();
    clays.sort((a, b) {
      final aRecent = recentNames.contains(a.name);
      final bRecent = recentNames.contains(b.name);
      if (aRecent && !bRecent) return -1;
      if (!aRecent && bRecent) return 1;
      if (aRecent && bRecent) {
        return _recentClayNames
            .indexOf(a.name)
            .compareTo(_recentClayNames.indexOf(b.name));
      }
      return a.sortOrder.compareTo(b.sortOrder);
    });

    final searchCtrl = TextEditingController();

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final query = searchCtrl.text.toLowerCase();
          final filtered = query.isEmpty
              ? clays
              : clays
                    .where((c) => c.name.toLowerCase().contains(query))
                    .toList();

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.selectClay,
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(l10n.done),
                        ),
                      ],
                    ),
                  ),
                  // Search field
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: CupertinoSearchTextField(
                      controller: searchCtrl,
                      placeholder: l10n.searchClays,
                      onChanged: (_) => setSheetState(() {}),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Divider(height: 1),
                  // "None" option (hidden during search)
                  if (query.isEmpty)
                    ListTile(
                      title: Text(l10n.stageNone),
                      trailing:
                          (widget.piece.clayType == null ||
                              widget.piece.clayType!.isEmpty)
                          ? const Icon(CupertinoIcons.checkmark_alt, size: 18)
                          : null,
                      onTap: () => Navigator.of(ctx).pop(''),
                    ),
                  // Clay options (scrollable)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.35,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final clay = filtered[i];
                        final isSelected = clay.name == widget.piece.clayType;
                        return ListTile(
                          title: Text(clay.name),
                          trailing: isSelected
                              ? const Icon(
                                  CupertinoIcons.checkmark_alt,
                                  size: 18,
                                )
                              : null,
                          onTap: () => Navigator.of(ctx).pop(clay.name),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  // Add new
                  ListTile(
                    leading: const Icon(CupertinoIcons.add),
                    title: Text(
                      query.isNotEmpty
                          ? l10n.addNewWithName(searchCtrl.text.trim())
                          : l10n.addNew,
                    ),
                    onTap: () async {
                      final name = await _showAddClayDialog(
                        initialName: query.isNotEmpty
                            ? searchCtrl.text.trim()
                            : null,
                      );
                      if (name != null && ctx.mounted) {
                        Navigator.of(ctx).pop(name);
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    searchCtrl.dispose();

    if (!mounted || result == null) return;
    if (result.isNotEmpty) {
      final clay = await widget.materialsDao.findOrCreateClay(result);
      await widget.syncTrigger.afterClayWrite(clay.id);
    }
    widget.onUpdateField(clayType: result);
  }

  Future<String?> _showAddClayDialog({String? initialName}) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: initialName ?? '');
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) {
        return CupertinoAlertDialog(
          title: Text(l10n.addNew),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: CupertinoTextField(
              controller: controller,
              autofocus: true,
              placeholder: l10n.enterClayName,
              textCapitalization: TextCapitalization.words,
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
        );
      },
    );

    if (!mounted) return null;
    if (name != null && name.trim().isNotEmpty) {
      final clay = await widget.materialsDao.findOrCreateClay(name);
      await widget.syncTrigger.afterClayWrite(clay.id);
      return name.trim();
    }
    return null;
  }

  // ── Glaze Picker ──

  Future<void> _showGlazePicker() async {
    final l10n = AppLocalizations.of(context)!;
    final allGlazes = await widget.materialsDao.getAllGlazes();

    if (!mounted) return;

    // Sort by recency: recently used glazes first, then the rest
    final recentGlazeIds = _recentGlazes.map((g) => g.id).toList();
    final recentGlazeIdSet = recentGlazeIds.toSet();
    allGlazes.sort((a, b) {
      final aRecent = recentGlazeIdSet.contains(a.id);
      final bRecent = recentGlazeIdSet.contains(b.id);
      if (aRecent && !bRecent) return -1;
      if (!aRecent && bRecent) return 1;
      if (aRecent && bRecent) {
        return recentGlazeIds
            .indexOf(a.id)
            .compareTo(recentGlazeIds.indexOf(b.id));
      }
      return a.sortOrder.compareTo(b.sortOrder);
    });

    final selectedIds = widget.selectedGlazes.map((g) => g.id).toSet();
    final searchCtrl = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final query = searchCtrl.text.toLowerCase();
          final filtered = query.isEmpty
              ? allGlazes
              : allGlazes
                    .where((g) => g.name.toLowerCase().contains(query))
                    .toList();

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.selectGlazes,
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(l10n.done),
                        ),
                      ],
                    ),
                  ),
                  // Search field
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: CupertinoSearchTextField(
                      controller: searchCtrl,
                      placeholder: l10n.searchGlazes,
                      onChanged: (_) => setSheetState(() {}),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Divider(height: 1),
                  // "None" option (hidden during search)
                  if (query.isEmpty)
                    CheckboxListTile(
                      title: Text(l10n.glazesNone),
                      value: selectedIds.isEmpty,
                      onChanged: (_) {
                        setSheetState(() => selectedIds.clear());
                      },
                    ),
                  // Glaze options (scrollable)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.35,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final glaze = filtered[i];
                        return CheckboxListTile(
                          title: Text(glaze.name),
                          value: selectedIds.contains(glaze.id),
                          onChanged: (checked) {
                            setSheetState(() {
                              if (checked == true) {
                                selectedIds.add(glaze.id);
                              } else {
                                selectedIds.remove(glaze.id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  // Add new
                  ListTile(
                    leading: const Icon(CupertinoIcons.add),
                    title: Text(
                      query.isNotEmpty
                          ? l10n.addNewWithName(searchCtrl.text.trim())
                          : l10n.addNew,
                    ),
                    onTap: () async {
                      final newGlaze = await _showAddGlazeDialog(
                        initialName: query.isNotEmpty
                            ? searchCtrl.text.trim()
                            : null,
                      );
                      if (newGlaze != null) {
                        final refreshed = await widget.materialsDao
                            .getAllGlazes();
                        setSheetState(() {
                          allGlazes
                            ..clear()
                            ..addAll(refreshed);
                          selectedIds.add(newGlaze.id);
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    searchCtrl.dispose();

    // Save on any dismiss
    if (mounted) {
      await widget.onUpdateGlazes(selectedIds.toList());
    }
  }

  Future<GlazeOption?> _showAddGlazeDialog({String? initialName}) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: initialName ?? '');
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) {
        return CupertinoAlertDialog(
          title: Text(l10n.addNew),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: CupertinoTextField(
              controller: controller,
              autofocus: true,
              placeholder: l10n.enterGlazeName,
              textCapitalization: TextCapitalization.words,
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
        );
      },
    );

    if (!mounted) return null;
    if (name != null && name.trim().isNotEmpty) {
      final glaze = await widget.materialsDao.findOrCreateGlaze(name);
      await widget.syncTrigger.afterGlazeWrite(glaze.id);
      return glaze;
    }
    return null;
  }

  // ── Tag Picker ──

  Future<void> _showTagPicker() async {
    final l10n = AppLocalizations.of(context)!;
    final allTags = await widget.materialsDao.getAllTags();

    if (!mounted) return;

    // Sort by recency: recently used tags first, then the rest
    final recentTagIds = _recentTags.map((t) => t.id).toList();
    final recentTagIdSet = recentTagIds.toSet();
    allTags.sort((a, b) {
      final aRecent = recentTagIdSet.contains(a.id);
      final bRecent = recentTagIdSet.contains(b.id);
      if (aRecent && !bRecent) return -1;
      if (!aRecent && bRecent) return 1;
      if (aRecent && bRecent) {
        return recentTagIds.indexOf(a.id).compareTo(recentTagIds.indexOf(b.id));
      }
      return a.sortOrder.compareTo(b.sortOrder);
    });

    final selectedIds = widget.selectedTags.map((t) => t.id).toSet();
    final searchCtrl = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final query = searchCtrl.text.toLowerCase();
          final filtered = query.isEmpty
              ? allTags
              : allTags
                    .where((t) => t.name.toLowerCase().contains(query))
                    .toList();

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.selectTags,
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(l10n.done),
                        ),
                      ],
                    ),
                  ),
                  // Search field
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: CupertinoSearchTextField(
                      controller: searchCtrl,
                      placeholder: l10n.searchTags,
                      onChanged: (_) => setSheetState(() {}),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Divider(height: 1),
                  // "None" option (hidden during search)
                  if (query.isEmpty)
                    CheckboxListTile(
                      title: Text(l10n.tagsNone),
                      value: selectedIds.isEmpty,
                      onChanged: (_) {
                        setSheetState(() => selectedIds.clear());
                      },
                    ),
                  // Tag options (scrollable)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.35,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final tag = filtered[i];
                        final tagColor = tag.color != null
                            ? TagColorPresets.hexToColor(tag.color!)
                            : null;
                        return CheckboxListTile(
                          secondary: tagColor != null
                              ? Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: tagColor,
                                    shape: BoxShape.circle,
                                  ),
                                )
                              : null,
                          title: Text(tag.name),
                          value: selectedIds.contains(tag.id),
                          onChanged: (checked) {
                            setSheetState(() {
                              if (checked == true) {
                                selectedIds.add(tag.id);
                              } else {
                                selectedIds.remove(tag.id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  // Add new
                  ListTile(
                    leading: const Icon(CupertinoIcons.add),
                    title: Text(
                      query.isNotEmpty
                          ? l10n.addNewWithName(searchCtrl.text.trim())
                          : l10n.addNew,
                    ),
                    onTap: () async {
                      final newTag = await _showAddTagDialog(
                        initialName: query.isNotEmpty
                            ? searchCtrl.text.trim()
                            : null,
                      );
                      if (newTag != null) {
                        final refreshed = await widget.materialsDao
                            .getAllTags();
                        setSheetState(() {
                          allTags
                            ..clear()
                            ..addAll(refreshed);
                          selectedIds.add(newTag.id);
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    searchCtrl.dispose();

    // Save on any dismiss
    if (mounted) {
      await widget.onUpdateTags(selectedIds.toList());
    }
  }

  Future<TagOption?> _showAddTagDialog({String? initialName}) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: initialName ?? '');
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) {
        return CupertinoAlertDialog(
          title: Text(l10n.addNew),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: CupertinoTextField(
              controller: controller,
              autofocus: true,
              placeholder: l10n.enterTagName,
              textCapitalization: TextCapitalization.words,
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
        );
      },
    );

    if (!mounted) return null;
    if (name != null && name.trim().isNotEmpty) {
      final tag = await widget.materialsDao.findOrCreateTag(name);
      await widget.syncTrigger.afterTagWrite(tag.id);
      return tag;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentClay = widget.piece.clayType;
    final clayDisplay = (currentClay != null && currentClay.isNotEmpty)
        ? currentClay
        : l10n.stageNone;

    final glazeDisplay = widget.selectedGlazes.isNotEmpty
        ? widget.selectedGlazes.map((g) => g.name).join(', ')
        : l10n.glazesNone;

    final tagDisplay = widget.selectedTags.isNotEmpty
        ? widget.selectedTags.map((t) => t.name).join(', ')
        : l10n.tagsNone;

    final selectedGlazeIds = widget.selectedGlazes.map((g) => g.id).toSet();
    final selectedTagIds = widget.selectedTags.map((t) => t.id).toSet();

    // Pills: clay pills only when no clay is selected (single-select)
    final unselectedRecentClays = (currentClay == null || currentClay.isEmpty)
        ? _recentClayNames
        : <String>[];
    final unselectedRecentGlazes = _recentGlazes
        .where((g) => !selectedGlazeIds.contains(g.id))
        .toList();
    final unselectedRecentTags = _recentTags
        .where((t) => !selectedTagIds.contains(t.id))
        .toList();

    return Padding(
      padding: const EdgeInsets.all(AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stage dropdown
          DropdownButtonFormField<PieceStage?>(
            initialValue: _currentStage,
            decoration: InputDecoration(labelText: l10n.stageLabel),
            items: [
              DropdownMenuItem<PieceStage?>(
                value: null,
                child: Text(l10n.stageNone),
              ),
              ...PieceStage.values.map(
                (s) => DropdownMenuItem(value: s, child: Text(s.displayName)),
              ),
            ],
            onChanged: (value) {
              if (value == null) {
                widget.onUpdateField(clearStage: true);
              } else {
                widget.onUpdateField(stage: value);
              }
            },
          ),
          const SizedBox(height: AppSizes.md),

          // Clay picker dropdown
          GestureDetector(
            onTap: _showClayPicker,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: l10n.clayTypeLabel,
                suffixIcon: const Icon(Icons.arrow_drop_down),
              ),
              child: Text(
                clayDisplay,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
          if (unselectedRecentClays.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: unselectedRecentClays.map((name) {
                  return ActionChip(
                    label: Text(name),
                    onPressed: () async {
                      final clay = await widget.materialsDao.findOrCreateClay(
                        name,
                      );
                      await widget.syncTrigger.afterClayWrite(clay.id);
                      widget.onUpdateField(clayType: name);
                    },
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: AppSizes.md),

          // Glazes picker dropdown
          GestureDetector(
            onTap: _showGlazePicker,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: l10n.glazesLabel,
                suffixIcon: const Icon(Icons.arrow_drop_down),
              ),
              child: Text(
                glazeDisplay,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
          if (unselectedRecentGlazes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: unselectedRecentGlazes.map((glaze) {
                  return ActionChip(
                    label: Text(glaze.name),
                    onPressed: () async {
                      final ids =
                          widget.selectedGlazes.map((g) => g.id).toList()
                            ..add(glaze.id);
                      await widget.onUpdateGlazes(ids);
                    },
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: AppSizes.md),

          // Tags picker dropdown
          GestureDetector(
            onTap: _showTagPicker,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: l10n.tagsLabel,
                suffixIcon: const Icon(Icons.arrow_drop_down),
              ),
              child: Text(
                tagDisplay,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
          if (unselectedRecentTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: unselectedRecentTags.map((tag) {
                  final tagColor = tag.color != null
                      ? TagColorPresets.hexToColor(tag.color!)
                      : null;
                  return ActionChip(
                    avatar: tagColor != null
                        ? Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: tagColor,
                              shape: BoxShape.circle,
                            ),
                          )
                        : null,
                    label: Text(tag.name),
                    onPressed: () async {
                      final ids = widget.selectedTags.map((t) => t.id).toList()
                        ..add(tag.id);
                      await widget.onUpdateTags(ids);
                    },
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: AppSizes.md),

          // Notes
          TextField(
            controller: _notesCtrl,
            decoration: InputDecoration(labelText: l10n.notesLabel),
            maxLines: 3,
            maxLength: AppSizes.maxNotesLength,
            autocorrect: false,
            onEditingComplete: () =>
                widget.onUpdateField(notes: _notesCtrl.text),
          ),
        ],
      ),
    );
  }
}
