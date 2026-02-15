import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../l10n/app_localizations.dart';
import '../../../database/database.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/analytics_provider.dart';
import '../../../providers/image_service_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../services/image_service.dart';

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
    // Use a string to distinguish camera vs gallery (multi-select)
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(l10n.camera),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(l10n.photoLibrary),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
          ],
        ),
      ),
    );

    if (choice == null) {
      if (mounted) context.pop();
      return;
    }

    if (choice == 'camera') {
      await _createPieceFromCamera();
    } else {
      await _createPieceFromGallery();
    }
  }

  Future<String> _nextUntitledName(dynamic piecesDao) async {
    final titles = await piecesDao.getUntitledPieceTitles();
    final usedNumbers = <int>{};
    final pattern = RegExp(r'^Untitled Piece (\d+)$');
    for (final t in titles) {
      final match = pattern.firstMatch(t);
      if (match != null) usedNumbers.add(int.parse(match.group(1)!));
    }
    var n = 1;
    while (usedNumbers.contains(n)) {
      n++;
    }
    return 'Untitled Piece $n';
  }

  Future<void> _createPieceFromCamera() async {
    setState(() => _processing = true);

    try {
      final imageService = ref.read(imageServiceProvider);
      const uuid = Uuid();
      final pieceId = uuid.v4();

      final result = await imageService.pickAndProcessImage(
        source: ImageSource.camera,
        pieceId: pieceId,
      );

      if (result == null) {
        if (mounted) context.pop();
        return;
      }

      await _savePiece(pieceId, [result]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not capture photo: $e')),
        );
        context.pop();
      }
    }
  }

  Future<void> _createPieceFromGallery() async {
    try {
      final imageService = ref.read(imageServiceProvider);
      final picked = await imageService.pickMultipleImages();

      if (picked == null) {
        if (mounted) context.pop();
        return;
      }

      setState(() => _processing = true);

      const uuid = Uuid();
      final pieceId = uuid.v4();
      final results = <ImageResult>[];

      for (final file in picked) {
        try {
          final bytes = await file.readAsBytes();
          final result = await imageService.processImage(
            bytes: bytes,
            pieceId: pieceId,
          );
          results.add(result);
        } catch (_) {
          // Skip failed photos
        }
      }

      if (results.isEmpty) {
        if (mounted) context.pop();
        return;
      }

      await _savePiece(pieceId, results);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add photos: $e')),
        );
        context.pop();
      }
    }
  }

  Future<void> _savePiece(String pieceId, List<ImageResult> results) async {
    final now = DateTime.now();
    final piecesDao = ref.read(piecesDaoProvider);
    final photosDao = ref.read(photosDaoProvider);

    final title = await _nextUntitledName(piecesDao);

    await piecesDao.insertPiece(PiecesCompanion(
      id: Value(pieceId),
      title: Value(title),
      coverPhotoId: Value(results.last.photoId),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));

    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      await photosDao.insertPhoto(PhotosCompanion(
        id: Value(result.photoId),
        pieceId: Value(pieceId),
        localPath: Value(result.localPath),
        thumbnailPath: Value(result.thumbnailPath),
        dateTaken: Value(result.dateTaken),
        createdAt: Value(now),
        sortOrder: Value(i),
      ));
    }

    HapticFeedback.lightImpact();
    ref.read(analyticsProvider).logEvent(
      name: 'piece_created',
      parameters: {'photo_count': results.length},
    );
    final trigger = ref.read(syncTriggerProvider);
    await trigger.afterPieceWrite(pieceId);
    for (final result in results) {
      await trigger.afterPhotoWrite(result.photoId, includeFile: true);
    }
    if (mounted) context.go('/piece/$pieceId');
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
