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
  final TextEditingController _glazesTextCtrl = TextEditingController();
  final TextEditingController _tagsTextCtrl = TextEditingController();
  late final TextEditingController _notesCtrl;
  late final TextEditingController _clayCtrl;
  late final FocusNode _clayFocus;
  List<ClayOption> _allClays = [];
  String _lastSavedClay = '';

  @override
  void initState() {
    super.initState();
    _notesCtrl = TextEditingController(text: widget.piece.notes ?? '');
    _clayCtrl = TextEditingController(text: widget.piece.clayType ?? '');
    _lastSavedClay = widget.piece.clayType ?? '';
    _clayFocus = FocusNode();
    _clayFocus.addListener(_onClayFocusChange);
    _loadClays();
  }

  @override
  void didUpdateWidget(MetadataForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.piece.id != widget.piece.id) {
      _notesCtrl.text = widget.piece.notes ?? '';
      _clayCtrl.text = widget.piece.clayType ?? '';
      _lastSavedClay = widget.piece.clayType ?? '';
      _loadClays();
    }
  }

  @override
  void dispose() {
    _clayFocus.removeListener(_onClayFocusChange);
    _clayFocus.dispose();
    _clayCtrl.dispose();
    _notesCtrl.dispose();
    _glazesTextCtrl.dispose();
    _tagsTextCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadClays() async {
    _allClays = await widget.materialsDao.getAllClays();
    if (mounted) setState(() {});
  }

  void _onClayFocusChange() {
    if (!_clayFocus.hasFocus) {
      _saveClay();
    }
  }

  Future<void> _saveClay() async {
    final text = _clayCtrl.text.trim();
    if (text == _lastSavedClay) return;
    _lastSavedClay = text;
    if (text.isNotEmpty) {
      final clay = await widget.materialsDao.findOrCreateClay(text);
      await widget.syncTrigger.afterClayWrite(clay.id);
      await _loadClays();
    }
    widget.onUpdateField(clayType: text);
    if (_clayCtrl.text != text) {
      _clayCtrl.text = text;
    }
  }

  PieceStage? get _currentStage {
    final s = widget.piece.stage;
    if (s == null) return null;
    return PieceStage.values.where((e) => e.name == s).firstOrNull;
  }

  Future<void> saveAll() async {
    // Save any pending typed-but-not-submitted glaze text
    final pendingGlaze = _glazesTextCtrl.text.trim();
    if (pendingGlaze.isNotEmpty) {
      final glaze = await widget.materialsDao.findOrCreateGlaze(pendingGlaze);
      await widget.syncTrigger.afterGlazeWrite(glaze.id);
      final glazeIds = widget.selectedGlazes.map((g) => g.id).toList();
      if (!glazeIds.contains(glaze.id)) {
        glazeIds.add(glaze.id);
      }
      await widget.onUpdateGlazes(glazeIds);
    }

    // Save any pending typed-but-not-submitted tag text
    final pendingTag = _tagsTextCtrl.text.trim();
    if (pendingTag.isNotEmpty) {
      final tag = await widget.materialsDao.findOrCreateTag(pendingTag);
      await widget.syncTrigger.afterTagWrite(tag.id);
      final tagIds = widget.selectedTags.map((t) => t.id).toList();
      if (!tagIds.contains(tag.id)) {
        tagIds.add(tag.id);
      }
      await widget.onUpdateTags(tagIds);
    }

    final clayText = _clayCtrl.text.trim();
    widget.onUpdateField(clayType: clayText, notes: _notesCtrl.text);
    if (clayText.isNotEmpty) {
      final clay = await widget.materialsDao.findOrCreateClay(clayText);
      await widget.syncTrigger.afterClayWrite(clay.id);
    }
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

          // Clay autocomplete text field
          RawAutocomplete<ClayOption>(
            textEditingController: _clayCtrl,
            focusNode: _clayFocus,
            optionsBuilder: (textEditingValue) {
              final query = textEditingValue.text.toLowerCase().trim();
              if (query.isEmpty) return Iterable<ClayOption>.empty();
              return _allClays.where(
                (c) => c.name.toLowerCase().contains(query),
              );
            },
            displayStringForOption: (option) => option.name,
            onSelected: (clay) => _saveClay(),
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
                  return InputDecorator(
                    decoration: InputDecoration(labelText: l10n.clayTypeLabel),
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        hintText: l10n.enterClayName,
                        counterText: '',
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      autocorrect: false,
                      maxLength: AppSizes.maxClayNameLength,
                      onSubmitted: (_) {
                        _saveClay();
                      },
                    ),
                  );
                },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: 200,
                      maxWidth:
                          MediaQuery.of(context).size.width - AppSizes.md * 2,
                    ),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index);
                        return ListTile(
                          title: Text(option.name),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSizes.md),

          // Glazes chip input
          _ChipInputField<GlazeOption>(
            controller: _glazesTextCtrl,
            selectedItems: widget.selectedGlazes,
            labelBuilder: (g) => g.name,
            allOptionsLoader: widget.materialsDao.getAllGlazes,
            onCreateNew: (name) async {
              final glaze = await widget.materialsDao.findOrCreateGlaze(name);
              await widget.syncTrigger.afterGlazeWrite(glaze.id);
              return glaze;
            },
            onChanged: widget.onUpdateGlazes,
            idGetter: (g) => g.id,
            label: l10n.glazesLabel,
            hintText: l10n.enterGlazeName,
            maxInputLength: AppSizes.maxGlazeNameLength,
          ),
          const SizedBox(height: AppSizes.md),

          // Tags chip input
          _ChipInputField<TagOption>(
            controller: _tagsTextCtrl,
            selectedItems: widget.selectedTags,
            labelBuilder: (t) => t.name,
            leadingBuilder: (t) => t.color != null
                ? Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: TagColorPresets.hexToColor(t.color!),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.divider, width: 1),
                    ),
                  )
                : null,
            allOptionsLoader: widget.materialsDao.getAllTags,
            onCreateNew: (name) async {
              final tag = await widget.materialsDao.findOrCreateTag(name);
              await widget.syncTrigger.afterTagWrite(tag.id);
              return tag;
            },
            onChanged: widget.onUpdateTags,
            idGetter: (t) => t.id,
            label: l10n.tagsLabel,
            hintText: l10n.enterTagName,
            maxInputLength: AppSizes.maxTagNameLength,
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

