import 'package:flutter/material.dart';
import '../../../database/database.dart';
import '../../../database/daos/materials_dao.dart';
import '../../../models/piece_stage.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/constants/app_sizes.dart';

class MetadataForm extends StatefulWidget {
  final Piece piece;
  final MaterialsDao materialsDao;
  final void Function({
    String? title,
    PieceStage? stage,
    bool clearStage,
    String? clayType,
    String? glazes,
    String? notes,
  }) onUpdateField;

  const MetadataForm({
    super.key,
    required this.piece,
    required this.materialsDao,
    required this.onUpdateField,
  });

  @override
  State<MetadataForm> createState() => MetadataFormState();
}

class MetadataFormState extends State<MetadataForm> {
  late final TextEditingController _glazesCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _glazesCtrl = TextEditingController(text: widget.piece.glazes ?? '');
    _notesCtrl = TextEditingController(text: widget.piece.notes ?? '');
  }

  @override
  void didUpdateWidget(MetadataForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.piece.id != widget.piece.id) {
      _glazesCtrl.text = widget.piece.glazes ?? '';
      _notesCtrl.text = widget.piece.notes ?? '';
    }
  }

  @override
  void dispose() {
    _glazesCtrl.dispose();
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
      glazes: _glazesCtrl.text,
      notes: _notesCtrl.text,
    );
  }

  Future<void> _showClayPicker() async {
    final l10n = AppLocalizations.of(context)!;
    final clays = await widget.materialsDao.getAllClays();

    if (!mounted) return;

    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l10n.stageNone),
              onTap: () => Navigator.of(ctx).pop(''),
            ),
            ...clays.map((c) => ListTile(
                  title: Text(c.name),
                  trailing: c.name == widget.piece.clayType
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(c.name),
                )),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(l10n.addNew),
              onTap: () => Navigator.of(ctx).pop('__add_new__'),
            ),
          ],
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
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.addNew),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: l10n.enterClayName),
            textCapitalization: TextCapitalization.words,
            onSubmitted: (value) => Navigator.of(ctx).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.cancel),
            ),
            TextButton(
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
      if (!mounted) return;
      widget.onUpdateField(clayType: name.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentClay = widget.piece.clayType;
    final clayDisplay = (currentClay != null && currentClay.isNotEmpty)
        ? currentClay
        : l10n.stageNone;

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

          // Glazes
          TextField(
            controller: _glazesCtrl,
            decoration: InputDecoration(labelText: l10n.glazesLabel),
            onEditingComplete: () =>
                widget.onUpdateField(glazes: _glazesCtrl.text),
          ),
          const SizedBox(height: AppSizes.md),

          // Notes
          TextField(
            controller: _notesCtrl,
            decoration: InputDecoration(labelText: l10n.notesLabel),
            maxLines: 3,
            onEditingComplete: () =>
                widget.onUpdateField(notes: _notesCtrl.text),
          ),
        ],
      ),
    );
  }
}
