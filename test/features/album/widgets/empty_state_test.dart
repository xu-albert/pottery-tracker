import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/features/album/widgets/empty_state.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  group('EmptyState', () {
    testWidgets('renders icon', (tester) async {
      await pumpApp(tester, const EmptyState());

      expect(find.byIcon(Icons.emoji_objects_outlined), findsOneWidget);
    });

    testWidgets('renders title text', (tester) async {
      await pumpApp(tester, const EmptyState());

      expect(find.text('No pieces yet'), findsOneWidget);
    });

    testWidgets('renders message text', (tester) async {
      await pumpApp(tester, const EmptyState());

      expect(
        find.text('Tap + to take a photo and start tracking your first piece!'),
        findsOneWidget,
      );
    });
  });
}
