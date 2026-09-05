import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../l10n/app_localizations.dart';
import '../../../database/database.dart';
import '../../../models/display_date.dart';
import '../../../models/piece_stage.dart';
import '../../../models/untitled_title.dart';
import '../../../providers/analytics_provider.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/materials_provider.dart';
import '../../../providers/photos_provider.dart';
import '../../../providers/image_service_provider.dart';
import '../../../providers/piece_writer_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../widgets/app_snackbar.dart';
import '../widgets/delete_piece_dialog.dart';
import '../widgets/photo_gallery.dart';
import '../widgets/metadata_form.dart';
import '../widgets/photo_timeline.dart' show LastUpdatedInfo;
import '../widgets/photo_reorder.dart';

class PieceDetailScreen extends ConsumerStatefulWidget {
  final String pieceId;

  const PieceDetailScreen({super.key, required this.pieceId});

  @override
  ConsumerState<PieceDetailScreen> createState() => _PieceDetailScreenState();
}

class _PieceDetailScreenState extends ConsumerState<PieceDetailScreen> {
  final _formKey = GlobalKey<MetadataFormState>();
  late final TextEditingController _titleCtrl;
  late final FocusNode _titleFocus;
  String? _titleHint;
  Piece? _piece;
  bool _showDateHint = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _titleFocus = FocusNode();
    _titleFocus.addListener(_onTitleFocusChange);
    _loadPiece();
    _checkDateHint();
  }

  @override
  void dispose() {
    _titleFocus.removeListener(_onTitleFocusChange);
    _titleFocus.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkDateHint() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool('date_hint_dismissed') ?? false;
    if (!dismissed && mounted) {
      setState(() => _showDateHint = true);
    }
  }

  Future<void> _dismissDateHint() async {
    setState(() => _showDateHint = false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('date_hint_dismissed', true);
  }

  void _onTitleFocusChange() {
    if (!_titleFocus.hasFocus && _titleCtrl.text.isNotEmpty) {
      _updateField(title: _titleCtrl.text);
    }
  }

  Future<void> _loadPiece() async {
    final dao = ref.read(piecesDaoProvider);
    final piece = await dao.getPieceById(widget.pieceId);
    if (mounted) {
      final title = piece?.title ?? '';
      final isUntitled = isUntitledTitle(title);
      setState(() {
        _piece = piece;
        _titleHint = isUntitled ? title : null;
      });
      _titleCtrl.text = isUntitled ? '' : title;
    }
  }

  Future<void> _addPhoto(ImageSource source) async {
    try {
      final imageService = ref.read(imageServiceProvider);
      final photosDao = ref.read(photosDaoProvider);
      final writer = ref.read(pieceWriterProvider);

      final result = await imageService.pickAndProcessImage(
        source: source,
        pieceId: widget.pieceId,
      );
      if (result == null) return;

      final sortOrder = await photosDao.getNextSortOrder(widget.pieceId);
      await writer.addPhoto(
        pieceId: widget.pieceId,
        photo: result,
        sortOrder: sortOrder,
      );
      await writer.setCoverPhoto(widget.pieceId, result.photoId);
      HapticFeedback.lightImpact();
      ref
          .read(analyticsProvider)
          .logEvent(name: 'photo_added', parameters: {'source': source.name});
      _loadPiece();
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(context, message: 'Could not add photo: $e');
      }
    }
  }

  Future<void> _deletePhoto(Photo photo) async {
    final wasCover = _piece?.coverPhotoId == photo.id;
    await ref
        .read(pieceWriterProvider)
        .deletePhoto(
          pieceId: widget.pieceId,
          photoId: photo.id,
          coverPhotoId: _piece?.coverPhotoId,
        );
    HapticFeedback.lightImpact();
    if (wasCover) _loadPiece();
  }

  Future<void> _toggleArchive() async {
    final wasArchived = _piece!.isArchived;
    final l10n = AppLocalizations.of(context)!;
    await ref
        .read(pieceWriterProvider)
        .setArchived(widget.pieceId, !wasArchived);
    HapticFeedback.lightImpact();
    ref
        .read(analyticsProvider)
        .logEvent(name: wasArchived ? 'piece_unarchived' : 'piece_archived');
    if (mounted) {
      AppSnackbar.show(
        context,
        message: wasArchived
            ? l10n.pieceUnarchivedWithTitle(_piece!.title ?? 'Untitled Piece')
            : l10n.pieceArchivedWithTitle(_piece!.title ?? 'Untitled Piece'),
      );
      context.go('/');
    }
  }

  Future<void> _deletePiece() async {
    if (!await confirmDeletePiece(context)) return;

    await ref.read(pieceWriterProvider).deletePiece(widget.pieceId);
    HapticFeedback.mediumImpact();
    ref.read(analyticsProvider).logEvent(name: 'piece_deleted');

    if (mounted) context.go('/');
  }

  Future<void> _updateField({
    String? title,
    PieceStage? stage,
    bool clearStage = false,
    String? clayType,
    String? notes,
  }) async {
    await ref
        .read(pieceWriterProvider)
        .updateFields(
          widget.pieceId,
          title: title,
          stage: stage,
          clearStage: clearStage,
          clayType: clayType,
          notes: notes,
        );
    _loadPiece();
  }

  Future<void> _updateGlazes(List<String> glazeOptionIds) async {
    final materialsDao = ref.read(materialsDaoProvider);
    await materialsDao.setGlazesForPiece(widget.pieceId, glazeOptionIds);
    final trigger = ref.read(syncTriggerProvider);
    await trigger.afterPieceGlazesWrite(widget.pieceId);
    await trigger.afterPieceWrite(widget.pieceId);
    _loadPiece();
  }

  Future<void> _updateTags(List<String> tagOptionIds) async {
    final materialsDao = ref.read(materialsDaoProvider);
    await materialsDao.setTagsForPiece(widget.pieceId, tagOptionIds);
    final trigger = ref.read(syncTriggerProvider);
    await trigger.afterPieceTagsWrite(widget.pieceId);
    await trigger.afterPieceWrite(widget.pieceId);
    _loadPiece();
  }

  Future<void> _pickUpdatedDate() async {
    final current = _resolveDisplayDate();
    final date = await _showCupertinoDatePicker(current);
    if (date == null || !mounted) return;

    await ref.read(pieceWriterProvider).setDisplayDate(widget.pieceId, date);
    _loadPiece();
  }

  DateTime _resolveDisplayDate() {
    final photos = ref.read(photosForPieceProvider(widget.pieceId)).valueOrNull;
    return resolveDisplayDate(_piece!, photos ?? const []);
  }

  Future<void> _editPhotoDate(Photo photo) async {
    final date = await _showCupertinoDatePicker(photo.dateTaken);
    if (date == null || !mounted) return;

    await ref.read(pieceWriterProvider).setPhotoDate(photo.id, date);
  }

  Future<DateTime?> _showCupertinoDatePicker(DateTime initial) async {
    DateTime selected = initial;
    return showModalBottomSheet<DateTime>(
      context: context,
      builder: (ctx) => SizedBox(
        height: 300,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.pop(ctx),
                ),
                CupertinoButton(
                  child: const Text('Done'),
                  onPressed: () => Navigator.pop(ctx, selected),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: initial,
                maximumDate: DateTime.now(),
                minimumDate: DateTime(2000),
                onDateTimeChanged: (date) => selected = date,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addMultiplePhotos() async {
    final l10n = AppLocalizations.of(context)!;
    var dialogOpen = false;
    final progress = ValueNotifier<int>(0);
    try {
      final imageService = ref.read(imageServiceProvider);
      final picked = await imageService.pickMultipleImages();
      if (picked == null || !mounted) return;

      // Show progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _BatchProgressDialog(total: picked.length, progress: progress),
      );
      dialogOpen = true;

      final photosDao = ref.read(photosDaoProvider);
      final writer = ref.read(pieceWriterProvider);
      var sortOrder = await photosDao.getNextSortOrder(widget.pieceId);
      String? lastPhotoId;
      var failures = 0;

      for (var i = 0; i < picked.length; i++) {
        progress.value = i + 1;

        try {
          final bytes = await picked[i].readAsBytes();
          final result = await imageService.processImage(
            bytes: bytes,
            pieceId: widget.pieceId,
          );

          await writer.addPhoto(
            pieceId: widget.pieceId,
            photo: result,
            sortOrder: sortOrder,
          );

          lastPhotoId = result.photoId;
          sortOrder++;
        } catch (_) {
          failures++;
        }
      }

      // Dismiss progress dialog
      if (mounted) Navigator.of(context).pop();
      dialogOpen = false;

      // Set last photo as cover
      if (lastPhotoId != null) {
        await writer.setCoverPhoto(widget.pieceId, lastPhotoId);
      }

      HapticFeedback.lightImpact();
      ref
          .read(analyticsProvider)
          .logEvent(
            name: 'photo_added',
            parameters: {
              'source': 'gallery',
              'count': picked.length - failures,
            },
          );
      _loadPiece();

      if (failures > 0 && mounted) {
        AppSnackbar.show(context, message: l10n.batchPhotoFailures(failures));
      }
    } catch (e) {
      // Dismiss progress dialog only if it was shown
      if (dialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        AppSnackbar.show(context, message: 'Could not add photos: $e');
      }
    } finally {
      progress.dispose();
    }
  }

  Future<void> _reorderPhotos(List<Photo> photos) async {
    final result = await Navigator.push<PhotoReorderResult>(
      context,
      MaterialPageRoute(builder: (_) => PhotoReorderScreen(photos: photos)),
    );
    if (result == null) return;

    final writer = ref.read(pieceWriterProvider);

    // Process deletions
    for (final deletedId in result.deletedIds) {
      await writer.deletePhoto(pieceId: widget.pieceId, photoId: deletedId);
    }

    // Update cover photo if deleted
    if (result.deletedIds.contains(_piece?.coverPhotoId)) {
      final remaining = result.reordered;
      await writer.setCoverPhoto(
        widget.pieceId,
        remaining.isNotEmpty ? remaining.first.id : null,
      );
      _loadPiece();
    }

    // Assign new sort orders
    if (result.reordered.isNotEmpty) {
      ref
          .read(analyticsProvider)
          .logEvent(
            name: 'photo_reorder_saved',
            parameters: {'photo_count': result.reordered.length},
          );
      await writer.reorderPhotos(result.reordered.map((p) => p.id).toList());
    }
  }

  void _showAddPhotoSheet() {
    final l10n = AppLocalizations.of(context)!;
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _addPhoto(ImageSource.camera);
            },
            child: Text(l10n.camera),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _addMultiplePhotos();
            },
            child: Text(l10n.photoLibrary),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.cancel),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final photosAsync = ref.watch(photosForPieceProvider(widget.pieceId));
    final glazesAsync = ref.watch(glazesForPieceProvider(widget.pieceId));
    final selectedGlazes = glazesAsync.valueOrNull ?? [];
    final tagsAsync = ref.watch(tagsForPieceProvider(widget.pieceId));
    final selectedTags = tagsAsync.valueOrNull ?? [];

    if (_piece == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: Icon(
              _piece!.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
            ),
            tooltip: _piece!.isArchived
                ? l10n.unarchivePiece
                : l10n.archivePiece,
            onPressed: _toggleArchive,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.deletePiece,
            color: Colors.red,
            onPressed: _deletePiece,
          ),
        ],
      ),
      body: photosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (photos) => Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: TextField(
                        controller: _titleCtrl,
                        focusNode: _titleFocus,
                        style: Theme.of(context).textTheme.titleLarge,
                        autocorrect: false,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: AppSizes.maxTitleLength,
                        decoration: InputDecoration(
                          hintText: _titleHint ?? l10n.untitledPiece,
                          border: InputBorder.none,
                          counterText: '',
                        ),
                        onEditingComplete: () {
                          if (_titleCtrl.text.isNotEmpty) {
                            _updateField(title: _titleCtrl.text);
                          }
                        },
                      ),
                    ),
                    if (_showDateHint && photos.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(
                              AppSizes.radiusSm,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 18,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Tap the date on a photo to change the photo\'s date',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: Colors.grey.shade700),
                                ),
                              ),
                              GestureDetector(
                                onTap: _dismissDateHint,
                                child: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    PhotoGallery(
                      photos: photos,
                      onDelete: _deletePhoto,
                      onEditDate: _editPhotoDate,
                      onAddPhoto: _showAddPhotoSheet,
                    ),
                    if (photos.length >= 2)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            right: 16,
                            top: AppSizes.sm,
                          ),
                          child: GestureDetector(
                            onTap: () => _reorderPhotos(photos),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.swap_vert,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.reorderPhotos,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    MetadataForm(
                      key: _formKey,
                      piece: _piece!,
                      materialsDao: ref.read(materialsDaoProvider),
                      syncTrigger: ref.read(syncTriggerProvider),
                      selectedGlazes: selectedGlazes,
                      selectedTags: selectedTags,
                      onUpdateField: _updateField,
                      onUpdateGlazes: _updateGlazes,
                      onUpdateTags: _updateTags,
                    ),
                    LastUpdatedInfo(
                      displayDate: _resolveDisplayDate(),
                      onTap: _pickUpdatedDate,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (_titleCtrl.text.isNotEmpty) {
                        _updateField(title: _titleCtrl.text);
                      }
                      await _formKey.currentState?.saveAll();
                      if (context.mounted) context.go('/');
                    },
                    child: const Text('Done'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchProgressDialog extends StatelessWidget {
  final int total;
  final ValueListenable<int> progress;

  const _BatchProgressDialog({required this.total, required this.progress});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return CupertinoAlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CupertinoActivityIndicator(),
          const SizedBox(height: 16),
          ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (_, current, _) =>
                Text(l10n.processingPhotos(current, total)),
          ),
        ],
      ),
    );
  }
}
