import 'package:flutter/material.dart';

import '../models/piece_stage.dart';

/// The tinted label that shows a piece's firing stage next to its title.
class StageBadge extends StatelessWidget {
  final PieceStage stage;

  const StageBadge({super.key, required this.stage});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: stage.color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        stage.displayName,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: stage.color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
