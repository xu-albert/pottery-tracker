import 'package:drift/drift.dart' hide Column;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../l10n/app_localizations.dart';
import '../../../database/database.dart';
import '../../../models/piece_stage.dart';
import '../../../providers/analytics_provider.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/materials_provider.dart';
import '../../../providers/photos_provider.dart';
import '../../../providers/image_service_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../core/constants/app_sizes.dart';
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
      final isUntitled = RegExp(r'^Untitled Piece \d+$').hasMatch(title);
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

      final result = await imageService.pickAndProcessImage(
        source: source,
        pieceId: widget.pieceId,
      );
      if (result == null) return;

      final sortOrder = await photosDao.getNextSortOrder(widget.pieceId);
      await photosDao.insertPhoto(
        PhotosCompanion(
          id: Value(result.photoId),
          pieceId: Value(widget.pieceId),
          localPath: Value(result.localPath),
          thumbnailPath: Value(result.thumbnailPath),
          dateTaken: Value(result.dateTaken),
          createdAt: Value(DateTime.now()),
          sortOrder: Value(sortOrder),
        ),
      );

      // Update piece timestamp and set new photo as cover
      final piecesDao = ref.read(piecesDaoProvider);
      await piecesDao.updatePiece(
        PiecesCompanion(
          id: Value(widget.pieceId),
          coverPhotoId: Value(result.photoId),
          updatedAt: Value(DateTime.now()),
        ),
      );
      HapticFeedback.lightImpact();
      ref
          .read(analyticsProvider)
          .logEvent(name: 'photo_added', parameters: {'source': source.name});
      final trigger = ref.read(syncTriggerProvider);
      await trigger.afterPhotoWrite(result.photoId, includeFile: true);
      await trigger.afterPieceWrite(widget.pieceId);
      _loadPiece();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not add photo: $e')));
      }
    }
  }

  Future<void> _deletePhoto(Photo photo) async {
    final photosDao = ref.read(photosDaoProvider);
    final imageService = ref.read(imageServiceProvider);

    await photosDao.deletePhoto(photo.id);
    await imageService.deletePhotoFiles(widget.pieceId, photo.id);
    HapticFeedback.lightImpact();
    await ref.read(syncTriggerProvider).afterPhotoDeletion(photo.id);

    // If deleted photo was cover, set new cover
    if (_piece?.coverPhotoId == photo.id) {
      final remaining = await photosDao.getPhotosForPiece(widget.pieceId);
      final piecesDao = ref.read(piecesDaoProvider);
      await piecesDao.updatePiece(
        PiecesCompanion(
          id: Value(widget.pieceId),
          coverPhotoId: Value(remaining.isNotEmpty ? remaining.first.id : null),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await ref.read(syncTriggerProvider).afterPieceWrite(widget.pieceId);
      _loadPiece();
    }
  }

  Future<void> _toggleArchive() async {
    final wasArchived = _piece!.isArchived;
    final l10n = AppLocalizations.of(context)!;
    final dao = ref.read(piecesDaoProvider);
    await dao.updatePiece(
      PiecesCompanion(
        id: Value(widget.pieceId),
        isArchived: Value(!wasArchived),
        updatedAt: Value(DateTime.now()),
      ),
    );
    HapticFeedback.lightImpact();
    ref
        .read(analyticsProvider)
        .logEvent(name: wasArchived ? 'piece_unarchived' : 'piece_archived');
    await ref.read(syncTriggerProvider).afterPieceWrite(widget.pieceId);
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              wasArchived
                  ? l10n.pieceUnarchivedWithTitle(
                      _piece!.title ?? 'Untitled Piece',
                    )
                  : l10n.pieceArchivedWithTitle(
                      _piece!.title ?? 'Untitled Piece',
                    ),
            ),
          ),
        );
      context.go('/');
    }
  }

  Future<void> _deletePiece() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deletePieceConfirmTitle),
        content: Text(l10n.deletePieceConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final piecesDao = ref.read(piecesDaoProvider);
    final photosDao = ref.read(photosDaoProvider);
    final imageService = ref.read(imageServiceProvider);

    // Capture photo IDs before deletion for sync
    final photos = await photosDao.getPhotosForPiece(widget.pieceId);
    final photoIds = photos.map((p) => p.id).toList();

    await photosDao.deletePhotosForPiece(widget.pieceId);
    await piecesDao.deletePiece(widget.pieceId);
    await imageService.deletePhotos(widget.pieceId);
    HapticFeedback.mediumImpact();
    ref.read(analyticsProvider).logEvent(name: 'piece_deleted');
    await ref
        .read(syncTriggerProvider)
        .afterPieceDeletion(widget.pieceId, photoIds);

    if (mounted) context.go('/');
  }

  Future<void> _updateField({
    String? title,
    PieceStage? stage,
    bool clearStage = false,
    String? clayType,
    String? notes,
  }) async {
    final dao = ref.read(piecesDaoProvider);
    await dao.updatePiece(
      PiecesCompanion(
        id: Value(widget.pieceId),
        title: title != null
            ? Value(title.isEmpty ? null : title)
            : const Value.absent(),
        stage: clearStage
            ? const Value(null)
            : stage != null
            ? Value(stage.name)
            : const Value.absent(),
        clayType: clayType != null
            ? Value(clayType.isEmpty ? null : clayType)
            : const Value.absent(),
        notes: notes != null
            ? Value(notes.isEmpty ? null : notes)
            : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await ref.read(syncTriggerProvider).afterPieceWrite(widget.pieceId);
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

    final dao = ref.read(piecesDaoProvider);
    await dao.updatePiece(
      PiecesCompanion(
        id: Value(widget.pieceId),
        displayDate: Value(date),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await ref.read(syncTriggerProvider).afterPieceWrite(widget.pieceId);
    _loadPiece();
  }

  DateTime _resolveDisplayDate() {
    if (_piece!.displayDate != null) return _piece!.displayDate!;
    final photos = ref.read(photosForPieceProvider(widget.pieceId)).valueOrNull;
    if (photos != null && photos.isNotEmpty) {
      return photos
          .map((p) => p.dateTaken)
          .reduce((a, b) => a.isAfter(b) ? a : b);
    }
    return _piece!.createdAt;
  }

  Future<void> _editPhotoDate(Photo photo) async {
    final date = await _showCupertinoDatePicker(photo.dateTaken);
    if (date == null || !mounted) return;

    final photosDao = ref.read(photosDaoProvider);
    await photosDao.updatePhoto(
      PhotosCompanion(id: Value(photo.id), dateTaken: Value(date)),
    );
    await ref.read(syncTriggerProvider).afterPhotoWrite(photo.id);
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
    try {
      final imageService = ref.read(imageServiceProvider);
      final picked = await imageService.pickMultipleImages();
      if (picked == null || !mounted) return;

      // Show progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _BatchProgressDialog(total: picked.length),
      );
      dialogOpen = true;

      final photosDao = ref.read(photosDaoProvider);
      final piecesDao = ref.read(piecesDaoProvider);
      var sortOrder = await photosDao.getNextSortOrder(widget.pieceId);
      String? lastPhotoId;
      var failures = 0;

      for (var i = 0; i < picked.length; i++) {
        // Update progress
        if (mounted) {
          _BatchProgressDialog._updateProgress(i + 1);
        }

        try {
          final bytes = await picked[i].readAsBytes();
          final result = await imageService.processImage(
            bytes: bytes,
            pieceId: widget.pieceId,
          );

          await photosDao.insertPhoto(
            PhotosCompanion(
              id: Value(result.photoId),
              pieceId: Value(widget.pieceId),
              localPath: Value(result.localPath),
              thumbnailPath: Value(result.thumbnailPath),
              dateTaken: Value(result.dateTaken),
              createdAt: Value(DateTime.now()),
              sortOrder: Value(sortOrder),
            ),
          );

          final trigger = ref.read(syncTriggerProvider);
          await trigger.afterPhotoWrite(result.photoId, includeFile: true);

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
        await piecesDao.updatePiece(
          PiecesCompanion(
            id: Value(widget.pieceId),
            coverPhotoId: Value(lastPhotoId),
            updatedAt: Value(DateTime.now()),
          ),
        );
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
      await ref.read(syncTriggerProvider).afterPieceWrite(widget.pieceId);
      _loadPiece();

      if (failures > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.batchPhotoFailures(failures))),
        );
      }
    } catch (e) {
      // Dismiss progress dialog only if it was shown
      if (dialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not add photos: $e')));
      }
    }
  }

  Future<void> _reorderPhotos(List<Photo> photos) async {
    final result = await Navigator.push<PhotoReorderResult>(
      context,
      MaterialPageRoute(builder: (_) => PhotoReorderScreen(photos: photos)),
    );
    if (result == null) return;

    final photosDao = ref.read(photosDaoProvider);
    final imageService = ref.read(imageServiceProvider);
    final trigger = ref.read(syncTriggerProvider);

    // Process deletions
    for (final deletedId in result.deletedIds) {
      await photosDao.deletePhoto(deletedId);
      await imageService.deletePhotoFiles(widget.pieceId, deletedId);
      await trigger.afterPhotoDeletion(deletedId);
    }

    // Update cover photo if deleted
    if (result.deletedIds.contains(_piece?.coverPhotoId)) {
      final remaining = result.reordered;
      final piecesDao = ref.read(piecesDaoProvider);
      await piecesDao.updatePiece(
        PiecesCompanion(
          id: Value(widget.pieceId),
          coverPhotoId: Value(remaining.isNotEmpty ? remaining.first.id : null),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await trigger.afterPieceWrite(widget.pieceId);
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

      final updates = <({String id, int sortOrder})>[];
      for (var i = 0; i < result.reordered.length; i++) {
        updates.add((
          id: result.reordered[i].id,
          sortOrder: result.reordered.length - 1 - i,
        ));
      }

      await photosDao.updateSortOrders(updates);
      for (final update in updates) {
        await trigger.afterPhotoWrite(update.id);
      }
    }
  }

  void _showAddPhotoSheet() {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(l10n.camera),
              onTap: () {
                Navigator.pop(ctx);
                _addPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(l10n.photoLibrary),
              onTap: () {
                Navigator.pop(ctx);
                _addMultiplePhotos();
              },
            ),
          ],
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

class _BatchProgressDialog extends StatefulWidget {
  final int total;

  const _BatchProgressDialog({required this.total});

  static void Function(int)? _onProgress;

  static void _updateProgress(int current) {
    _onProgress?.call(current);
  }

  @override
  State<_BatchProgressDialog> createState() => _BatchProgressDialogState();
}

class _BatchProgressDialogState extends State<_BatchProgressDialog> {
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _BatchProgressDialog._onProgress = (current) {
      if (mounted) setState(() => _current = current);
    };
  }

  @override
  void dispose() {
    _BatchProgressDialog._onProgress = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(l10n.processingPhotos(_current, widget.total)),
        ],
      ),
    );
  }
}
