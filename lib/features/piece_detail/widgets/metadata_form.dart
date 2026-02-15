import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../database/database.dart';
import '../../../database/daos/materials_dao.dart';
import '../../../models/piece_stage.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';

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
  }) onUpdateField;
  final void Function(List<String> glazeOptionIds) onUpdateGlazes;
  final void Function(List<String> tagOptionIds) onUpdateTags;

  const MetadataForm({
    super.key,
    required this.piece,
    required this.materialsDao,
    required this.selectedGlazes,
    required this.selectedTags,
    required this.onUpdateField,
    required this.onUpdateGlazes,
    required this.onUpdateTags,
  });

  @override
  State<MetadataForm> createState() => MetadataFormState();
}

class MetadataFormState extends State<MetadataForm> {
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController(text: widget.piece.notes ?? '');
  }

  @override
  void didUpdateWidget(MetadataForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.piece.id != widget.piece.id) {
      _notesCtrl.text = widget.piece.notes ?? '';
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  PieceStage? get _currentStage {
    final s = widget.piece.stage;
    if (s == null) return null;
    return PieceStage.values.where((e) => e.name == s).firstOrNull;
  }

  void saveAll() {
    widget.onUpdateField(
      clayType: widget.piece.clayType,
      notes: _notesCtrl.text,
    );
  }

  Future<void> _showClayPicker() async {
    final l10n = AppLocalizations.of(context)!;
    final clays = await widget.materialsDao.getAllClays();

    if (!mounted) return;

    final result = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop(''),
            child: Text(l10n.stageNone),
          ),
          ...clays.map((c) => CupertinoActionSheetAction(
                onPressed: () => Navigator.of(ctx).pop(c.name),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(c.name),
                    if (c.name == widget.piece.clayType) ...[
                      const SizedBox(width: 8),
                      const Icon(CupertinoIcons.checkmark_alt, size: 18),
                    ],
                  ],
                ),
              )),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(ctx).pop('__add_new__'),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(CupertinoIcons.add, size: 18),
                const SizedBox(width: 8),
                Text(l10n.addNew),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l10n.cancel),
        ),
      ),
    );

    if (!mounted || result == null) return;
    if (result == '__add_new__') {
      await _showAddClayDialog();
    } else {
      widget.onUpdateField(clayType: result);
    }
  }

  Future<void> _showAddClayDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
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
        );
      },
    );
    // Don't dispose controller here — the dialog's TextField may still be
    // animating out and referencing it, which triggers _dependents.isEmpty.
    // The controller is a local variable and will be GC'd.

    if (!mounted) return;
    if (name != null && name.trim().isNotEmpty) {
      await widget.materialsDao.findOrCreateClay(name);
      FirebaseAnalytics.instance.logEvent(
        name: 'material_created',
        parameters: {'type': 'clay'},
      );
      if (!mounted) return;
      widget.onUpdateField(clayType: name.trim());
    }
  }

  Future<void> _showGlazePicker() async {
    final l10n = AppLocalizations.of(context)!;
    final allGlazes = await widget.materialsDao.getAllGlazes();

    if (!mounted) return;

    // Track selected IDs locally in the bottom sheet
    final selectedIds = widget.selectedGlazes.map((g) => g.id).toSet();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  const Divider(height: 1),
                  // "None" option
                  CheckboxListTile(
                    title: Text(l10n.glazesNone),
                    value: selectedIds.isEmpty,
                    onChanged: (_) {
                      setSheetState(() => selectedIds.clear());
                    },
                  ),
                  // Glaze options
                  ...allGlazes.map((glaze) => CheckboxListTile(
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
                      )),
                  const Divider(height: 1),
                  // Add new
                  ListTile(
                    leading: const Icon(CupertinoIcons.add),
                    title: Text(l10n.addNew),
                    onTap: () async {
                      final newGlaze = await _showAddGlazeDialog();
                      if (newGlaze != null) {
                        // Refresh the list and add the new glaze to selection
                        final refreshed =
                            await widget.materialsDao.getAllGlazes();
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

    // Save on any dismiss (Done button, tap outside, back gesture)
    if (mounted) {
      widget.onUpdateGlazes(selectedIds.toList());
    }
  }

  Future<GlazeOption?> _showAddGlazeDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
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
        );
      },
    );

    if (!mounted) return null;
    if (name != null && name.trim().isNotEmpty) {
      final glaze = await widget.materialsDao.findOrCreateGlaze(name);
      FirebaseAnalytics.instance.logEvent(
        name: 'material_created',
        parameters: {'type': 'glaze'},
      );
      return glaze;
    }
    return null;
  }

  Future<void> _showTagPicker() async {
    final l10n = AppLocalizations.of(context)!;
    final allTags = await widget.materialsDao.getAllTags();

    if (!mounted) return;

    final selectedIds = widget.selectedTags.map((t) => t.id).toSet();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  const Divider(height: 1),
                  CheckboxListTile(
                    title: Text(l10n.tagsNone),
                    value: selectedIds.isEmpty,
                    onChanged: (_) {
                      setSheetState(() => selectedIds.clear());
                    },
                  ),
                  ...allTags.map((tag) => CheckboxListTile(
                        title: Row(
                          children: [
                            if (tag.color != null) ...[
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: TagColorPresets.hexToColor(tag.color!),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.divider,
                                    width: 1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(tag.name),
                          ],
                        ),
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
                      )),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(CupertinoIcons.add),
                    title: Text(l10n.addNew),
                    onTap: () async {
                      final newTag = await _showAddTagDialog();
                      if (newTag != null) {
                        final refreshed =
                            await widget.materialsDao.getAllTags();
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

    // Save on any dismiss (Done button, tap outside, back gesture)
    if (mounted) {
      widget.onUpdateTags(selectedIds.toList());
    }
  }

  Future<TagOption?> _showAddTagDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
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
        );
      },
    );

    if (!mounted) return null;
    if (name != null && name.trim().isNotEmpty) {
      final tag = await widget.materialsDao.findOrCreateTag(name);
      FirebaseAnalytics.instance.logEvent(
        name: 'material_created',
        parameters: {'type': 'tag'},
      );
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
              ...PieceStage.values.map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(s.displayName),
                  )),
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

          // Clay picker
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
          const SizedBox(height: AppSizes.md),

          // Glazes multi-select picker
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
          const SizedBox(height: AppSizes.md),

          // Tags multi-select picker
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
          const SizedBox(height: AppSizes.md),

          // Notes
          TextField(
            controller: _notesCtrl,
            decoration: InputDecoration(labelText: l10n.notesLabel),
            maxLines: 3,
            autocorrect: false,
            onEditingComplete: () =>
                widget.onUpdateField(notes: _notesCtrl.text),
          ),
        ],
      ),
    );
  }
}
