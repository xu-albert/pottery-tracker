import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pottery_tracker/features/feedback/screens/feedback_screen.dart';
import 'package:pottery_tracker/l10n/app_localizations.dart';
import 'package:pottery_tracker/providers/feedback_provider.dart';
import 'package:pottery_tracker/providers/review_prompt_provider.dart';
import 'package:pottery_tracker/providers/telemetry_provider.dart';
import 'package:pottery_tracker/services/feedback_service.dart';
import 'package:pottery_tracker/services/review_prompt_service.dart';
import 'package:pottery_tracker/services/telemetry_service.dart';

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

  Widget wrap({TelemetryService? telemetry}) => ProviderScope(
    overrides: [
      feedbackServiceProvider.overrideWithValue(feedback),
      reviewPromptServiceProvider.overrideWithValue(review),
      if (telemetry != null)
        telemetryServiceProvider.overrideWithValue(telemetry),
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

  testWidgets(
    'Send records sanitized non-fatal telemetry without user message or email on unexpected failure',
    (tester) async {
      final logs = <String>[];
      final recorded = <(Object, String, bool)>[];
      final telemetry = TelemetryService(
        isFirebaseReady: () => true,
        log: logs.add,
        recordError:
            (
              error,
              stack, {
              required String reason,
              required Iterable<Object> information,
              required bool fatal,
            }) async {
              recorded.add((error, reason, fatal));
            },
      );
      when(
        () => feedback.submit(
          category: any(named: 'category'),
          message: any(named: 'message'),
          replyEmail: any(named: 'replyEmail'),
        ),
      ).thenThrow(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'secret@example.com uid=user-123',
        ),
      );

      await tester.pumpWidget(wrap(telemetry: telemetry));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'private potter feedback text',
      );
      await tester.enterText(find.byType(TextField).last, 'potter@example.com');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
      await tester.pumpAndSettle();

      expect(recorded, hasLength(1));
      expect(recorded.single.$2, 'feedback.submit');
      expect(recorded.single.$3, isFalse);
      expect(
        recorded.single.$1.toString(),
        'feedback.submit: FirebaseException(plugin=cloud_firestore, code=permission-denied)',
      );
      final combined = '${logs.join(' ')} ${recorded.single.$1}';
      expect(combined, contains('category=other'));
      expect(combined, isNot(contains('private potter feedback text')));
      expect(combined, isNot(contains('potter@example.com')));
      expect(combined, isNot(contains('secret@example.com')));
      expect(combined, isNot(contains('user-123')));
    },
  );

  testWidgets('Send skips Crashlytics reporting on expected offline failure', (
    tester,
  ) async {
    var recordedCount = 0;
    final telemetry = TelemetryService(
      isFirebaseReady: () => true,
      log: (_) async {},
      recordError:
          (
            error,
            stack, {
            required String reason,
            required Iterable<Object> information,
            required bool fatal,
          }) async {
            recordedCount++;
          },
    );
    when(
      () => feedback.submit(
        category: any(named: 'category'),
        message: any(named: 'message'),
        replyEmail: any(named: 'replyEmail'),
      ),
    ).thenThrow(
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
    );

    await tester.pumpWidget(wrap(telemetry: telemetry));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'hello');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    await tester.pumpAndSettle();

    expect(recordedCount, 0);
  });
}
