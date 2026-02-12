enum PieceStage {
  greenware,
  bisqued,
  glazed;

  String get displayName => switch (this) {
        PieceStage.greenware => 'Greenware',
        PieceStage.bisqued => 'Bisqued',
        PieceStage.glazed => 'Glazed',
      };
}
