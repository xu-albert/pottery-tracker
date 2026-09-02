import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/analytics_provider.dart';
import '../../../providers/image_service_provider.dart';
import '../../../providers/piece_writer_provider.dart';
import '../../../providers/review_prompt_provider.dart';
import '../../../services/image_service.dart';
import '../../../widgets/app_snackbar.dart';

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
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, 'camera'),
            child: Text(l10n.camera),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, 'gallery'),
            child: Text(l10n.photoLibrary),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.cancel),
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
        AppSnackbar.show(context, message: 'Could not capture photo: $e');
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
        AppSnackbar.show(context, message: 'Could not add photos: $e');
        context.pop();
      }
    }
  }

  Future<void> _savePiece(String pieceId, List<ImageResult> results) async {
    await ref
        .read(pieceWriterProvider)
        .createPiece(pieceId: pieceId, photos: results);

    HapticFeedback.lightImpact();
    ref
        .read(analyticsProvider)
        .logEvent(
          name: 'piece_created',
          parameters: {'photo_count': results.length},
        );
    if (mounted) {
      await ref
          .read(reviewPromptServiceProvider)
          .maybePromptAfterPieceSave(context);
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
