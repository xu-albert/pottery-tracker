import 'dart:io';
import 'package:flutter/material.dart';
import '../../../database/daos/pieces_dao.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_colors.dart';

class PieceThumbnail extends StatelessWidget {
  final PieceWithCover piece;
  final VoidCallback onTap;

  const PieceThumbnail({super.key, required this.piece, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final thumbPath = piece.coverPhoto?.thumbnailPath ?? piece.coverPhoto?.localPath;

    return Semantics(
      label: piece.piece.title ?? 'Untitled piece',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumbPath != null)
                Image.file(
                  File(thumbPath),
                  fit: BoxFit.cover,
                  cacheWidth: AppSizes.thumbnailSize.toInt(),
                  errorBuilder: (_, _, _) => _placeholder(),
                )
              else
                _placeholder(),
              if (piece.piece.title != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.6),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Text(
                      piece.piece.title!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
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
