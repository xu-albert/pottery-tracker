import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../l10n/app_localizations.dart';
import '../../../database/database.dart';
import '../../../models/piece_stage.dart';
import '../../../providers/analytics_provider.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/materials_provider.dart';
import '../../../providers/photos_provider.dart';
import '../../../providers/image_service_provider.dart';
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
  String? _titleHint;
  Piece? _piece;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _loadPiece();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
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
      await photosDao.insertPhoto(PhotosCompanion(
        id: Value(result.photoId),
        pieceId: Value(widget.pieceId),
        localPath: Value(result.localPath),
        thumbnailPath: Value(result.thumbnailPath),
        dateTaken: Value(result.dateTaken),
        createdAt: Value(DateTime.now()),
        sortOrder: Value(sortOrder),
      ));

      // Update piece timestamp and set new photo as cover
      final piecesDao = ref.read(piecesDaoProvider);
      await piecesDao.updatePiece(PiecesCompanion(
        id: Value(widget.pieceId),
        coverPhotoId: Value(result.photoId),
        updatedAt: Value(DateTime.now()),
      ));
      HapticFeedback.lightImpact();
      ref.read(analyticsProvider).logEvent(
        name: 'photo_added',
        parameters: {'source': source.name},
      );
      _loadPiece();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add photo: $e')),
        );
      }
    }
  }

  Future<void> _deletePhoto(Photo photo) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deletePhotoConfirmTitle),
        content: Text(l10n.deletePhotoConfirmMessage),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.delete)),
        ],
      ),
    );

    if (confirmed != true) return;

    final photosDao = ref.read(photosDaoProvider);
    final imageService = ref.read(imageServiceProvider);

    await photosDao.deletePhoto(photo.id);
    await imageService.deletePhotoFiles(widget.pieceId, photo.id);
    HapticFeedback.lightImpact();

    // If deleted photo was cover, set new cover
    if (_piece?.coverPhotoId == photo.id) {
      final remaining = await photosDao.getPhotosForPiece(widget.pieceId);
      final piecesDao = ref.read(piecesDaoProvider);
      await piecesDao.updatePiece(PiecesCompanion(
        id: Value(widget.pieceId),
        coverPhotoId: Value(remaining.isNotEmpty ? remaining.first.id : null),
        updatedAt: Value(DateTime.now()),
      ));
      _loadPiece();
    }
  }

  Future<void> _toggleArchive() async {
    final wasArchived = _piece!.isArchived;
    final l10n = AppLocalizations.of(context)!;
    final dao = ref.read(piecesDaoProvider);
    await dao.updatePiece(PiecesCompanion(
      id: Value(widget.pieceId),
      isArchived: Value(!wasArchived),
      updatedAt: Value(DateTime.now()),
    ));
    HapticFeedback.lightImpact();
    ref.read(analyticsProvider).logEvent(
      name: wasArchived ? 'piece_unarchived' : 'piece_archived',
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              wasArchived
                  ? l10n.pieceUnarchivedWithTitle(_piece!.title ?? 'Untitled Piece')
                  : l10n.pieceArchivedWithTitle(_piece!.title ?? 'Untitled Piece'),
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
              child: Text(l10n.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.delete,
                  style: const TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed != true) return;

    final piecesDao = ref.read(piecesDaoProvider);
    final photosDao = ref.read(photosDaoProvider);
    final imageService = ref.read(imageServiceProvider);

    await photosDao.deletePhotosForPiece(widget.pieceId);
    await piecesDao.deletePiece(widget.pieceId);
    await imageService.deletePhotos(widget.pieceId);
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
    final dao = ref.read(piecesDaoProvider);
    await dao.updatePiece(PiecesCompanion(
      id: Value(widget.pieceId),
      title: title != null ? Value(title.isEmpty ? null : title) : const Value.absent(),
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
    ));
    _loadPiece();
  }

  Future<void> _updateGlazes(List<String> glazeOptionIds) async {
    final materialsDao = ref.read(materialsDaoProvider);
    await materialsDao.setGlazesForPiece(widget.pieceId, glazeOptionIds);
    _loadPiece();
  }

  Future<void> _updateTags(List<String> tagOptionIds) async {
    final materialsDao = ref.read(materialsDaoProvider);
    await materialsDao.setTagsForPiece(widget.pieceId, tagOptionIds);
    _loadPiece();
  }

  Future<void> _pickUpdatedDate() async {
    final current = _piece!.updatedAt;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (!mounted) return;

    final newDate = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? current.hour,
      time?.minute ?? current.minute,
    );

    final dao = ref.read(piecesDaoProvider);
    await dao.updatePiece(PiecesCompanion(
      id: Value(widget.pieceId),
      updatedAt: Value(newDate),
    ));
    _loadPiece();
  }

  Future<void> _addMultiplePhotos() async {
    final l10n = AppLocalizations.of(context)!;
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

          await photosDao.insertPhoto(PhotosCompanion(
            id: Value(result.photoId),
            pieceId: Value(widget.pieceId),
            localPath: Value(result.localPath),
            thumbnailPath: Value(result.thumbnailPath),
            dateTaken: Value(result.dateTaken),
            createdAt: Value(DateTime.now()),
            sortOrder: Value(sortOrder),
          ));

          lastPhotoId = result.photoId;
          sortOrder++;
        } catch (_) {
          failures++;
        }
      }

      // Dismiss progress dialog
      if (mounted) Navigator.of(context).pop();

      // Set last photo as cover
      if (lastPhotoId != null) {
        await piecesDao.updatePiece(PiecesCompanion(
          id: Value(widget.pieceId),
          coverPhotoId: Value(lastPhotoId),
          updatedAt: Value(DateTime.now()),
        ));
      }

      HapticFeedback.lightImpact();
      ref.read(analyticsProvider).logEvent(
        name: 'photo_added',
        parameters: {'source': 'gallery', 'count': picked.length - failures},
      );
      _loadPiece();

      if (failures > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.batchPhotoFailures(failures))),
        );
      }
    } catch (e) {
      // Dismiss progress dialog if open
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add photos: $e')),
        );
      }
    }
  }

  Future<void> _reorderPhotos(List<Photo> photos) async {
    final result = await Navigator.push<List<Photo>>(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoReorderScreen(photos: photos),
      ),
    );
    if (result == null) return;
    ref.read(analyticsProvider).logEvent(
      name: 'photo_reorder_saved',
      parameters: {'photo_count': result.length},
    );

    // Assign new sort orders: first in list = highest sortOrder (newest first display)
    final updates = <({String id, int sortOrder})>[];
    for (var i = 0; i < result.length; i++) {
      updates.add((id: result[i].id, sortOrder: result.length - 1 - i));
    }

    final photosDao = ref.read(photosDaoProvider);
    await photosDao.updateSortOrders(updates);
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.add_a_photo),
            tooltip: l10n.addPhoto,
            onPressed: _showAddPhotoSheet,
          ),
          IconButton(
            icon: Icon(_piece!.isArchived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined),
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
                        style: Theme.of(context).textTheme.titleLarge,
                        autocorrect: false,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: _titleHint ?? l10n.untitledPiece,
                          border: InputBorder.none,
                        ),
                        onEditingComplete: () {
                          if (_titleCtrl.text.isNotEmpty) {
                            _updateField(title: _titleCtrl.text);
                          }
                        },
                      ),
                    ),
                    if (photos.isNotEmpty)
                      PhotoGallery(
                        photos: photos,
                        onDelete: _deletePhoto,
                      ),
                    if (photos.length >= 2)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: TextButton.icon(
                            onPressed: () => _reorderPhotos(photos),
                            icon: const Icon(Icons.swap_vert, size: 18),
                            label: Text(l10n.reorderPhotos),
                          ),
                        ),
                      ),
                    MetadataForm(
                      key: _formKey,
                      piece: _piece!,
                      materialsDao: ref.read(materialsDaoProvider),
                      selectedGlazes: selectedGlazes,
                      selectedTags: selectedTags,
                      onUpdateField: _updateField,
                      onUpdateGlazes: _updateGlazes,
                      onUpdateTags: _updateTags,
                    ),
                    LastUpdatedInfo(piece: _piece!, onTap: _pickUpdatedDate),
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
                    onPressed: () {
                      if (_titleCtrl.text.isNotEmpty) {
                        _updateField(title: _titleCtrl.text);
                      }
                      _formKey.currentState?.saveAll();
                      context.go('/');
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
