import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../l10n/app_localizations.dart';
import '../../../database/database.dart';
import '../../../models/piece_stage.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/photos_provider.dart';
import '../../../providers/image_service_provider.dart';
import '../widgets/photo_gallery.dart';
import '../widgets/metadata_form.dart';
import '../widgets/photo_timeline.dart' show LastUpdatedInfo;

class PieceDetailScreen extends ConsumerStatefulWidget {
  final String pieceId;

  const PieceDetailScreen({super.key, required this.pieceId});

  @override
  ConsumerState<PieceDetailScreen> createState() => _PieceDetailScreenState();
}

class _PieceDetailScreenState extends ConsumerState<PieceDetailScreen> {
  final _formKey = GlobalKey<MetadataFormState>();
  Piece? _piece;

  @override
  void initState() {
    super.initState();
    _loadPiece();
  }

  Future<void> _loadPiece() async {
    final dao = ref.read(piecesDaoProvider);
    final piece = await dao.getPieceById(widget.pieceId);
    if (mounted) setState(() => _piece = piece);
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
    final dao = ref.read(piecesDaoProvider);
    await dao.updatePiece(PiecesCompanion(
      id: Value(widget.pieceId),
      isArchived: Value(!wasArchived),
      updatedAt: Value(DateTime.now()),
    ));
    if (!wasArchived && mounted) {
      context.go('/');
    } else {
      _loadPiece();
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

    if (mounted) context.go('/');
  }

  Future<void> _updateField({
    String? title,
    PieceStage? stage,
    bool clearStage = false,
    String? clayType,
    String? glazes,
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
      glazes: glazes != null
          ? Value(glazes.isEmpty ? null : glazes)
          : const Value.absent(),
      notes: notes != null
          ? Value(notes.isEmpty ? null : notes)
          : const Value.absent(),
      updatedAt: Value(DateTime.now()),
    ));
    _loadPiece();
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
                _addPhoto(ImageSource.gallery);
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
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'archive') _toggleArchive();
              if (value == 'delete') _deletePiece();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'archive',
                child: Text(_piece!.isArchived
                    ? l10n.unarchivePiece
                    : l10n.archivePiece),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(l10n.deletePiece,
                    style: const TextStyle(color: Colors.red)),
              ),
            ],
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
                    if (photos.isNotEmpty)
                      PhotoGallery(
                        photos: photos,
                        onDelete: _deletePhoto,
                      ),
                    MetadataForm(
                      key: _formKey,
                      piece: _piece!,
                      onUpdateField: _updateField,
                    ),
                    LastUpdatedInfo(piece: _piece!),
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
