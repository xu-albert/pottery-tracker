import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../database/database.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_colors.dart';

class LastUpdatedInfo extends StatelessWidget {
  final Piece piece;

  const LastUpdatedInfo({super.key, required this.piece});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat.yMMMd().add_jm();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
      child: Row(
        children: [
          Icon(Icons.access_time, size: 16, color: AppColors.charcoal.withValues(alpha: 0.5)),
          const SizedBox(width: AppSizes.xs),
          Text(
            'Last updated ${dateFormat.format(piece.updatedAt)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.charcoal.withValues(alpha: 0.5),
                ),
          ),
        ],
      ),
    );
  }
}
