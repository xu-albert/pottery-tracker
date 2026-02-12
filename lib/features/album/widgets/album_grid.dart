import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../database/daos/pieces_dao.dart';
import 'archive_thumbnail.dart';
import 'piece_row.dart';

class AlbumGrid extends StatelessWidget {
  final List<PieceWithCover> pieces;
  final bool isArchived;

  const AlbumGrid({super.key, required this.pieces, this.isArchived = false});

  @override
  Widget build(BuildContext context) {
    if (isArchived) {
      return GridView.builder(
        padding: const EdgeInsets.all(AppSizes.sm),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: AppSizes.albumColumns,
          crossAxisSpacing: AppSizes.albumSpacing,
          mainAxisSpacing: AppSizes.albumSpacing,
          childAspectRatio: 1.0,
        ),
        itemCount: pieces.length,
        itemBuilder: (context, index) {
          final item = pieces[index];
          return ArchiveThumbnail(
            piece: item,
            onTap: () => context.push('/piece/${item.piece.id}'),
          );
        },
      );
    }

    return ListView.separated(
      itemCount: pieces.length,
      separatorBuilder: (_, _) => const Divider(
        height: AppSizes.xl,
        thickness: 0.5,
        color: AppColors.divider,
        indent: AppSizes.md,
        endIndent: AppSizes.md,
      ),
      itemBuilder: (context, index) {
        final item = pieces[index];
        return PieceRow(
          piece: item,
          onTap: () => context.push('/piece/${item.piece.id}'),
        );
      },
    );
  }
}
