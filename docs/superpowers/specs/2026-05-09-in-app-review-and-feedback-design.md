# In-App Review Prompt + Feedback Form

**Date:** 2026-05-09
**Status:** Approved
**Author:** Albert Xu (with Claude)

## Problem

The Pottery Tracker app currently has 2 ratings on the App Store, both 1-star. There is no in-app mechanism to (a) ask happy users for a review, or (b) capture private feedback from unhappy users before they leave a public bad review. The result is a rating distribution skewed toward dissatisfied users — happy users have no easy path to leave a review, and unhappy users have no path to vent privately.

## Goals

1. Ask engaged users for a review at a "happy moment" — only after they've demonstrated retention.
2. Filter unhappy users out of the review flow into a private in-app feedback channel.
3. Respect platform constraints (iOS allows ~3 review prompts per user per 365 days).
4. Allow users to send feedback proactively at any time from Settings.

## Non-Goals

- Email notifications when feedback is submitted (deferred — user will check Firebase Console manually for v1).
- Screenshot attachment in the feedback form.
- Cloud Function or Firebase Trigger Email setup.
- Anonymous user gating — anonymous users can submit feedback.
- Custom rating UI inside the app — we always defer to the native iOS/Android review sheet.

## High-Level Flow

```
Piece save completes
       ↓
ReviewPromptService.maybePromptAfterPieceSave()
       ↓ (gates pass)
Soft-ask Cupertino dialog: "Enjoying Pottery Tracker?"
       ├─ "Yes, I love it!"  → InAppReview.requestReview() (native sheet)
       ├─ "Could be better"  → push /feedback route → form → write to Firestore
       └─ Dismiss            → no action; cooldown clock starts
```

## Gating Logic

A prompt fires only when **all** of the following are true:

| Gate | Condition |
|---|---|
| Piece count | `piecesDao.count() >= 3` |
| Sessions | `session_count >= 2` (cold app starts) |
| Days since install | `now - first_launch_date >= 3 days` |
| Cooldown | `last_prompted_at` is null OR `now - last_prompted_at >= 90 days` |

For existing users on upgrade: `first_launch_date` is set on first launch of the new version, so they get a 3-day warm-up before any prompt.

`last_prompted_at` is set to "now" the moment the soft-ask dialog is shown — atomic with `showCupertinoDialog`. This means whatever the user does next (Yes / No / Dismiss / submit form / fail to submit) does not change `last_prompted_at`, and the 90-day cooldown applies uniformly. Rationale: simpler, and avoids the edge case where a user dismisses then immediately re-triggers by saving another piece. iOS's per-app per-year cap is the safety backstop for the "Yes" path.

The Settings → "Send feedback" path does **not** touch `last_prompted_at` — it's a separate entry point unrelated to the soft-ask cooldown.

## Architecture

### New files

| File | Responsibility |
|---|---|
| `lib/services/review_prompt_service.dart` | Owns gating logic. Reads/writes SharedPreferences. Calls `InAppReview.requestReview()`. Exposes `maybePromptAfterPieceSave(BuildContext)`. Takes `DateTime Function() now` in constructor for testability. |
| `lib/services/feedback_service.dart` | Builds and writes feedback documents to Firestore `feedback/{autoId}`. Captures app version, platform, OS, device model, locale via `package_info_plus` + `device_info_plus`. |
| `lib/providers/review_prompt_provider.dart` | Riverpod provider exposing `ReviewPromptService` singleton. |
| `lib/providers/feedback_provider.dart` | Riverpod provider exposing `FeedbackService` singleton. |
| `lib/features/feedback/screens/feedback_screen.dart` | Form UI: category dropdown, message field, optional reply email, Send + Cancel buttons. |
| `lib/features/feedback/widgets/enjoyment_dialog.dart` | Cupertino soft-ask dialog with "Yes, I love it!" and "Could be better" actions. |

### Modified files

| File | Change |
|---|---|
| `lib/features/create_piece/screens/create_piece_screen.dart` (and any other piece-save call sites) | Call `ref.read(reviewPromptServiceProvider).maybePromptAfterPieceSave(context)` after a successful save. |
| `lib/features/settings/screens/settings_screen.dart` | Add "Send feedback" row that pushes `/feedback`. |
| `lib/router/app_router.dart` | Register `/feedback` route. |
| `lib/main.dart` | Increment `review_prompt_session_count` on cold start. Set `review_prompt_first_launch_date` if not yet set. |
| `pubspec.yaml` | Add `in_app_review`, `package_info_plus`, `device_info_plus`. |
| `firestore.rules` | Allow create on `feedback/{docId}` for any user (auth or anon) with valid message size; deny read/update/delete. |
| `TEST_PLAN.md` | Add manual test cases + changelog entry. |

### SharedPreferences keys

All under `review_prompt_*` prefix:

- `review_prompt_first_launch_date` — ISO 8601 string. Set on first launch of the new app version.
- `review_prompt_session_count` — int. Incremented once per cold app start (in `main()` before `runApp()`).
- `review_prompt_last_prompted_at` — ISO 8601 string. Set whenever the soft-ask dialog is shown.
- `review_prompt_completed` — bool. Set true if user tapped "Yes, I love it!" or submitted feedback. Reserved for future logic; v1 does not branch on this flag (cooldown is the only re-prompt rule).

## Feedback Form

### UI (Cupertino-styled to match existing dialogs)

