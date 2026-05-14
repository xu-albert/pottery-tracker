# In-App Review Prompt + Feedback Form Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an in-app soft-ask review prompt that fires after a user has demonstrated retention (3rd piece + multi-session + 3+ days), routing happy users to the native iOS/Android review sheet and unhappy users into a private in-app feedback form that writes to Firestore.

**Architecture:** Two services (`ReviewPromptService` for gating + native sheet, `FeedbackService` for Firestore writes), one new screen (`/feedback`) and one Cupertino dialog widget. Existing patterns from `lib/services/` and `lib/providers/` are followed. Trigger fires from `create_piece_screen._savePiece()` *before* navigating to the new piece detail — the dialog appears in the moment-of-accomplishment.

**Tech Stack:** Flutter 3.41, Riverpod, GoRouter, SharedPreferences, Cloud Firestore, `in_app_review`, `package_info_plus`, `device_info_plus`. Existing test infra: `mocktail`, `fake_cloud_firestore`.

**Spec:** `docs/superpowers/specs/2026-05-09-in-app-review-and-feedback-design.md`

---

## File Structure

### Files to create

| Path | Responsibility |
|---|---|
| `lib/services/review_prompt_service.dart` | Owns gating logic + native review sheet trigger. Reads/writes `review_prompt_*` SharedPreferences keys. Exposes `shouldPrompt()`, `recordPrompted()`, `recordCompleted()`, and `maybePromptAfterPieceSave(BuildContext)`. Constructor takes injectable `now`, `inAppReview`, `pieceCount` for tests. |
| `lib/services/feedback_service.dart` | Builds metadata-rich feedback documents and writes them to Firestore `feedback/{autoId}`. Pulls app/device info via `package_info_plus` + `device_info_plus`. |
| `lib/providers/review_prompt_provider.dart` | Riverpod `Provider<ReviewPromptService>` that wires `PiecesDao.count()` and the default `InAppReview` instance. |
| `lib/providers/feedback_provider.dart` | Riverpod `Provider<FeedbackService>` wiring `FirebaseFirestore.instance` + `FirebaseAuth.instance`. |
| `lib/features/feedback/screens/feedback_screen.dart` | Form UI: category dropdown, message TextField, optional reply email, Send/Cancel buttons. |
| `lib/features/feedback/widgets/enjoyment_dialog.dart` | Cupertino dialog returning a 3-state enum (`yes`, `no`, `dismissed`). |
| `test/services/review_prompt_service_test.dart` | Unit tests for gating + recording. |
| `test/services/feedback_service_test.dart` | Unit tests for doc construction. |
| `test/features/feedback/feedback_screen_test.dart` | Widget tests for form. |
| `test/features/feedback/enjoyment_dialog_test.dart` | Widget tests for dialog. |

### Files to modify

| Path | Change |
|---|---|
| `pubspec.yaml` | Add 3 dependencies. |
| `lib/l10n/app_en.arb` | Add new strings (existing `sendFeedback` key reused). |
| `lib/main.dart` | Increment `review_prompt_session_count`; set `review_prompt_first_launch_date` if absent. |
| `lib/router/app_router.dart` | Register `/feedback` route. |
| `lib/features/settings/screens/settings_screen.dart` | Replace existing `mailto:` `onTap` with `context.push('/feedback')`. |
| `lib/features/create_piece/screens/create_piece_screen.dart` | Call `ref.read(reviewPromptServiceProvider).maybePromptAfterPieceSave(context)` immediately before `context.go('/piece/$pieceId')`. |
| `firestore.rules` | Append `match /feedback/{docId}` block. |
| `test/helpers/mock_providers.dart` | Add `MockReviewPromptService`, `MockFeedbackService`, `MockInAppReview`. |
| `TEST_PLAN.md` | Add manual cases + changelog entry. |

---

## Task 1: Add dependencies + l10n strings

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/l10n/app_en.arb`

- [ ] **Step 1: Add dependencies to pubspec.yaml**

In `pubspec.yaml`, under `dependencies:`, add (place near the existing Firebase block):

```yaml
  # In-app review + device info
  in_app_review: ^2.0.10
  package_info_plus: ^8.3.0
  device_info_plus: ^11.3.0
