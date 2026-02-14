import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../database/database.dart';
import '../../../database/daos/pieces_dao.dart';
import '../../../models/piece_stage.dart';
import '../../../providers/photos_provider.dart';

class PieceRow extends ConsumerWidget {
  final PieceWithCover piece;
  final VoidCallback onTap;

  const PieceRow({super.key, required this.piece, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photosAsync = ref.watch(photosForPieceProvider(piece.piece.id));
    final title = piece.piece.title ?? 'Untitled Piece';
    final stage = piece.piece.stage != null
        ? PieceStage.values.byName(piece.piece.stage!)
        : null;
    final metadataChips = _buildMetadataChips(context);

    return Semantics(
      label: title,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(
            left: AppSizes.md,
            right: AppSizes.md,
            top: AppSizes.sm,
            bottom: AppSizes.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (stage != null) ...[
                    const SizedBox(width: AppSizes.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: stage.color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        stage.displayName,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: stage.color,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                DateFormat.yMMMd().format(piece.piece.updatedAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.charcoal.withValues(alpha: 0.5),
                    ),
              ),
              ..._buildClayGlazeLines(context),
              const SizedBox(height: AppSizes.sm),
              photosAsync.when(
                loading: () => _buildPhotoRowPlaceholder(context),
                error: (_, _) => _buildPhotoRowPlaceholder(context),
                data: (photos) => _buildPhotoRow(context, photos),
              ),
              if (metadataChips.isNotEmpty) ...[
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _interleave(
                      metadataChips,
                      const SizedBox(width: 4),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMetadataChips(BuildContext context) {
    final chips = <Widget>[];
    final textStyle = Theme.of(context).textTheme.bodySmall;

    final tags = piece.piece.tags;
    if (tags != null && tags.isNotEmpty) {
      for (final tag in tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty)) {
        chips.add(_tagChip(context, tag, textStyle));
      }
    }

    return chips;
  }

  List<Widget> _buildClayGlazeLines(BuildContext context) {
    final lines = <Widget>[];
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: AppColors.charcoal.withValues(alpha: 0.7),
        );

    final clay = piece.piece.clayType;
    if (clay != null && clay.isNotEmpty) {
      lines.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('Clay: $clay', style: textStyle),
      ));
    }

    final glazes = piece.piece.glazes;
    if (glazes != null && glazes.isNotEmpty) {
      final glazeList = glazes.split(',').map((g) => g.trim()).where((g) => g.isNotEmpty).toList();
      final prefix = glazeList.length > 1 ? 'Glazes' : 'Glaze';
      lines.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('$prefix: ${glazeList.join(', ')}', style: textStyle),
      ));
    }

    return lines;
  }

  // Each entry: (background tint color, accessible text color)
  static const _defaultTagColors = [
    (AppColors.teal, AppColors.teal),                   // #2D6E6E — dark enough
    (AppColors.terracotta, Color(0xFF8B5536)),           // darken terracotta for text
    (AppColors.dustyRose, Color(0xFF8B5D55)),            // darken dustyRose for text
    (AppColors.sage, Color(0xFF536B53)),                 // darken sage for text
    (AppColors.blue, AppColors.blue),                    // #4A7FB5 — dark enough
  ];

  Widget _tagChip(BuildContext context, String tag, TextStyle? textStyle) {
    final colorIndex = tag.hashCode.abs() % _defaultTagColors.length;
    final (bgColor, textColor) = _defaultTagColors[colorIndex];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('#', style: textStyle?.copyWith(color: textColor.withValues(alpha: 0.5))),
          const SizedBox(width: 2),
          Text(tag, style: textStyle?.copyWith(color: textColor)),
        ],
      ),
    );
  }

  static List<Widget> _interleave(List<Widget> widgets, Widget separator) {
    if (widgets.length <= 1) return widgets;
    return [
      for (int i = 0; i < widgets.length; i++) ...[
        if (i > 0) separator,
        widgets[i],
      ],
    ];
  }

  Widget _buildPhotoRow(BuildContext context, List<Photo> photos) {
    if (photos.isEmpty) {
      return _buildPhotoRowPlaceholder(context);
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = screenWidth - AppSizes.md * 2;
    final thumbSize = (availableWidth - AppSizes.sm * 2) / 3;

    return _ScrollablePhotoRow(
      photos: photos,
      thumbSize: thumbSize,
      placeholderBuilder: _placeholderTile,
    );
  }

  Widget _buildPhotoRowPlaceholder(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = screenWidth - AppSizes.md * 2;
    final thumbSize = (availableWidth - AppSizes.sm * 2) / 3;

    return SizedBox(
      height: thumbSize,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        child: SizedBox(
          width: thumbSize,
          height: thumbSize,
          child: _placeholderTile(),
        ),
      ),
    );
  }

  Widget _placeholderTile() {
    return Container(
      color: AppColors.peach.withValues(alpha: 0.3),
      child: const Icon(Icons.image_outlined, color: AppColors.charcoal),
    );
  }
}

class _ScrollablePhotoRow extends StatefulWidget {
  final List<Photo> photos;
  final double thumbSize;
  final Widget Function() placeholderBuilder;

  const _ScrollablePhotoRow({
    required this.photos,
    required this.thumbSize,
    required this.placeholderBuilder,
  });

  @override
  State<_ScrollablePhotoRow> createState() => _ScrollablePhotoRowState();
}

class _ScrollablePhotoRowState extends State<_ScrollablePhotoRow> {
  final _scrollController = ScrollController();
  bool _showLeftGradient = false;
  bool _showRightGradient = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _checkOverflow() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    setState(() {
      _showRightGradient = maxScroll > 0;
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atStart = pos.pixels <= 0;
    final atEnd = pos.pixels >= pos.maxScrollExtent - 1;
    if (_showLeftGradient != !atStart || _showRightGradient != !atEnd) {
      setState(() {
        _showLeftGradient = !atStart;
        _showRightGradient = !atEnd;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final gradientWidth = widget.thumbSize * 0.4;

    return SizedBox(
      height: widget.thumbSize,
      child: Stack(
        children: [
          ListView.separated(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: widget.photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSizes.sm),
            itemBuilder: (context, index) {
              final photo = widget.photos[index];
              final path = photo.thumbnailPath ?? photo.localPath;
              return ClipRRect(
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                child: SizedBox(
                  width: widget.thumbSize,
                  height: widget.thumbSize,
                  child: Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    cacheWidth: AppSizes.thumbnailSize.toInt(),
                    errorBuilder: (_, _, _) => widget.placeholderBuilder(),
                  ),
                ),
              );
            },
          ),
          if (_showLeftGradient)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: gradientWidth,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [
                        bgColor.withValues(alpha: 0),
                        bgColor.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_showRightGradient)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: gradientWidth,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        bgColor.withValues(alpha: 0),
                        bgColor.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