- **Category dropdown** — `Bug` / `Feature request` / `Other` / `Praise`. Default: `Other`.
- **Message** — multiline text field, ~5 lines visible, required, max 2000 chars.
- **Reply email** — single-line text field, optional. Pre-filled with `FirebaseAuth.currentUser?.email` if signed in. Helper text: "Optional — only if you want a reply."
- **Send button** — disabled until message is non-empty.
- **Cancel button** — pops the route.

On successful send: show toast "Thanks — we read every message" and pop the route.
On send failure: show toast "Couldn't send — try again later" and leave the form open. Do not update `last_prompted_at` so the user can retry from the soft-ask flow.

### Firestore schema — `feedback/{autoId}`

```
{
  uid:           string | null,        // Firebase auth uid, null for anonymous
  category:      "bug" | "feature" | "other" | "praise",
  message:       string,               // 1-2000 chars
  replyEmail:    string | null,
  appVersion:    string,               // e.g. "1.1.0+5"
  platform:      "ios" | "android",
  osVersion:     string,               // e.g. "iOS 26.2.1"
  deviceModel:   string,               // e.g. "iPhone15,2"
  locale:        string,               // e.g. "en_US"
  createdAt:     Timestamp              // serverTimestamp
}
```

### Firestore rules

```
match /feedback/{docId} {
  allow create: if request.resource.data.message is string
                && request.resource.data.message.size() > 0
                && request.resource.data.message.size() <= 2000
                && request.resource.data.category in ["bug", "feature", "other", "praise"];
  allow read, update, delete: if false;
}
```

No `auth != null` gate — anonymous users can submit feedback.

## Failure Modes

| Failure | Handling |
|---|---|
| `InAppReview.isAvailable()` returns false (jailbroken, restricted account, simulator) | Silently skip the native prompt. Set `last_prompted_at` so we don't retry every save. |
| Firestore write fails (offline, permission, etc.) | Show error toast. Form stays open; user can retry. `last_prompted_at` was already set when the soft-ask appeared, so no cooldown change. |
| `package_info_plus` / `device_info_plus` throws | Catch and substitute "unknown" for the affected field. Do not block the send. |
| User dismisses soft-ask via outside-tap or back gesture | Treat same as dismiss — set `last_prompted_at`, no completed flag. |

## Testing

### Unit tests

`test/services/review_prompt_service_test.dart`:

- Returns no-prompt when piece count < 3.
- Returns no-prompt when session count < 2.
- Returns no-prompt when first launch < 3 days ago.
- Returns no-prompt when last_prompted_at < 90 days ago.
- Prompts when all gates pass.
- Sets `last_prompted_at` after every dismiss path (Yes / No / Dismiss).
- `InAppReview.isAvailable() == false` → silently skips and sets `last_prompted_at`.

Use `SharedPreferences.setMockInitialValues({})` and inject a fake clock via constructor (`DateTime Function() now = DateTime.now`).

`test/services/feedback_service_test.dart`:

- Builds doc with required fields populated correctly.
- Anonymous user produces `uid: null`.
- Sets serverTimestamp on `createdAt`.
- Substitutes "unknown" when device-info plugin throws.

Mock Firestore via `fake_cloud_firestore` package or the existing `mock_providers.dart` pattern.

### Widget tests

`test/features/feedback/feedback_screen_test.dart`:

- Send button disabled until message is non-empty.
- Tapping Send invokes `FeedbackService.submit` with form values.
- Success toast and route pop on success.
- Error toast on failure; route stays open.

`test/features/feedback/enjoyment_dialog_test.dart`:

- "Yes, I love it!" calls `InAppReview.requestReview()`.
- "Could be better" navigates to `/feedback`.
- Dismiss/outside-tap calls neither but updates `last_prompted_at`.

### Manual test plan

To be added to `TEST_PLAN.md`:

1. **Fresh install gating:** Install fresh → create 1, 2 pieces → no prompt. Restart app → create 3rd piece → still no prompt (< 3 days since install).
2. **3-day fast-forward:** Manipulate `review_prompt_first_launch_date` to 4 days ago → save another piece → soft-ask appears.
3. **Yes path:** Tap "Yes, I love it!" → native review sheet appears (or doesn't if iOS has hit its 3/year cap — both are correct).
4. **Feedback path:** Tap "Could be better" → /feedback opens → fill out and send → success toast → returned to album.
5. **Cooldown:** After step 4, save another piece → no prompt.
6. **90-day fast-forward:** Manipulate `review_prompt_last_prompted_at` to 91 days ago → save piece → soft-ask appears again.
7. **Settings entry:** Settings → Send feedback → /feedback opens directly (no soft-ask).
8. **Anonymous user:** Sign out (or use "Skip for now") → submit feedback → check Firebase Console for doc with `uid: null`.
9. **Offline send:** Airplane mode → submit feedback → error toast, form stays open.

## Out of Scope (Future Work)

- Email notifications on new feedback (requires Blaze plan + Cloud Function or Trigger Email extension).
- Screenshot attachment in feedback.
- Per-category routing (e.g., bugs → GitHub issue, feature requests → roadmap).
- Branching cooldown by `completed` flag (e.g., "never re-prompt users who already gave 5 stars").
- Analytics on prompt fire / dismiss / yes / feedback rates (could log via existing `analytics_provider`).

## Dependencies

- `in_app_review` — latest stable
- `package_info_plus` — latest stable
- `device_info_plus` — latest stable
- (existing) `cloud_firestore`, `firebase_auth`, `shared_preferences`, `flutter_riverpod`
