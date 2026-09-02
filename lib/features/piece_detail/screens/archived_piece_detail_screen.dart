import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../database/database.dart';
import '../../../models/display_date.dart';
import '../../../models/piece_stage.dart';
import '../../../providers/analytics_provider.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/materials_provider.dart';
import '../../../providers/photos_provider.dart';
import '../../../providers/piece_writer_provider.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/stage_badge.dart';
import '../../../widgets/tag_chip.dart';
import '../widgets/delete_piece_dialog.dart';
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
    await ref.read(pieceWriterProvider).setArchived(widget.pieceId, false);
    HapticFeedback.lightImpact();
    ref.read(analyticsProvider).logEvent(name: 'piece_unarchived');
    if (mounted) {
      AppSnackbar.show(
        context,
        message: AppLocalizations.of(
          context,
        )!.pieceUnarchivedWithTitle(_piece!.title ?? 'Untitled Piece'),
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
        data: (photos) => LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSizes.xl),
                  // Title + Stage
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.md,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (stage != null) ...[
                          const SizedBox(width: AppSizes.sm),
                          StageBadge(stage: stage),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSizes.sm),

                  // Photo gallery (read-only: no add, no delete, no date edit)
                  PhotoGallery(
                    photos: photos,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.md,
                    ),
                  ),
                  const SizedBox(height: AppSizes.md),

                  // Metadata section
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Date
                        Text(
                          _formatDisplayDate(photos),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.charcoal.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                        ),

                        // Clay
                        if (_piece!.clayType != null &&
                            _piece!.clayType!.isNotEmpty) ...[
                          const SizedBox(height: AppSizes.sm),
                          _metadataLine(context, 'Clay', _piece!.clayType!),
                        ],

                        // Glazes
                        glazesAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                          data: (glazes) {
                            if (glazes.isEmpty) return const SizedBox.shrink();
                            final names = glazes.map((g) => g.name).toList();
                            final prefix = names.length > 1
                                ? 'Glazes'
                                : 'Glaze';
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
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: AppColors.charcoal.withValues(
                                    alpha: 0.7,
                                  ),
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
                                  return TagChip(
                                    tag: tag.name,
                                    customColor: tagColorMap[tag.name],
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
        ),
      ),
    );
  }

  String _formatDisplayDate(List<Photo> photos) {
    return DateFormat.yMMMd().format(resolveDisplayDate(_piece!, photos));
  }

  Widget _metadataLine(BuildContext context, String label, String value) {
    return Text(
      '$label: $value',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: AppColors.charcoal.withValues(alpha: 0.7),
      ),
    );
  }
}