```

- [ ] **Step 2: Run pub get**

```bash
flutter pub get
```

Expected: resolves cleanly, no version conflicts.

- [ ] **Step 3: Add l10n strings to app_en.arb**

Append to `lib/l10n/app_en.arb` (just before the closing `}`, with comma after the previous entry):

```json
  "enjoymentDialogTitle": "Enjoying Potter Journal?",
  "@enjoymentDialogTitle": { "description": "Soft-ask dialog title" },
  "enjoymentDialogYes": "Yes, I love it!",
  "@enjoymentDialogYes": { "description": "Soft-ask positive action" },
  "enjoymentDialogNo": "Could be better",
  "@enjoymentDialogNo": { "description": "Soft-ask negative action" },
  "feedbackScreenTitle": "Send Feedback",
  "@feedbackScreenTitle": { "description": "Feedback screen title" },
  "feedbackCategoryLabel": "Category",
  "@feedbackCategoryLabel": { "description": "Feedback category dropdown label" },
  "feedbackCategoryBug": "Bug",
  "@feedbackCategoryBug": { "description": "Bug category" },
  "feedbackCategoryFeature": "Feature request",
  "@feedbackCategoryFeature": { "description": "Feature request category" },
  "feedbackCategoryOther": "Other",
  "@feedbackCategoryOther": { "description": "Other category" },
  "feedbackCategoryPraise": "Praise",
  "@feedbackCategoryPraise": { "description": "Praise category" },
  "feedbackMessageLabel": "Message",
  "@feedbackMessageLabel": { "description": "Feedback message field label" },
  "feedbackMessageHint": "What's on your mind?",
  "@feedbackMessageHint": { "description": "Feedback message placeholder" },
  "feedbackReplyEmailLabel": "Reply email (optional)",
  "@feedbackReplyEmailLabel": { "description": "Optional reply email label" },
  "feedbackReplyEmailHint": "Only if you want a reply",
  "@feedbackReplyEmailHint": { "description": "Optional reply email helper" },
  "feedbackSendButton": "Send",
  "@feedbackSendButton": { "description": "Send feedback button" },
  "feedbackSentSuccess": "Thanks — we read every message",
  "@feedbackSentSuccess": { "description": "Toast after successful submit" },
  "feedbackSendFailed": "Couldn't send — try again later",
  "@feedbackSendFailed": { "description": "Toast after failed submit" }
```

- [ ] **Step 4: Regenerate l10n**

```bash
flutter gen-l10n
```

Expected: `lib/l10n/app_localizations.dart` and `app_localizations_en.dart` updated, no errors.

- [ ] **Step 5: Verify build still passes**

```bash
dart analyze
```

Expected: no new errors (warnings about unused l10n keys are OK — they'll be used in later tasks).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/l10n/
git commit -m "feat: add deps and l10n strings for review prompt + feedback"
```

---

## Task 2: ReviewPromptService — gating logic (TDD)

**Files:**
- Create: `lib/services/review_prompt_service.dart`
- Create: `test/services/review_prompt_service_test.dart`

The service exposes:

```
class ReviewPromptService {
  ReviewPromptService({
    DateTime Function()? now,
    InAppReview? inAppReview,
    required Future<int> Function() pieceCount,
  });

  Future<bool> shouldPrompt();
  Future<void> recordPrompted();      // sets last_prompted_at
  Future<void> recordCompleted();     // sets review_prompt_completed = true
  Future<void> maybePromptAfterPieceSave(BuildContext context);  // see Task 6
}
```

SharedPreferences keys:
- `review_prompt_first_launch_date` (String, ISO 8601)
- `review_prompt_session_count` (int)
- `review_prompt_last_prompted_at` (String, ISO 8601, nullable)
- `review_prompt_completed` (bool)

Gates (all must be true):
- `pieceCount() >= 3`
- `session_count >= 2`
- `now - first_launch_date >= Duration(days: 3)`
- `last_prompted_at == null` OR `now - last_prompted_at >= Duration(days: 90)`

Edge cases: if `first_launch_date` is missing in prefs, treat as fail-closed (return false). The setting of `first_launch_date` happens in `main.dart` (Task 7).

- [ ] **Step 1: Write the failing test file skeleton**

Create `test/services/review_prompt_service_test.dart`:

```dart
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
        'review_prompt_first_launch_date':
            DateTime(2026, 5, 1).toIso8601String(),
        'review_prompt_session_count': 5,
      });
      final service = buildService(now: DateTime(2026, 5, 9), pieceCount: 2);
      expect(await service.shouldPrompt(), isFalse);
    });

    test('returns false when session count < 2', () async {
      SharedPreferences.setMockInitialValues({
        'review_prompt_first_launch_date':
            DateTime(2026, 5, 1).toIso8601String(),
        'review_prompt_session_count': 1,
      });
      final service = buildService(now: DateTime(2026, 5, 9), pieceCount: 5);
      expect(await service.shouldPrompt(), isFalse);
    });

    test('returns false when first launch < 3 days ago', () async {
      SharedPreferences.setMockInitialValues({
        'review_prompt_first_launch_date':
            DateTime(2026, 5, 8).toIso8601String(),
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
        'review_prompt_first_launch_date':
            DateTime(2026, 1, 1).toIso8601String(),
        'review_prompt_session_count': 5,
        'review_prompt_last_prompted_at':
            DateTime(2026, 4, 1).toIso8601String(),
      });
      final service = buildService(now: DateTime(2026, 5, 9), pieceCount: 5);
      expect(await service.shouldPrompt(), isFalse);
    });

    test('returns true when all gates pass', () async {
      SharedPreferences.setMockInitialValues({
        'review_prompt_first_launch_date':
            DateTime(2026, 5, 1).toIso8601String(),
        'review_prompt_session_count': 2,
      });
      final service = buildService(now: DateTime(2026, 5, 9), pieceCount: 3);
      expect(await service.shouldPrompt(), isTrue);
    });

    test('returns true when last_prompted_at >= 90 days ago', () async {
      SharedPreferences.setMockInitialValues({
        'review_prompt_first_launch_date':
            DateTime(2025, 1, 1).toIso8601String(),
        'review_prompt_session_count': 5,
        'review_prompt_last_prompted_at':
            DateTime(2026, 2, 1).toIso8601String(),
      });
      final service = buildService(now: DateTime(2026, 5, 9), pieceCount: 5);
      expect(await service.shouldPrompt(), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/services/review_prompt_service_test.dart
```

