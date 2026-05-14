import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pottery_tracker/features/feedback/screens/feedback_screen.dart';
import 'package:pottery_tracker/l10n/app_localizations.dart';
import 'package:pottery_tracker/providers/feedback_provider.dart';
import 'package:pottery_tracker/providers/review_prompt_provider.dart';
import 'package:pottery_tracker/services/feedback_service.dart';
import 'package:pottery_tracker/services/review_prompt_service.dart';

class _MockFeedbackService extends Mock implements FeedbackService {}

class _MockReviewPromptService extends Mock implements ReviewPromptService {}

void main() {
  setUpAll(() {
    registerFallbackValue(FeedbackCategory.other);
  });

  late _MockFeedbackService feedback;
  late _MockReviewPromptService review;

  setUp(() {
    feedback = _MockFeedbackService();
    review = _MockReviewPromptService();
    when(() => review.recordCompleted()).thenAnswer((_) async {});
  });

  Widget wrap() => ProviderScope(
    overrides: [
      feedbackServiceProvider.overrideWithValue(feedback),
      reviewPromptServiceProvider.overrideWithValue(review),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const FeedbackScreen(),
    ),
  );

  testWidgets('Send button disabled until message non-empty', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final sendButton = find.widgetWithText(ElevatedButton, 'Send');
    expect(tester.widget<ElevatedButton>(sendButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'hello');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(sendButton).onPressed, isNotNull);
  });

  testWidgets('Send invokes service and pops on success', (tester) async {
    when(
      () => feedback.submit(
        category: any(named: 'category'),
        message: any(named: 'message'),
        replyEmail: any(named: 'replyEmail'),
      ),
    ).thenAnswer((_) async {});

    await tester.pumpWidget(
      MaterialApp(
        home: ProviderScope(
          overrides: [
            feedbackServiceProvider.overrideWithValue(feedback),
            reviewPromptServiceProvider.overrideWithValue(review),
          ],
          child: Navigator(
            onGenerateRoute: (_) =>
                MaterialPageRoute(builder: (_) => const FeedbackScreen()),
          ),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'hello');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    await tester.pumpAndSettle();

    verify(
      () => feedback.submit(
        category: FeedbackCategory.other,
        message: 'hello',
        replyEmail: null,
      ),
    ).called(1);
    verify(() => review.recordCompleted()).called(1);
  });

  testWidgets('Send shows error and stays open on failure', (tester) async {
    when(
      () => feedback.submit(
        category: any(named: 'category'),
        message: any(named: 'message'),
        replyEmail: any(named: 'replyEmail'),
      ),
    ).thenThrow(Exception('boom'));

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'hello');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    await tester.pumpAndSettle();

    expect(find.byType(FeedbackScreen), findsOneWidget);
    expect(find.textContaining("Couldn't send"), findsOneWidget);
    verifyNever(() => review.recordCompleted());
  });
}
