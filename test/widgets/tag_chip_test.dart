import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/core/constants/app_colors.dart';
import 'package:pottery_tracker/widgets/tag_chip.dart';

import '../helpers/test_helpers.dart';

void main() {
  Container chipContainer(WidgetTester tester) {
    return tester.widget<Container>(
      find.descendant(
        of: find.byType(TagChip),
        matching: find.byType(Container),
      ),
    );
  }

  Color? textColor(WidgetTester tester, String text) {
    return tester.widget<Text>(find.text(text)).style?.color;
  }

  testWidgets('renders a hash prefix and the tag name', (tester) async {
    await pumpApp(tester, const TagChip(tag: 'gift'));

    expect(find.text('#'), findsOneWidget);
    expect(find.text('gift'), findsOneWidget);
  });

  testWidgets('a custom colour drives both background and text', (
    tester,
  ) async {
    const base = Color(0xFFB55A5A);
    await pumpApp(tester, const TagChip(tag: 'gift', customColor: base));

    final (expectedBg, expectedText) = TagColorPresets.colorsFor(base);
    final decoration = chipContainer(tester).decoration as BoxDecoration;
    expect(decoration.color, expectedBg);
    expect(textColor(tester, 'gift'), expectedText);
    expect(textColor(tester, '#'), expectedText.withValues(alpha: 0.5));
  });

  testWidgets('without a custom colour the palette pick is stable', (
    tester,
  ) async {
    await pumpApp(tester, const TagChip(tag: 'gift'));
    final first = (chipContainer(tester).decoration as BoxDecoration).color;

    await pumpApp(tester, const TagChip(tag: 'gift'));
    final second = (chipContainer(tester).decoration as BoxDecoration).color;

    expect(first, second);
    expect(
      TagChip.defaultColors.map((c) => c.$1.withValues(alpha: 0.18)),
      contains(first),
    );
  });

  testWidgets('colorsFor matches what the widget paints', (tester) async {
    await pumpApp(tester, const TagChip(tag: 'wheel'));

    final (bg, text) = TagChip.colorsFor('wheel', null);
    expect((chipContainer(tester).decoration as BoxDecoration).color, bg);
    expect(textColor(tester, 'wheel'), text);
  });

  testWidgets('a long tag is capped in width and ellipsised', (tester) async {
    await pumpApp(
      tester,
      const TagChip(tag: 'an extremely long tag name that keeps going'),
    );

    expect(tester.getSize(find.byType(TagChip)).width, lessThanOrEqualTo(150));
    final text = tester.widget<Text>(
      find.text('an extremely long tag name that keeps going'),
    );
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });
}
