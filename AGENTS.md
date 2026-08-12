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

## Common Commands

```bash
# Generate Drift database code
dart run build_runner build --delete-conflicting-outputs

# Generate localization files
flutter gen-l10n
```

## Architecture

### Offline-First + Cloud Sync

All data lives in local SQLite first. Writes never block on the network: every DAO write enqueues an entry via `SyncTrigger`, and `SyncNotifier` drains the queue on a short debounce, on sign-in, and on explicit `syncNow()`. Failed operations retry with exponential backoff and are re-attempted on the next full sync, so there is no connectivity listener — offline is just a failed attempt that stays queued. Conflict resolution is last-write-wins based on `updatedAt`.

Every write path must go through `SyncTrigger`; a DAO write without one silently never reaches the cloud.

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