Expected: All tests FAIL with "Target of URI doesn't exist: 'package:pottery_tracker/services/review_prompt_service.dart'".

- [ ] **Step 3: Implement the service to make tests pass**

Create `lib/services/review_prompt_service.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReviewPromptService {
  ReviewPromptService({
    DateTime Function()? now,
    InAppReview? inAppReview,
    required Future<int> Function() pieceCount,
  })  : _now = now ?? DateTime.now,
        _inAppReview = inAppReview ?? InAppReview.instance,
        _pieceCount = pieceCount;

  static const _kFirstLaunch = 'review_prompt_first_launch_date';
  static const _kSessions = 'review_prompt_session_count';
  static const _kLastPrompted = 'review_prompt_last_prompted_at';
  static const _kCompleted = 'review_prompt_completed';

  static const _minPieces = 3;
  static const _minSessions = 2;
  static const _minDaysSinceInstall = Duration(days: 3);
  static const _cooldown = Duration(days: 90);

  final DateTime Function() _now;
  final InAppReview _inAppReview;
  final Future<int> Function() _pieceCount;

  Future<bool> shouldPrompt() async {
    final prefs = await SharedPreferences.getInstance();

    final firstLaunchStr = prefs.getString(_kFirstLaunch);
    if (firstLaunchStr == null) return false;
    final firstLaunch = DateTime.parse(firstLaunchStr);
    if (_now().difference(firstLaunch) < _minDaysSinceInstall) return false;

    final sessions = prefs.getInt(_kSessions) ?? 0;
    if (sessions < _minSessions) return false;

    final lastPromptedStr = prefs.getString(_kLastPrompted);
    if (lastPromptedStr != null) {
      final lastPrompted = DateTime.parse(lastPromptedStr);
      if (_now().difference(lastPrompted) < _cooldown) return false;
    }

    final pieces = await _pieceCount();
    if (pieces < _minPieces) return false;

    return true;
  }

  Future<void> recordPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastPrompted, _now().toIso8601String());
  }

  Future<void> recordCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCompleted, true);
  }

  Future<void> maybePromptAfterPieceSave(BuildContext context) async {
    // Implemented in Task 6.
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/review_prompt_service_test.dart
```

Expected: All 7 tests PASS.

- [ ] **Step 5: Add recordPrompted/recordCompleted tests**

Append to the same test file (inside `void main()`):

```dart
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
      final service = buildService(
        now: DateTime(2026, 5, 9),
        pieceCount: 0,
      );
      await service.recordCompleted();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('review_prompt_completed'), isTrue);
    });
  });
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
flutter test test/services/review_prompt_service_test.dart
```

Expected: All 9 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/services/review_prompt_service.dart test/services/review_prompt_service_test.dart
git commit -m "feat: ReviewPromptService gating + record methods"
```

---

## Task 3: review_prompt_provider + main.dart wiring

**Files:**
- Create: `lib/providers/review_prompt_provider.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Create the provider**

Create `lib/providers/review_prompt_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/review_prompt_service.dart';
import 'database_provider.dart';

final reviewPromptServiceProvider = Provider<ReviewPromptService>((ref) {
  final piecesDao = ref.watch(piecesDaoProvider);
  return ReviewPromptService(
    pieceCount: () async => (await piecesDao.getAllPieces()).length,
  );
});
```

Note: `getAllPieces()` exists per `database/daos/pieces_dao.dart`. If a dedicated `count()` method exists, prefer that — check by running `grep -n "Future<int>" lib/database/daos/pieces_dao.dart`. Use whichever returns a piece count efficiently.

- [ ] **Step 2: Verify the count method**

```bash
grep -n "count\|getAllPieces" /Users/albertxu/Documents/pottery-tracker/lib/database/daos/pieces_dao.dart
```

If a dedicated `Future<int> countPieces()` method exists, edit the provider to use it. If only `getAllPieces()` exists, the implementation above is fine.

- [ ] **Step 3: Wire main.dart to track session count + first launch**

In `lib/main.dart`, after the existing `final prefs = await SharedPreferences.getInstance();` line (line 49), insert:

```dart
  // Review-prompt session tracking
  final sessions = prefs.getInt('review_prompt_session_count') ?? 0;
  await prefs.setInt('review_prompt_session_count', sessions + 1);
  if (prefs.getString('review_prompt_first_launch_date') == null) {
    await prefs.setString(
      'review_prompt_first_launch_date',
      DateTime.now().toIso8601String(),
    );
  }
```

- [ ] **Step 4: Run dart analyze**

```bash
dart analyze
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/review_prompt_provider.dart lib/main.dart
git commit -m "feat: wire ReviewPromptService provider + session/launch tracking"
```

---

## Task 4: FeedbackService — Firestore write (TDD)

**Files:**
- Create: `lib/services/feedback_service.dart`
- Create: `test/services/feedback_service_test.dart`

The service exposes:

```
enum FeedbackCategory { bug, feature, other, praise }

class FeedbackService {
  FeedbackService({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    Future<PackageInfo> Function()? packageInfoLoader,
    Future<Map<String, String>> Function()? deviceInfoLoader,
  });

  Future<void> submit({
    required FeedbackCategory category,
    required String message,
    String? replyEmail,
  });
}
```

