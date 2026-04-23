import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_colors.dart';

class LastUpdatedInfo extends StatelessWidget {
  final DateTime displayDate;
  final VoidCallback? onTap;

  const LastUpdatedInfo({super.key, required this.displayDate, this.onTap});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat.yMMMd();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(
                Icons.access_time,
                size: 16,
                color: AppColors.charcoal.withValues(alpha: 0.5),
              ),
              const SizedBox(width: AppSizes.xs),
              Text(
                dateFormat.format(displayDate),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.charcoal.withValues(alpha: 0.5),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: AppSizes.xs),
                Icon(
                  Icons.edit,
                  size: 14,
                  color: AppColors.charcoal.withValues(alpha: 0.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
