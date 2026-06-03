import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pottery_tracker/services/review_prompt_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockInAppReview extends Mock implements InAppReview {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockInAppReview mockReview;

  setUp(() {
    mockReview = _MockInAppReview();
    when(() => mockReview.isAvailable()).thenAnswer((_) async => true);
    when(() => mockReview.requestReview()).thenAnswer((_) async {});
  });

  ReviewPromptService buildService({
    required DateTime now,
    required int pieceCount,
  }) {
    return ReviewPromptService(
      now: () => now,
      inAppReview: mockReview,
      pieceCount: () async => pieceCount,
    );
  }

  group('shouldPrompt gates', () {
    test('returns false when piece count < 3', () async {
      SharedPreferences.setMockInitialValues({
        'review_prompt_first_launch_date': DateTime(
          2026,
          5,
          1,
        ).toIso8601String(),
        'review_prompt_session_count': 5,
      });
      final service = buildService(now: DateTime(2026, 5, 9), pieceCount: 2);
      expect(await service.shouldPrompt(), isFalse);
    });

    test('returns false when session count < 2', () async {
      SharedPreferences.setMockInitialValues({
        'review_prompt_first_launch_date': DateTime(
          2026,
          5,
          1,
        ).toIso8601String(),
        'review_prompt_session_count': 1,
      });
      final service = buildService(now: DateTime(2026, 5, 9), pieceCount: 5);
      expect(await service.shouldPrompt(), isFalse);
    });

    test('returns false when first launch < 3 days ago', () async {
      SharedPreferences.setMockInitialValues({
        'review_prompt_first_launch_date': DateTime(
          2026,
          5,
          8,
        ).toIso8601String(),
        'review_prompt_session_count': 5,
      });
      final service = buildService(now: DateTime(2026, 5, 9), pieceCount: 5);
      expect(await service.shouldPrompt(), isFalse);
    });

    test('returns false when first_launch_date missing', () async {
      SharedPreferences.setMockInitialValues({
        'review_prompt_session_count': 5,
      });
      final service = buildService(now: DateTime(2026, 5, 9), pieceCount: 5);
      expect(await service.shouldPrompt(), isFalse);
    });

    test('returns false when last_prompted_at < 90 days ago', () async {
      SharedPreferences.setMockInitialValues({
        'review_prompt_first_launch_date': DateTime(
          2026,
          1,
          1,
        ).toIso8601String(),
        'review_prompt_session_count': 5,
        'review_prompt_last_prompted_at': DateTime(
          2026,
          4,
          1,
        ).toIso8601String(),
      });
      final service = buildService(now: DateTime(2026, 5, 9), pieceCount: 5);
      expect(await service.shouldPrompt(), isFalse);
    });

    test('returns true when all gates pass', () async {
      SharedPreferences.setMockInitialValues({
        'review_prompt_first_launch_date': DateTime(
          2026,
          5,
          1,
        ).toIso8601String(),
        'review_prompt_session_count': 2,
      });
      final service = buildService(now: DateTime(2026, 5, 9), pieceCount: 3);
      expect(await service.shouldPrompt(), isTrue);
    });

    test('returns true when last_prompted_at >= 90 days ago', () async {
      SharedPreferences.setMockInitialValues({
        'review_prompt_first_launch_date': DateTime(
          2025,
          1,
          1,
        ).toIso8601String(),
        'review_prompt_session_count': 5,
        'review_prompt_last_prompted_at': DateTime(
          2026,
          2,
          1,
        ).toIso8601String(),
      });
      final service = buildService(now: DateTime(2026, 5, 9), pieceCount: 5);
      expect(await service.shouldPrompt(), isTrue);
    });
  });

  group('recordPrompted', () {
    test('sets last_prompted_at to now', () async {
      SharedPreferences.setMockInitialValues({});
      final service = buildService(
        now: DateTime(2026, 5, 9, 14, 30),
        pieceCount: 0,
      );
      await service.recordPrompted();
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('review_prompt_last_prompted_at'),
        DateTime(2026, 5, 9, 14, 30).toIso8601String(),
      );
    });
  });

  group('recordCompleted', () {
    test('sets completed flag to true', () async {
      SharedPreferences.setMockInitialValues({});
      final service = buildService(now: DateTime(2026, 5, 9), pieceCount: 0);
      await service.recordCompleted();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('review_prompt_completed'), isTrue);
    });
  });

  group('maybePromptAfterPieceSave gating', () {
    testWidgets('does nothing when shouldPrompt is false', (tester) async {
      SharedPreferences.setMockInitialValues(
        {},
      ); // missing first launch -> false
      final service = buildService(now: DateTime(2026, 5, 9), pieceCount: 5);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              service.maybePromptAfterPieceSave(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      verifyNever(() => mockReview.requestReview());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('review_prompt_last_prompted_at'), isNull);
    });
  });
}