The doc shape per the spec:

```
{
  uid:         String?,           // null if not signed in
  category:    String,            // "bug" | "feature" | "other" | "praise"
  message:     String,
  replyEmail:  String?,
  appVersion:  String,            // e.g. "1.1.0+5"
  platform:    String,            // "ios" | "android"
  osVersion:   String,
  deviceModel: String,
  locale:      String,
  createdAt:   FieldValue.serverTimestamp(),
}
```

- [ ] **Step 1: Write the failing tests**

Create `test/services/feedback_service_test.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pottery_tracker/services/feedback_service.dart';

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  late FakeFirebaseFirestore firestore;
  late _MockAuth auth;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = _MockAuth();
    when(() => auth.currentUser).thenReturn(null);
  });

  FeedbackService buildService() => FeedbackService(
        firestore: firestore,
        auth: auth,
        packageInfoLoader: () async => PackageInfo(
          appName: 'Potter Journal',
          packageName: 'com.albertxu.potterytracker',
          version: '1.1.0',
          buildNumber: '5',
        ),
        deviceInfoLoader: () async => {
          'platform': 'ios',
          'osVersion': 'iOS 26.2.1',
          'deviceModel': 'iPhone15,2',
        },
      );

  test('writes a doc with all fields populated', () async {
    final service = buildService();
    await service.submit(
      category: FeedbackCategory.bug,
      message: 'hello',
      replyEmail: 'a@b.com',
    );

    final docs = await firestore.collection('feedback').get();
    expect(docs.docs, hasLength(1));
    final data = docs.docs.first.data();
    expect(data['uid'], isNull);
    expect(data['category'], 'bug');
    expect(data['message'], 'hello');
    expect(data['replyEmail'], 'a@b.com');
    expect(data['appVersion'], '1.1.0+5');
    expect(data['platform'], 'ios');
    expect(data['osVersion'], 'iOS 26.2.1');
    expect(data['deviceModel'], 'iPhone15,2');
    expect(data['locale'], isNotNull);
    expect(data['createdAt'], isNotNull);
  });

  test('uses authenticated uid when signed in', () async {
    final user = _MockUser();
    when(() => user.uid).thenReturn('uid-123');
    when(() => auth.currentUser).thenReturn(user);

    final service = buildService();
    await service.submit(
      category: FeedbackCategory.feature,
      message: 'pls add tags',
    );

    final docs = await firestore.collection('feedback').get();
    expect(docs.docs.first.data()['uid'], 'uid-123');
  });

  test('omits replyEmail when not provided', () async {
    final service = buildService();
    await service.submit(
      category: FeedbackCategory.praise,
      message: 'love it',
    );

    final data = (await firestore.collection('feedback').get()).docs.first.data();
    expect(data['replyEmail'], isNull);
  });

  test('substitutes "unknown" when device-info loader throws', () async {
    final service = FeedbackService(
      firestore: firestore,
      auth: auth,
      packageInfoLoader: () async => PackageInfo(
        appName: 'Potter Journal',
        packageName: 'com.albertxu.potterytracker',
        version: '1.1.0',
        buildNumber: '5',
      ),
      deviceInfoLoader: () async => throw Exception('boom'),
    );
    await service.submit(
      category: FeedbackCategory.other,
      message: 'meh',
    );

    final data = (await firestore.collection('feedback').get()).docs.first.data();
    expect(data['platform'], 'unknown');
    expect(data['osVersion'], 'unknown');
    expect(data['deviceModel'], 'unknown');
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/services/feedback_service_test.dart
```

Expected: FAIL — `FeedbackService` URI doesn't exist.

- [ ] **Step 3: Implement the service**

Create `lib/services/feedback_service.dart`:

```dart
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum FeedbackCategory { bug, feature, other, praise }

extension FeedbackCategoryX on FeedbackCategory {
  String get value {
    switch (this) {
      case FeedbackCategory.bug:
        return 'bug';
      case FeedbackCategory.feature:
        return 'feature';
      case FeedbackCategory.other:
        return 'other';
      case FeedbackCategory.praise:
        return 'praise';
    }
  }
}

class FeedbackService {
  FeedbackService({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    Future<PackageInfo> Function()? packageInfoLoader,
    Future<Map<String, String>> Function()? deviceInfoLoader,
  })  : _firestore = firestore,
        _auth = auth,
        _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
        _deviceInfoLoader = deviceInfoLoader ?? _defaultDeviceInfo;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final Future<Map<String, String>> Function() _deviceInfoLoader;

  Future<void> submit({
    required FeedbackCategory category,
    required String message,
    String? replyEmail,
  }) async {
    PackageInfo? pkg;
    Map<String, String>? device;
    try {
      pkg = await _packageInfoLoader();
    } catch (_) {}
    try {
      device = await _deviceInfoLoader();
    } catch (_) {}

    final appVersion = pkg != null
        ? '${pkg.version}+${pkg.buildNumber}'
        : 'unknown';

    await _firestore.collection('feedback').add({
      'uid': _auth.currentUser?.uid,
      'category': category.value,
      'message': message,
      'replyEmail': replyEmail,
      'appVersion': appVersion,
      'platform': device?['platform'] ?? 'unknown',
      'osVersion': device?['osVersion'] ?? 'unknown',
      'deviceModel': device?['deviceModel'] ?? 'unknown',
      'locale': PlatformDispatcher.instance.locale.toString(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<Map<String, String>> _defaultDeviceInfo() async {
    final plugin = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final ios = await plugin.iosInfo;
      return {
        'platform': 'ios',
        'osVersion': '${ios.systemName} ${ios.systemVersion}',
        'deviceModel': ios.utsname.machine,
      };
    } else if (Platform.isAndroid) {
      final android = await plugin.androidInfo;
      return {
        'platform': 'android',
        'osVersion': 'Android ${android.version.release}',
        'deviceModel': android.model,
      };
    }
    return {
      'platform': 'unknown',
      'osVersion': 'unknown',
      'deviceModel': 'unknown',
    };
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/services/feedback_service_test.dart
```

