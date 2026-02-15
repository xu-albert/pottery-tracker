import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';

enum PieceStage {
  greenware,
  bisqued,
  glazed;

  String get displayName => switch (this) {
    PieceStage.greenware => 'Greenware',
    PieceStage.bisqued => 'Bisqued',
    PieceStage.glazed => 'Glazed',
  };

  Color get color => switch (this) {
    PieceStage.greenware => AppColors.sage,
    PieceStage.bisqued => AppColors.terracotta,
    PieceStage.glazed => AppColors.blue,
  };
}
