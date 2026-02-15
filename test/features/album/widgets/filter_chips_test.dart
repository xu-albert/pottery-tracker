import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pottery_tracker/features/album/widgets/filter_chips.dart';
import 'package:pottery_tracker/providers/analytics_provider.dart';
import 'package:pottery_tracker/providers/pieces_provider.dart';

import '../../../helpers/mock_providers.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  late MockFirebaseAnalytics mockAnalytics;

  setUp(() {
    mockAnalytics = MockFirebaseAnalytics();
    when(() => mockAnalytics.logEvent(
          name: any(named: 'name'),
          parameters: any(named: 'parameters'),
        )).thenAnswer((_) async {});
  });

  group('FilterChips', () {
    testWidgets('Active is selected by default', (tester) async {
      await pumpApp(tester, const FilterChips(),
          overrides: [analyticsProvider.overrideWithValue(mockAnalytics)]);

      final activeChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Active'),
      );
      expect(activeChip.selected, isTrue);

      final archiveChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Archive'),
      );
      expect(archiveChip.selected, isFalse);
    });

    testWidgets('tapping Archive updates provider to true', (tester) async {
      late WidgetRef capturedRef;
      await pumpApp(
        tester,
        Consumer(builder: (context, ref, _) {
          capturedRef = ref;
          return const FilterChips();
        }),
        overrides: [analyticsProvider.overrideWithValue(mockAnalytics)],
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Archive'));
      await tester.pumpAndSettle();

      expect(capturedRef.read(archivedFilterProvider), isTrue);
    });

    testWidgets('tapping Active after Archive sets back to false',
        (tester) async {
      late WidgetRef capturedRef;
      await pumpApp(
        tester,
        Consumer(builder: (context, ref, _) {
          capturedRef = ref;
          return const FilterChips();
        }),
        overrides: [analyticsProvider.overrideWithValue(mockAnalytics)],
      );

      // Tap Archive first
      await tester.tap(find.widgetWithText(ChoiceChip, 'Archive'));
      await tester.pumpAndSettle();
      expect(capturedRef.read(archivedFilterProvider), isTrue);

      // Tap Active
      await tester.tap(find.widgetWithText(ChoiceChip, 'Active'));
      await tester.pumpAndSettle();
      expect(capturedRef.read(archivedFilterProvider), isFalse);
    });
  });
}
