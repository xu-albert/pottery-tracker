import 'package:drift/drift.dart' hide Column;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../database/database.dart';
import '../../../models/piece_stage.dart';
import '../../../providers/analytics_provider.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/materials_provider.dart';
import '../../../providers/photos_provider.dart';
import '../../../providers/image_service_provider.dart';
import '../../../providers/sync_provider.dart';
import '../widgets/photo_gallery.dart';

class ArchivedPieceDetailScreen extends ConsumerStatefulWidget {
  final String pieceId;

  const ArchivedPieceDetailScreen({super.key, required this.pieceId});

  @override
  ConsumerState<ArchivedPieceDetailScreen> createState() =>
      _ArchivedPieceDetailScreenState();
}

class _ArchivedPieceDetailScreenState
    extends ConsumerState<ArchivedPieceDetailScreen> {
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

  Future<void> _unarchive() async {
    final l10n = AppLocalizations.of(context)!;
    final dao = ref.read(piecesDaoProvider);
    await dao.updatePiece(
      PiecesCompanion(
        id: Value(widget.pieceId),
        isArchived: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    );
    HapticFeedback.lightImpact();
    ref.read(analyticsProvider).logEvent(name: 'piece_unarchived');
    await ref.read(syncTriggerProvider).afterPieceWrite(widget.pieceId);
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l10n.pieceUnarchivedWithTitle(
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
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l10n.deletePieceConfirmTitle),
        content: Text(l10n.deletePieceConfirmMessage),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final piecesDao = ref.read(piecesDaoProvider);
    final photosDao = ref.read(photosDaoProvider);
    final imageService = ref.read(imageServiceProvider);

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final photosAsync = ref.watch(photosForPieceProvider(widget.pieceId));
    final glazesAsync = ref.watch(glazesForPieceProvider(widget.pieceId));
    final tagsAsync = ref.watch(tagsForPieceProvider(widget.pieceId));
    final tagColorMap = ref.watch(tagColorMapProvider);

    if (_piece == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final title = _piece!.title ?? 'Untitled Piece';
    final stage = _piece!.stage != null
        ? PieceStage.values.byName(_piece!.stage!)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.unarchive_outlined),
            tooltip: l10n.unarchivePiece,
            onPressed: _unarchive,
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
        data: (photos) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo gallery (read-only: no add, no delete, no date edit)
              PhotoGallery(
                photos: photos,
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
              ),
              const SizedBox(height: AppSizes.md),

              // Metadata section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stage + Date row
                    Row(
                      children: [
                        if (stage != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: stage.color.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              stage.displayName,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: stage.color,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        if (stage != null) const SizedBox(width: AppSizes.sm),
                        Text(
                          _formatDisplayDate(photos),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: AppColors.charcoal.withValues(alpha: 0.5),
                              ),
                        ),
                      ],
                    ),

                    // Clay
                    if (_piece!.clayType != null &&
                        _piece!.clayType!.isNotEmpty) ...[
                      const SizedBox(height: AppSizes.sm),
                      _metadataLine(
                        context,
                        'Clay',
                        _piece!.clayType!,
                      ),
                    ],

                    // Glazes
                    glazesAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, _) => const SizedBox.shrink(),
                      data: (glazes) {
                        if (glazes.isEmpty) return const SizedBox.shrink();
                        final names =
                            glazes.map((g) => g.name).toList();
                        final prefix =
                            names.length > 1 ? 'Glazes' : 'Glaze';
                        return Padding(
                          padding: const EdgeInsets.only(top: AppSizes.sm),
                          child: _metadataLine(
                            context,
                            prefix,
                            names.join(', '),
                          ),
                        );
                      },
                    ),

                    // Notes
                    if (_piece!.notes != null &&
                        _piece!.notes!.isNotEmpty) ...[
                      const SizedBox(height: AppSizes.sm),
                      Text(
                        _piece!.notes!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.charcoal.withValues(alpha: 0.7),
                        ),
                      ),
                    ],

                    // Tags
                    tagsAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, _) => const SizedBox.shrink(),
                      data: (tags) {
                        if (tags.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: AppSizes.sm),
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: tags.map((tag) {
                              return _buildTagChip(
                                context,
                                tag.name,
                                tagColorMap,
                              );
                            }).toList(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: AppSizes.lg),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDisplayDate(List<Photo> photos) {
    final displayDate = _piece!.displayDate ??
        (photos.isNotEmpty
            ? photos
                  .map((p) => p.dateTaken)
                  .reduce((a, b) => a.isAfter(b) ? a : b)
            : null) ??
        _piece!.createdAt;
    return DateFormat.yMMMd().format(displayDate);
  }

  Widget _metadataLine(BuildContext context, String label, String value) {
    return Text(
      '$label: $value',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: AppColors.charcoal.withValues(alpha: 0.7),
      ),
    );
  }

  // Tag chip — same style as PieceRow
  static const _defaultTagColors = [
    (AppColors.teal, AppColors.teal),
    (AppColors.terracotta, Color(0xFF8B5536)),
    (AppColors.dustyRose, Color(0xFF8B5D55)),
    (AppColors.sage, Color(0xFF536B53)),
    (AppColors.blue, AppColors.blue),
  ];

  Widget _buildTagChip(
    BuildContext context,
    String tag,
    Map<String, Color> tagColorMap,
  ) {
    final textStyle = Theme.of(context).textTheme.bodySmall;
    final customColor = tagColorMap[tag];
    final Color bgColor;
    final Color textColor;
    if (customColor != null) {
      final colors = TagColorPresets.colorsFor(customColor);
      bgColor = colors.$1;
      textColor = colors.$2;
    } else {
      final colorIndex = tag.hashCode.abs() % _defaultTagColors.length;
      final defaults = _defaultTagColors[colorIndex];
      bgColor = defaults.$1.withValues(alpha: 0.18);
      textColor = defaults.$2;
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '#',
              style: textStyle?.copyWith(
                color: textColor.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                tag,
                style: textStyle?.copyWith(color: textColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