Expected: All 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/feedback_service.dart test/services/feedback_service_test.dart
git commit -m "feat: FeedbackService writes feedback docs to Firestore"
```

---

## Task 5: feedback_provider

**Files:**
- Create: `lib/providers/feedback_provider.dart`

- [ ] **Step 1: Create the provider**

Create `lib/providers/feedback_provider.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/feedback_service.dart';

final feedbackServiceProvider = Provider<FeedbackService>((ref) {
  return FeedbackService(
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );
});
```

- [ ] **Step 2: Verify dart analyze**

```bash
dart analyze lib/providers/feedback_provider.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/providers/feedback_provider.dart
git commit -m "feat: feedbackServiceProvider"
```

---

## Task 6: EnjoymentDialog widget + maybePromptAfterPieceSave wiring

**Files:**
- Create: `lib/features/feedback/widgets/enjoyment_dialog.dart`
- Modify: `lib/services/review_prompt_service.dart`
- Create: `test/features/feedback/enjoyment_dialog_test.dart`

The dialog returns `EnjoymentResponse` enum: `yes`, `no`, `dismissed`. The service then routes accordingly:

- `yes` → `recordPrompted()` (already done before showing) → `requestReview()` if available → `recordCompleted()`
- `no` → push `/feedback` route
- `dismissed` → no further action (cooldown already started)

Per the spec: `last_prompted_at` is set the moment the dialog is shown, atomically.

- [ ] **Step 1: Write the failing dialog test**

Create `test/features/feedback/enjoyment_dialog_test.dart`:

```dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/features/feedback/widgets/enjoyment_dialog.dart';
import 'package:pottery_tracker/l10n/app_localizations.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (_) => child),
      );

  testWidgets('returns yes when "Yes" tapped', (tester) async {
    EnjoymentResponse? result;
    await tester.pumpWidget(wrap(Builder(builder: (context) {
      return CupertinoButton(
        onPressed: () async {
          result = await showEnjoymentDialog(context);
        },
        child: const Text('open'),
      );
    })));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, I love it!'));
    await tester.pumpAndSettle();
    expect(result, EnjoymentResponse.yes);
  });

  testWidgets('returns no when "Could be better" tapped', (tester) async {
    EnjoymentResponse? result;
    await tester.pumpWidget(wrap(Builder(builder: (context) {
      return CupertinoButton(
        onPressed: () async {
          result = await showEnjoymentDialog(context);
        },
        child: const Text('open'),
      );
    })));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Could be better'));
    await tester.pumpAndSettle();
    expect(result, EnjoymentResponse.no);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/features/feedback/enjoyment_dialog_test.dart
```

Expected: FAIL — `enjoyment_dialog.dart` URI doesn't exist.

- [ ] **Step 3: Implement the dialog**

Create `lib/features/feedback/widgets/enjoyment_dialog.dart`:

```dart
import 'package:flutter/cupertino.dart';
import '../../../l10n/app_localizations.dart';

enum EnjoymentResponse { yes, no, dismissed }

Future<EnjoymentResponse> showEnjoymentDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final result = await showCupertinoDialog<EnjoymentResponse>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(l10n.enjoymentDialogTitle),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(ctx, EnjoymentResponse.no),
          child: Text(l10n.enjoymentDialogNo),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx, EnjoymentResponse.yes),
          child: Text(l10n.enjoymentDialogYes),
        ),
      ],
    ),
  );
  return result ?? EnjoymentResponse.dismissed;
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/features/feedback/enjoyment_dialog_test.dart
```

Expected: 2 tests PASS.

- [ ] **Step 5: Implement maybePromptAfterPieceSave in ReviewPromptService**

Open `lib/services/review_prompt_service.dart` and replace the placeholder `maybePromptAfterPieceSave` with:

```dart
  Future<void> maybePromptAfterPieceSave(BuildContext context) async {
    if (!await shouldPrompt()) return;

    // Mark prompted atomically before showing the dialog (per design spec).
    await recordPrompted();

    if (!context.mounted) return;
    final response = await showEnjoymentDialog(context);

    switch (response) {
      case EnjoymentResponse.yes:
        if (await _inAppReview.isAvailable()) {
          await _inAppReview.requestReview();
        }
        await recordCompleted();
      case EnjoymentResponse.no:
        if (!context.mounted) return;
        context.push('/feedback');
      case EnjoymentResponse.dismissed:
        break;
    }
  }
