# AGENTS.md

This file provides guidance to coding agents working in this repository. `CLAUDE.md` is a symlink to it — edit this file, never replace the symlink with a second copy.

## Rules

- **DO NOT write TODOs, FIXMEs, or HACKs in code comments.** Track all TODOs in Claude memory files only.
- **Save every design iteration to `docs/design/<feature>/`.** Any time visual options are generated — logo studies, layout comparisons, colour or weight sheets, icon sizing — commit *every* round, not just the winner, before moving on. Save each as vector HTML (zoomable, and the path data stays readable) plus a PNG screenshot, and keep a README noting what each round changed, what was rejected, and why. Scratchpad files are session-scoped and vanish; rejected options are the most valuable part of the record for a later case study or blog post, and the reasoning behind a rejection is impossible to reconstruct afterwards. `docs/design/splash-logo/` is the reference example.

## Project Overview

Pottery Tracker is a photo-first mobile app for hobby potters to log and track their ceramic pieces. The full product requirements are in `pottery_tracker_prd.md`.

## Current Status

Local-only (Phase 1) and Firebase sync (Phase 2) are both shipped. Firebase Auth (Google + Apple), Firestore, Cloud Storage, and App Check are live; the local DB is encrypted with SQLCipher.

### Known decisions:
- Cover photo / thumbnail selection UI removed — will be reworked later. Currently auto-sets most recent photo as cover.
- Image pipeline uses in-memory compression (`compressWithList`) with raw-bytes fallback for reliability
- Camera crashes on iOS simulator — use Photo Library for testing

### Android release

Android builds and produces a Play-shaped `.aab`, but has never run on a device — the encrypted-DB
path in `lib/database/database.dart` is the highest-risk unverified item. Everything a human has to
do in the Firebase or Play console is in `docs/android-release.md`; keep that file current rather
than re-deriving it.

- `sqlcipher_flutter_libs` must stay at **>= 0.6.8**. Below that the package sets `compileSdkVersion 28`
  and `flutter build apk --release` fails on `android:attr/lStar`, and its `libsqlcipher.so` is
  4 KB-aligned, which Play rejects. 0.6.8 is also the last release before the `0.7.0+eol` tombstone;
  the real destination is `package:sqlite3` 3.x with SQLCipher built in.
- Release signing reads `android/key.properties` (gitignored, never committed). With no such file the
  build falls back to the Android **debug** key so a clean checkout still builds — pass
  `-PrequireReleaseSigning=true` for anything destined for Play and the build fails instead.
- The SQLCipher guard (`configureSqlCipher` in `lib/database/sqlcipher_guard.dart`) is what stops the
  app writing a plaintext database when SQLCipher is not the library that loaded. Its own behaviour is
  tested, but its single call site — the `setup:` callback in `AppDatabase.open()` — is not covered by
  any test, because that path needs a real SQLCipher-backed database. Do not remove or refactor that
  call away without verifying on a device.
- Major dependency upgrades (Firebase 3->4/5->6, `go_router`, `google_sign_in`, `sign_in_with_apple`,
  `flutter_secure_storage`, Riverpod 3, `sqlite3` 3) are deliberately frozen until Android is on a
  Play track, so an Android regression is never confounded with an upgrade. `drift` is already at its
  ceiling (2.31.0) because >= 2.32.0 requires `sqlite3` 3.x, and `intl` is pinned by
  `flutter_localizations` inside the Flutter SDK — neither is an independent upgrade.
- `path_provider_foundation` is held at exactly **2.5.1** as an Apple-side workaround, not a design
  choice: 2.6.0 reimplements the plugin on `package:objective_c`, which drags in Dart's build-hooks /
  native-assets toolchain (`hooks`, `code_assets`, `native_toolchain_c`). Lifting the pin can only be
  validated by an iOS build, so it stays until the `package:sqlite3` 3.x migration above, which needs
  that toolchain anyway.

## Common Commands

```bash
# Generate Drift database code
dart run build_runner build --delete-conflicting-outputs

# Generate localization files
flutter gen-l10n

# Cloud Function typecheck + tests (feedback sanitiser)
cd functions && npm ci && npm test
```

## Architecture

### Offline-First + Cloud Sync

All data lives in local SQLite first. Writes never block on the network: every DAO write enqueues an entry via `SyncTrigger`, and `SyncNotifier` drains the queue on a short debounce, on sign-in, and on explicit `syncNow()`. Failed operations retry with exponential backoff and are re-attempted on the next full sync, so there is no connectivity listener — offline is just a failed attempt that stays queued. Conflict resolution is last-write-wins based on `updatedAt`.

Every write path must go through `SyncTrigger`; a DAO write without one silently never reaches the cloud.

No account may push another account's data. The *next* account's first sync calls `pushAllLocal`, so
whatever is on the device gets uploaded into whichever cloud tree is signed in — three captain
decisions (2026-08-18) settle how that is prevented, and they differ by how the session ended:

- **Explicit sign-out is destructive.** `SyncNotifier.signOutAndWipeLocalData` ends the session and
  then deletes the local database, the photo and cache files, the sync queue and every pull
  watermark. A new local store must be added to `SyncService.deleteLocalData` or it becomes a
  cross-account leak, and the confirmation must keep saying plainly that local data is deleted.
- **Involuntary session loss destroys nothing.** `AuthNotifier._init` signs out when `reload()`
  fails or times out — which includes an ordinary offline launch — so it wipes nothing and relies on
  the `localDataOwnerUid` stamp instead: every push path refuses while the stamp names someone else
  (`SyncStatus.blocked` with `SyncBlockedReason.foreignLocalData`). The way out is signing back in
  as the owner, or an explicit erase.
- **An owed wipe is only ever retried where the user expects it** — at an auth transition, or from
  the confirmed `eraseLocalDataNow`. Never from `syncNow` or the debounced `_pushQueue`: a delete on
  the push path fires 500ms after any edit and would destroy the *current* account's work.

`test/providers/account_switch_test.dart` is the end-to-end guard for all three, against a real
Drift database.

## Design Constraints

- All features must work fully offline; sync is additive
- English only for V1 but use Flutter intl (no hardcoded strings)
- V1 is free with optional donation — no paywalls
- Firebase Spark (free) plan: 1GB Firestore, 5GB Cloud Storage, 50K reads/day, 20K writes/day
- Accessibility: screen reader support, system font scaling, minimum touch targets (48dp Android / 44pt iOS)
- Portrait only, iPhone and iPad — landscape is never allowed anywhere. There is deliberately no `SystemChrome.setPreferredOrientations` call: it would be a no-op against the declarations below, so do not add one, and do not build landscape layouts. Two declaration sites must stay in agreement:
  - `ios/Runner/Info.plist` — `UISupportedInterfaceOrientations` is portrait alone; the `~ipad` variant also allows `PortraitUpsideDown`. `UIRequiresFullScreen` is load-bearing, not cosmetic: `TARGETED_DEVICE_FAMILY` includes iPad, and an iPad app that supports multitasking must support every orientation, so without opting out of multitasking iOS ignores the `~ipad` restriction and rotates anyway. Accepted cost: no Split View / Slide Over.
  - `android/app/src/main/AndroidManifest.xml` — `android:screenOrientation="userPortrait"` on `MainActivity`, which allows both portrait directions on phones too since the manifest has no phone/tablet variant like iOS's `~ipad`; `android:resizeableActivity="false"`, giving up split-screen/multi-window in the same tradeoff as `UIRequiresFullScreen`; and the application-level `android.window.PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY` property, without which Android 16 large screens override the lock (the platform drops that opt-out at targetSdk 37).

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