class _ChipInputField<T extends Object> extends StatefulWidget {
  final List<T> selectedItems;
  final String Function(T) labelBuilder;
  final Widget? Function(T)? leadingBuilder;
  final Future<List<T>> Function() allOptionsLoader;
  final Future<T> Function(String name) onCreateNew;
  final Future<void> Function(List<String> ids) onChanged;
  final String Function(T) idGetter;
  final String label;
  final String hintText;
  final int? maxInputLength;
  final TextEditingController? controller;

  const _ChipInputField({
    super.key,
    this.controller,
    required this.selectedItems,
    required this.labelBuilder,
    this.leadingBuilder,
    required this.allOptionsLoader,
    required this.onCreateNew,
    required this.onChanged,
    required this.idGetter,
    required this.label,
    required this.hintText,
    this.maxInputLength,
  });

  @override
  State<_ChipInputField<T>> createState() => _ChipInputFieldState<T>();
}

class _ChipInputFieldState<T extends Object> extends State<_ChipInputField<T>> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  List<T> _allOptions = [];
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = TextEditingController();
      _ownsController = true;
    }
    _focusNode.addListener(_onFocusChange);
    _loadOptions();
  }

  @override
  void didUpdateWidget(_ChipInputField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadOptions();
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _loadOptions();
    }
  }

  Future<void> _loadOptions() async {
    _allOptions = await widget.allOptionsLoader();
    if (mounted) setState(() {});
  }

  Future<void> _removeItem(T item) async {
    final ids = widget.selectedItems
        .where((i) => widget.idGetter(i) != widget.idGetter(item))
        .map((i) => widget.idGetter(i))
        .toList();
    await widget.onChanged(ids);
  }

  Future<void> _addItem(T item) async {
    final selectedIds = widget.selectedItems.map(widget.idGetter).toSet();
    if (selectedIds.contains(widget.idGetter(item))) {
      _controller.clear();
      return;
    }
    final ids = widget.selectedItems.map((i) => widget.idGetter(i)).toList()
      ..add(widget.idGetter(item));
    await widget.onChanged(ids);
    _controller.clear();
    _focusNode.requestFocus();
  }

  Future<void> submitText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    final item = await widget.onCreateNew(text);
    await _loadOptions();
    await _addItem(item);
  }

  Iterable<T> _filterOptions(TextEditingValue value) {
    final query = value.text.toLowerCase().trim();
    if (query.isEmpty) return <T>[];
    final selectedIds = widget.selectedItems.map(widget.idGetter).toSet();
    return _allOptions.where(
      (o) =>
          !selectedIds.contains(widget.idGetter(o)) &&
          widget.labelBuilder(o).toLowerCase().contains(query),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<T>(
      textEditingController: _controller,
      focusNode: _focusNode,
      optionsBuilder: _filterOptions,
      displayStringForOption: widget.labelBuilder,
      onSelected: _addItem,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return InputDecorator(
          decoration: InputDecoration(labelText: widget.label),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                focusNode: focusNode,
                maxLength: widget.maxInputLength,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  hintText: widget.hintText,
                  counterText: '',
                ),
                textCapitalization: TextCapitalization.sentences,
                autocorrect: false,
                onEditingComplete: () {},
                onSubmitted: (_) {
                  submitText();
                  _focusNode.requestFocus();
                },
              ),
              if (widget.selectedItems.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: widget.selectedItems.map((item) {
                      final leading = widget.leadingBuilder?.call(item);
                      return ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth:
                              MediaQuery.of(context).size.width -
                              AppSizes.md * 4,
                        ),
                        child: InputChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ?leading,
                              Flexible(
                                child: Text(
                                  widget.labelBuilder(item),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          onDeleted: () => _removeItem(item),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 200,
                maxWidth: MediaQuery.of(context).size.width - AppSizes.md * 2,
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  final leading = widget.leadingBuilder?.call(option);
                  return ListTile(
                    leading: leading,
                    title: Text(widget.labelBuilder(option)),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
