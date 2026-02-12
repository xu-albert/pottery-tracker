import 'package:flutter/material.dart';
import '../../../database/database.dart';
import '../../../models/piece_stage.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/constants/app_sizes.dart';

class MetadataForm extends StatefulWidget {
  final Piece piece;
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
    required this.onUpdateField,
  });

  @override
  State<MetadataForm> createState() => MetadataFormState();
}

class MetadataFormState extends State<MetadataForm> {
  late final TextEditingController _clayCtrl;
  late final TextEditingController _glazesCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _clayCtrl = TextEditingController(text: widget.piece.clayType ?? '');
    _glazesCtrl = TextEditingController(text: widget.piece.glazes ?? '');
    _notesCtrl = TextEditingController(text: widget.piece.notes ?? '');
  }

  @override
  void didUpdateWidget(MetadataForm old) {
    super.didUpdateWidget(old);
    if (old.piece.id != widget.piece.id) {
      _clayCtrl.text = widget.piece.clayType ?? '';
      _glazesCtrl.text = widget.piece.glazes ?? '';
      _notesCtrl.text = widget.piece.notes ?? '';
    }
  }

  @override
  void dispose() {
    _clayCtrl.dispose();
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
      clayType: _clayCtrl.text,
      glazes: _glazesCtrl.text,
      notes: _notesCtrl.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

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

          // Clay type
          TextField(
            controller: _clayCtrl,
            decoration: InputDecoration(labelText: l10n.clayTypeLabel),
            onEditingComplete: () =>
                widget.onUpdateField(clayType: _clayCtrl.text),
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