```

Add the new imports at the top of the file:

```dart
import 'package:go_router/go_router.dart';
import '../features/feedback/widgets/enjoyment_dialog.dart';
```

- [ ] **Step 6: Add maybePromptAfterPieceSave tests**

Append to `test/services/review_prompt_service_test.dart`:

```dart
  group('maybePromptAfterPieceSave gating', () {
    testWidgets('does nothing when shouldPrompt is false', (tester) async {
      SharedPreferences.setMockInitialValues({});  // missing first launch -> false
      final service = buildService(
        now: DateTime(2026, 5, 9),
        pieceCount: 5,
      );
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
```

(More integration testing of the dialog path is covered manually + via the dialog widget test. Service-level routing through GoRouter is impractical to unit test cleanly; the rely-on-manual-test trade-off is acceptable here.)

- [ ] **Step 7: Run all relevant tests**

```bash
flutter test test/services/review_prompt_service_test.dart test/features/feedback/enjoyment_dialog_test.dart
```

Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/features/feedback/widgets/enjoyment_dialog.dart lib/services/review_prompt_service.dart test/features/feedback/enjoyment_dialog_test.dart test/services/review_prompt_service_test.dart
git commit -m "feat: EnjoymentDialog + maybePromptAfterPieceSave routing"
```

---

## Task 7: FeedbackScreen widget + widget test

**Files:**
- Create: `lib/features/feedback/screens/feedback_screen.dart`
- Create: `test/features/feedback/feedback_screen_test.dart`

The screen:
- AppBar with title (`feedbackScreenTitle`) and back button
- Category dropdown (default `FeedbackCategory.other`)
- Multiline message TextField (5 lines, max 2000 chars, required)
- Optional reply email TextField (pre-filled from auth if signed in)
- Cancel + Send buttons in the body
- On Send: disabled while submitting; calls `feedbackServiceProvider.submit(...)`; on success → toast + pop; on failure → toast, stay open
- After successful send (and before pop), call `reviewPromptServiceProvider.recordCompleted()`

- [ ] **Step 1: Write the failing widget test**

Create `test/features/feedback/feedback_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_review/in_app_review.dart';
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
    when(() => feedback.submit(
          category: any(named: 'category'),
          message: any(named: 'message'),
          replyEmail: any(named: 'replyEmail'),
        )).thenAnswer((_) async {});

    await tester.pumpWidget(MaterialApp(
      home: ProviderScope(
        overrides: [
          feedbackServiceProvider.overrideWithValue(feedback),
          reviewPromptServiceProvider.overrideWithValue(review),
        ],
        child: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => const FeedbackScreen(),
          ),
        ),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'hello');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    await tester.pumpAndSettle();

    verify(() => feedback.submit(
          category: FeedbackCategory.other,
          message: 'hello',
          replyEmail: null,
        )).called(1);
    verify(() => review.recordCompleted()).called(1);
  });

  testWidgets('Send shows error and stays open on failure', (tester) async {
    when(() => feedback.submit(
          category: any(named: 'category'),
          message: any(named: 'message'),
          replyEmail: any(named: 'replyEmail'),
        )).thenThrow(Exception('boom'));

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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/features/feedback/feedback_screen_test.dart
```

Expected: FAIL — feedback_screen.dart URI doesn't exist.

- [ ] **Step 3: Implement the screen**

Create `lib/features/feedback/screens/feedback_screen.dart`:

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/feedback_provider.dart';
import '../../../providers/review_prompt_provider.dart';
import '../../../services/feedback_service.dart';
import '../../../widgets/app_snackbar.dart';

class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  static const _maxMessageLength = 2000;

  FeedbackCategory _category = FeedbackCategory.other;
  final _messageController = TextEditingController();
  late final TextEditingController _emailController;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(
      text: FirebaseAuth.instance.currentUser?.email ?? '',
    );
    _messageController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _messageController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _submitting = true);
    try {
      await ref.read(feedbackServiceProvider).submit(
            category: _category,
            message: _messageController.text.trim(),
            replyEmail: _emailController.text.trim().isEmpty
                ? null
                : _emailController.text.trim(),
          );
      await ref.read(reviewPromptServiceProvider).recordCompleted();
      if (!mounted) return;
      AppSnackbar.show(context, message: l10n.feedbackSentSuccess);
      context.pop();
    } catch (_) {
      if (!mounted) return;
      AppSnackbar.show(context, message: l10n.feedbackSendFailed);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _categoryLabel(FeedbackCategory c, AppLocalizations l10n) {
    switch (c) {
      case FeedbackCategory.bug:
        return l10n.feedbackCategoryBug;
      case FeedbackCategory.feature:
        return l10n.feedbackCategoryFeature;
      case FeedbackCategory.other:
        return l10n.feedbackCategoryOther;
      case FeedbackCategory.praise:
        return l10n.feedbackCategoryPraise;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canSend =
        !_submitting && _messageController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.feedbackScreenTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<FeedbackCategory>(
              initialValue: _category,
              decoration: InputDecoration(
                labelText: l10n.feedbackCategoryLabel,
                border: const OutlineInputBorder(),
              ),
              items: FeedbackCategory.values
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(_categoryLabel(c, l10n)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _category = v);
              },
            ),
            const SizedBox(height: AppSizes.md),
            TextField(
              controller: _messageController,
              maxLength: _maxMessageLength,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: l10n.feedbackMessageLabel,
                hintText: l10n.feedbackMessageHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSizes.md),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: l10n.feedbackReplyEmailLabel,
                hintText: l10n.feedbackReplyEmailHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting ? null : () => context.pop(),
                    child: Text(l10n.cancel),
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: ElevatedButton(
                    onPressed: canSend ? _submit : null,
                    child: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.feedbackSendButton),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/features/feedback/feedback_screen_test.dart
```

Expected: 3 tests PASS. If any fail due to `AppSnackbar` requiring a `ScaffoldMessenger`, wrap the test scaffold appropriately — the existing `app_snackbar.dart` should already work inside `MaterialApp`, but if `AppSnackbar` calls `ScaffoldMessenger.of(context)`, the test setup using `Navigator` directly (test 2) may need a `ScaffoldMessenger` ancestor. Inspect `lib/widgets/app_snackbar.dart` and adjust the test wrapper if needed.

- [ ] **Step 5: Commit**

```bash
git add lib/features/feedback/ test/features/feedback/feedback_screen_test.dart
git commit -m "feat: FeedbackScreen with category dropdown and submit"
```

---

## Task 8: Add /feedback route to app_router.dart

**Files:**
- Modify: `lib/router/app_router.dart`

- [ ] **Step 1: Add the import**

Near the other feature imports (after line 15 `archived_piece_detail_screen.dart`), add:

```dart
import '../features/feedback/screens/feedback_screen.dart';
```

- [ ] **Step 2: Register the route**

Inside the `routes:` list (after the existing `/piece/:id` route), add:

```dart
      GoRoute(
        path: '/feedback',
        builder: (context, state) => const FeedbackScreen(),
      ),
```

- [ ] **Step 3: Verify**

```bash
dart analyze lib/router/app_router.dart
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/router/app_router.dart
git commit -m "feat: register /feedback route"
```

---

## Task 9: Replace Settings mailto with /feedback navigation

**Files:**
- Modify: `lib/features/settings/screens/settings_screen.dart`

The existing entry uses `launchUrl(Uri(scheme: 'mailto', ...))`. Replace it with `context.push('/feedback')`.

- [ ] **Step 1: Replace the onTap**

In `lib/features/settings/screens/settings_screen.dart`, find the ListTile around line 370-381 (the one with `Icons.mail_outline` and `l10n.sendFeedback`). Replace its `onTap` with:

```dart
            onTap: () => context.push('/feedback'),
```

The full replaced ListTile becomes:

```dart
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(l10n.sendFeedback),
            onTap: () => context.push('/feedback'),
          ),
```

- [ ] **Step 2: Verify dart analyze**

```bash
dart analyze lib/features/settings/screens/settings_screen.dart
```

Expected: no errors. The `url_launcher` import may now be unused IF no other code in this file calls `launchUrl` — verify with `grep -n "launchUrl" lib/features/settings/screens/settings_screen.dart`. If only the Ko-fi support tile uses it, leave the import. Do NOT remove it just because of this single replacement.

- [ ] **Step 3: Commit**

```bash
git add lib/features/settings/screens/settings_screen.dart
git commit -m "feat: route Settings 'Send feedback' to in-app /feedback form"
```

---

## Task 10: Wire create_piece_screen to call maybePromptAfterPieceSave

**Files:**
- Modify: `lib/features/create_piece/screens/create_piece_screen.dart`

The trigger fires inside `_savePiece` immediately *before* `context.go('/piece/$pieceId')`. The dialog awaits before navigation proceeds.

- [ ] **Step 1: Add the import**

Near the top of `create_piece_screen.dart`, alongside existing provider imports, add:

```dart
import '../../../providers/review_prompt_provider.dart';
```

- [ ] **Step 2: Insert the prompt call**

In `_savePiece` (around line 197), find the existing trailing block:

```dart
    final trigger = ref.read(syncTriggerProvider);
    await trigger.afterPieceWrite(pieceId);
    for (final result in results) {
      await trigger.afterPhotoWrite(result.photoId, includeFile: true);
    }
    if (mounted) context.go('/piece/$pieceId');
```

Insert one line before the `if (mounted) context.go(...)`:

```dart
    final trigger = ref.read(syncTriggerProvider);
    await trigger.afterPieceWrite(pieceId);
    for (final result in results) {
      await trigger.afterPhotoWrite(result.photoId, includeFile: true);
    }
    if (mounted) {
      await ref
          .read(reviewPromptServiceProvider)
          .maybePromptAfterPieceSave(context);
    }
    if (mounted) context.go('/piece/$pieceId');
```

The double `mounted` check is intentional — the dialog awaits, so the widget could unmount during the prompt.

- [ ] **Step 3: Verify dart analyze**

```bash
dart analyze lib/features/create_piece/screens/create_piece_screen.dart
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/features/create_piece/screens/create_piece_screen.dart
git commit -m "feat: trigger review prompt after piece save"
```

---

## Task 11: Update firestore.rules

**Files:**
- Modify: `firestore.rules`

- [ ] **Step 1: Append the feedback rule**

Edit `firestore.rules`. Add a new `match` block inside `match /databases/{database}/documents { ... }`, before the catch-all `match /{document=**}` rule:

```
    // Anyone (auth or anon) can submit feedback; nobody can read/update/delete
    match /feedback/{docId} {
      allow create: if request.resource.data.message is string
                    && request.resource.data.message.size() > 0
                    && request.resource.data.message.size() <= 2000
                    && request.resource.data.category in ["bug", "feature", "other", "praise"];
      allow read, update, delete: if false;
    }
```

The full file should look like:

```
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only read/write their own data
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }

    // Anyone (auth or anon) can submit feedback; nobody can read/update/delete
    match /feedback/{docId} {
      allow create: if request.resource.data.message is string
                    && request.resource.data.message.size() > 0
                    && request.resource.data.message.size() <= 2000
                    && request.resource.data.category in ["bug", "feature", "other", "praise"];
      allow read, update, delete: if false;
    }

    // Deny all other access
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

- [ ] **Step 2: Deploy the rules**

```bash
firebase deploy --only firestore:rules
```

Expected: "Deploy complete!" — note: this requires `firebase` CLI auth. If not logged in, the user will be prompted; if not installed, skip this step and ask the user to deploy manually before testing.

- [ ] **Step 3: Commit**

```bash
git add firestore.rules
git commit -m "feat: allow public feedback writes with size + category constraints"
```

---

## Task 12: Manual test pass + TEST_PLAN.md update + final verification

**Files:**
- Modify: `TEST_PLAN.md`

- [ ] **Step 1: Run the full test suite**

```bash
flutter test
```

Expected: all tests PASS, no regressions in existing test files.

- [ ] **Step 2: Run analyzer + formatter**

```bash
dart analyze && dart format --set-exit-if-changed .
```

Expected: no analyzer errors. If formatter modifies files, re-run `dart format .` and stage.

- [ ] **Step 3: Build for iOS (smoke test)**

```bash
flutter run -d 596FA2B9-8F2D-4E57-BEF5-29F2C3DB6A1B
```

Expected: app builds and launches without errors. Hot-restart-ready.

- [ ] **Step 4: Manual test — gating**

In the running simulator:
1. Wipe app state (uninstall + reinstall, or `flutter clean` + reinstall).
2. Sign in (or skip).
3. Create 1 piece → no dialog.
4. Create 2nd piece → no dialog.
5. Restart app (cold start, so session_count = 2).
6. Create 3rd piece → no dialog (first launch was today; 3-day gate not satisfied).

- [ ] **Step 5: Manual test — fast-forward + happy path**

Use a debug snippet (run via `flutter run` console or temporary code) to set `review_prompt_first_launch_date` to 4 days ago:

```dart
// Temporary: in main.dart, BEFORE the session counter block, add:
// await prefs.setString('review_prompt_first_launch_date',
//     DateTime.now().subtract(const Duration(days: 4)).toIso8601String());
```

Then:
1. Hot-restart.
2. Create another piece → soft-ask appears.
3. Tap "Yes, I love it!" → native review sheet appears (or doesn't on simulator — that's expected).
4. Pop back to album → save another piece → no dialog (cooldown active).

Remove the temporary snippet after.

- [ ] **Step 6: Manual test — feedback path**

1. Reset prefs again, fast-forward first_launch as in Step 5.
2. Create another piece → soft-ask appears.
3. Tap "Could be better" → /feedback opens.
4. Fill in message "test feedback from manual run" → tap Send.
5. Toast shows "Thanks — we read every message" → returned to album.
6. Open Firebase Console → Firestore → `feedback/` → confirm doc exists with all fields.

- [ ] **Step 7: Manual test — Settings entry + anonymous**

1. Sign out.
2. From Settings → tap "Send Feedback" → /feedback opens directly (no soft-ask).
3. Submit → check Firebase Console → confirm new doc with `uid: null`.

- [ ] **Step 8: Update TEST_PLAN.md**

Add to the changelog table at the top of `TEST_PLAN.md`:

```
| 2026-05-09 | In-app review prompt + feedback form |
```

Add a new test section near similar feature sections:

```markdown
## In-App Review Prompt + Feedback Form

### Gating
- Fresh install creates 1, 2 pieces → no prompt fires.
- After 3rd piece, before 3 days since install → no prompt fires.
- After 3rd piece + 3 days + 2 sessions → soft-ask appears on next save.
- After any prompt fires → 90-day cooldown enforced.

### Soft-ask paths
- "Yes, I love it!" → native review sheet (or silently no-op if iOS cap hit).
- "Could be better" → /feedback opens with form.
- Outside-tap dismiss → cooldown starts, no further action.

### Feedback form
- Send disabled until message non-empty.
- Successful submit → toast, pops back, doc lands in Firestore `feedback/`.
- Failed submit (airplane mode) → error toast, form stays open.
- Anonymous user submit → doc has `uid: null`.

### Settings entry
- Settings → "Send Feedback" → /feedback opens directly (no soft-ask).
```

- [ ] **Step 9: Final commit**

```bash
git add TEST_PLAN.md
git commit -m "docs: TEST_PLAN entries for review prompt + feedback"
```

- [ ] **Step 10: Verify branch state**

```bash
git log --oneline main..HEAD
```

Expected: ~12 commits on `feature/in-app-review-and-feedback` branch, each scoped to one task. Ready for PR.
