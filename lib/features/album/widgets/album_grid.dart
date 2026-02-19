import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../database/database.dart';
import '../../../database/daos/pieces_dao.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/analytics_provider.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/pieces_provider.dart';
import '../../../providers/sync_provider.dart';
import 'archive_thumbnail.dart';
import 'piece_row.dart';

class AlbumGrid extends ConsumerWidget {
  final List<PieceWithCover> pieces;
  final bool isArchived;
  final ViewMode viewMode;

  const AlbumGrid({
    super.key,
    required this.pieces,
    required this.viewMode,
    this.isArchived = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (viewMode == ViewMode.grid) {
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

    final l10n = AppLocalizations.of(context)!;
    final piecesDao = ref.read(piecesDaoProvider);
    final syncTrigger = ref.read(syncTriggerProvider);

    return ListView.separated(
      itemCount: pieces.length,
      separatorBuilder: (_, _) => const Divider(
        height: AppSizes.sm,
        thickness: 0.5,
        color: AppColors.divider,
        indent: AppSizes.md,
        endIndent: AppSizes.md,
      ),
      itemBuilder: (context, index) {
        final item = pieces[index];
        final child = PieceRow(
          piece: item,
          onTap: () => context.push('/piece/${item.piece.id}'),
        );

        if (isArchived) return child;

        return Dismissible(
          key: ValueKey(item.piece.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: AppSizes.lg),
            color: AppColors.teal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  l10n.archivePiece,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: AppSizes.xs),
                const Icon(Icons.archive_outlined, color: Colors.white),
              ],
            ),
          ),
          onDismissed: (_) {
            HapticFeedback.lightImpact();
            ref.read(analyticsProvider).logEvent(name: 'piece_archived');
            final pieceId = item.piece.id;
            piecesDao.updatePiece(
              PiecesCompanion(
                id: Value(pieceId),
                isArchived: const Value(true),
                updatedAt: Value(DateTime.now()),
              ),
            );
            syncTrigger.afterPieceWrite(pieceId);
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(
                    l10n.pieceArchivedWithTitle(
                      item.piece.title ?? 'Untitled Piece',
                    ),
                  ),
                  duration: const Duration(seconds: 2),
                  action: SnackBarAction(
                    label: l10n.undo,
                    onPressed: () {
                      piecesDao.updatePiece(
                        PiecesCompanion(
                          id: Value(pieceId),
                          isArchived: const Value(false),
                          updatedAt: Value(DateTime.now()),
                        ),
                      );
                      syncTrigger.afterPieceWrite(pieceId);
                      ref
                          .read(analyticsProvider)
                          .logEvent(name: 'piece_unarchived');
                    },
                  ),
                ),
              );
          },
          child: child,
        );
      },
    );
  }
}
