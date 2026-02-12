import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../database/daos/pieces_dao.dart';
import '../../../core/constants/app_sizes.dart';
import 'piece_thumbnail.dart';

class AlbumGrid extends StatelessWidget {
  final List<PieceWithCover> pieces;

  const AlbumGrid({super.key, required this.pieces});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSizes.albumSpacing),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: AppSizes.albumColumns,
        crossAxisSpacing: AppSizes.albumSpacing,
        mainAxisSpacing: AppSizes.albumSpacing,
      ),
      itemCount: pieces.length,
      itemBuilder: (context, index) {
        final item = pieces[index];
        return PieceThumbnail(
          piece: item,
          onTap: () => context.push('/piece/${item.piece.id}'),
        );
      },
    );
  }
}
