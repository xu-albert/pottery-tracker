import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../database/daos/pieces_dao.dart';

class ArchiveThumbnail extends StatelessWidget {
  final PieceWithCover piece;
  final VoidCallback onTap;

  const ArchiveThumbnail({
    super.key,
    required this.piece,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = piece.piece.title ?? 'Untitled Piece';
    final coverPath = piece.coverPhoto?.thumbnailPath ??
        piece.coverPhoto?.localPath;

    return Semantics(
      label: title,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          child: SizedBox.expand(
            child: coverPath != null
                ? Image.file(
                    File(coverPath),
                    fit: BoxFit.cover,
                    cacheWidth: AppSizes.thumbnailSize.toInt(),
                    errorBuilder: (_, _, _) => _placeholder(),
                  )
                : _placeholder(),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.peach.withValues(alpha: 0.3),
      child: const Icon(Icons.image_outlined, color: AppColors.charcoal),
    );
  }
}
