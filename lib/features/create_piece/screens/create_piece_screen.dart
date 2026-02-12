import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../l10n/app_localizations.dart';
import '../../../database/database.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/image_service_provider.dart';

class CreatePieceScreen extends ConsumerStatefulWidget {
  const CreatePieceScreen({super.key});

  @override
  ConsumerState<CreatePieceScreen> createState() => _CreatePieceScreenState();
}

class _CreatePieceScreenState extends ConsumerState<CreatePieceScreen> {
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showSourcePicker());
  }

  Future<void> _showSourcePicker() async {
    final l10n = AppLocalizations.of(context)!;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(l10n.camera),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(l10n.photoLibrary),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) {
      if (mounted) context.pop();
      return;
    }

    await _createPiece(source);
  }

  Future<void> _createPiece(ImageSource source) async {
    setState(() => _processing = true);

    try {
      final imageService = ref.read(imageServiceProvider);
      const uuid = Uuid();
      final pieceId = uuid.v4();

      final result = await imageService.pickAndProcessImage(
        source: source,
        pieceId: pieceId,
      );

      if (result == null) {
        if (mounted) context.pop();
        return;
      }

      final now = DateTime.now();
      final piecesDao = ref.read(piecesDaoProvider);
      final photosDao = ref.read(photosDaoProvider);

      await piecesDao.insertPiece(PiecesCompanion(
        id: Value(pieceId),
        coverPhotoId: Value(result.photoId),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));

      await photosDao.insertPhoto(PhotosCompanion(
        id: Value(result.photoId),
        pieceId: Value(pieceId),
        localPath: Value(result.localPath),
        thumbnailPath: Value(result.thumbnailPath),
        dateTaken: Value(result.dateTaken),
        createdAt: Value(now),
        sortOrder: const Value(0),
      ));

      if (mounted) context.go('/piece/$pieceId');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not capture photo: $e')),
        );
        context.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('New Piece'),
      ),
      body: Center(
        child: _processing
            ? const CircularProgressIndicator()
            : const SizedBox.shrink(),
      ),
    );
  }
}
