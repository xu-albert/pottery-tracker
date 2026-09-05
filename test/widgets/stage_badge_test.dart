import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/models/piece_stage.dart';
import 'package:pottery_tracker/widgets/stage_badge.dart';

import '../helpers/test_helpers.dart';

void main() {
  for (final stage in PieceStage.values) {
    testWidgets('shows ${stage.name} in its own colour', (tester) async {
      await pumpApp(tester, StageBadge(stage: stage));

      final text = tester.widget<Text>(find.text(stage.displayName));
      expect(text.style?.color, stage.color);
      expect(text.style?.fontWeight, FontWeight.w600);

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(StageBadge),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, stage.color.withValues(alpha: 0.2));
    });
  }
}
