# AGENTS.md

This file provides guidance to coding agents working in this repository. `CLAUDE.md` imports it through an `@AGENTS.md` pointer — edit this file, keep the pointer as a pointer.

## Rules

- **DO NOT write TODOs, FIXMEs, or HACKs in code comments.** Track all TODOs in Claude memory files only.
- **Save every design iteration to `docs/design/<feature>/`.** Any time visual options are generated — logo studies, layout comparisons, colour or weight sheets, icon sizing — commit *every* round, not just the winner, before moving on. Save each as vector HTML (zoomable, and the path data stays readable) plus a PNG screenshot, and keep a README noting what each round changed, what was rejected, and why. Scratchpad files are session-scoped and vanish; rejected options are the most valuable part of the record for a later case study or blog post, and the reasoning behind a rejection is impossible to reconstruct afterwards. `docs/design/splash-logo/` is the reference example.

## Project Overview

Pottery Tracker is a photo-first mobile app for hobby potters to log and track their ceramic pieces. The full product requirements are in `pottery_tracker_prd.md`. `TEST_PLAN.md` is the project's test plan — strategy, unit/integration inventory, a regression catalog keyed to `fix:` commits, and a prioritized test-gap backlog; add a row there with every `fix:` commit rather than letting regressions go uncatalogued.

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
  tested, but its call site for the real database — the `setup:` callback in
  `AppDatabase.open(file, key)` — is not covered by any test, because that path needs a real
  SQLCipher-backed database. Do not remove or refactor that call away without verifying on a device.
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

### Schema migrations

`onUpgrade` in `lib/database/database.dart` creates every table from the *current* Dart definition,
so a step that creates a table already gets the columns added in later versions. An `addColumn` on
such a table must therefore be bounded on both sides, the way the clay `sort_order` and tag `color`
steps are; unbounded, the upgrade throws `duplicate column name` and the app cannot open at all.
When you bump `schemaVersion`, add a `test/database/fixtures/schema_v<previous>.sql` fixture:
`test/database/migration_test.dart` discovers every fixture, walks it to the current version and
compares the result against a fresh install, and fails if the fixture set is not exactly every
version below `schemaVersion`.

drift runs `onUpgrade` outside a transaction and writes the new `user_version` only after it
returns, and no step here is idempotent, so a migration that throws part-way cannot be resumed: the
work it already committed stays, the version does not move, and the next launch re-enters at the
same `from` and dies on whichever non-idempotent step had applied — the glaze backfill's `INSERT`
against a unique `name`, or an `addColumn`, which is a bare `ALTER TABLE ... ADD COLUMN`
(`createTable` is `IF NOT EXISTS` and survives). Recovery for a half-applied migration is tracked
outside this repo as `pt-migration-half-applied-recovery`.

### Local database key

The SQLCipher key is stored under options pinned in `EncryptionKeyService` (iOS
`first_unlock_this_device`, never synchronised; Android KeyStore with RSA-OAEP + AES-GCM) so it never
enters a phone backup. Consequences, all documented in `docs/local-database-key.md`:

- **Never change those options without a migration.** A key written under different options is
  unreadable to the next launch on Android and travels in backups again on iOS. The secure-storage
  marker `db_encryption_key_storage_version` is what says a key was stored under the current options;
  bump it and extend `hardenStoredKey` if they ever change.
- **Every launch goes through `LocalDatabaseBootstrap`**, which never creates a key while a database
  file exists — that would open an empty database over the user's pottery. A file with no key is a
  backup restore and gets `DatabaseRecoveryScreen` *before* the app runs.
- **Local-only users move phones with a transfer passphrase, on iOS only** (`TransferKeyBackup`, a
  second SQLCipher file in `Documents/` wrapping the key). Android opts out of backups *and*
  Android 12+ device transfer (`allowBackup="false"` plus `dataExtractionRules` excluding every
  domain — `allowBackup` alone does not stop device transfer), so the Settings section there says
  plainly that local-only pottery does not move; never show the passphrase on Android. It is a
  local store: `deleteLocalData` and both recovery discard paths delete it, and `deleteLocalData`
  also rekeys the emptied database so the passphrase in an old backup unwraps nothing new. Cloud
  users re-pull; their photo files are kept for the pull to reuse.

## no-mistakes test step: evidence-agent hang

After `flutter test` passes, the no-mistakes test step dispatches a second evidence-gathering
agent that writes an ad-hoc widget test driving real screens against in-memory Drift, and this
repo's screens make that agent hang until `test_agent_timeout` (30m) fails the step. Symptom: the
run stalls at the test step even though the gate log already shows `All tests passed!`. Remedy:
re-run at the same head with `no-mistakes run --skip=test` once the gate log proves the suite
green, and quote that log line in the PR body.

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

A run decides from its own outcome, never from the latched `SyncState.status` — the status is what the *previous* run left behind, so reading it strands stale errors. `_pushQueue` in `lib/providers/sync_provider.dart` owns the rationale and the limits of what a drain's "backed up" claim covers. `SyncState.copyWith` drops `errorMessage` whenever it is not passed — that is how a healthy state stops carrying a dead failure's caption, and several callers depend on it. The same rule, for the same reason, governs the read-only lock below.

Piece-row and photo writes from screens go through `PieceWriter` (`lib/services/piece_writer.dart`), whose tests pin the enqueue for each operation; the remaining direct piece and photo DAO writes from screens are the glaze and tag setters in `piece_detail_screen.dart` (`setGlazesForPiece` / `setTagsForPiece`, each followed by a hand-enqueued `afterPieceGlazesWrite` / `afterPieceTagsWrite` + `afterPieceWrite` pair) and the album swipe-to-archive in `album_grid.dart`. Material rename/delete in the Manage screens goes straight to `materials_dao`, which also rewrites the denormalized `pieces.glazes` / `pieces.tags` columns.

No account may push another account's data. The *next* account's first sync calls `pushAllLocal`, so
whatever is on the device gets uploaded into whichever cloud tree is signed in. Captain decisions
(2026-08-18/19) settle how that is prevented, and they differ by how the session ended:

- **Explicit sign-out is destructive.** `SyncNotifier.signOutAndWipeLocalData` ends the session and
  then deletes the local database, the photo and cache files, the sync queue and every pull
  watermark. A new local store must be added to `SyncService.deleteLocalData` or it becomes a
  cross-account leak, and the confirmation must keep saying plainly that local data is deleted.
- **Involuntary session loss destroys nothing.** `AuthNotifier._init` signs out when `reload()`
  fails or times out — which includes an ordinary offline launch — so it wipes nothing and relies on
  the `localDataOwnerUid` stamp instead.
- **A locked device is locked read-only at the router** (`deviceLockedProvider` → `/device-locked`),
  not screen by screen, so a refused account never reaches the album, the create flow, the piece
  editor or the material screens and cannot write at all. `deviceLockReasonProvider` says which of
  two situations it is, and they are opposites — the screen picks its words and its actions from it:
  - **Foreign pottery.** Exactly two ways out: the owner signs back in, or the user erases the
    device deliberately. Leaving via the lock screen ends the session **without** wiping — none of
    that pottery belongs to the account leaving.
  - **An owed wipe** the user confirmed and did not get. It is their own library, so leaving is not
    offered; finishing the erase is the only way out. The lock reflects an *owed* wipe, never one in
    flight: locking during a wipe redirects away from the screen that owes the user its result.

  Every input to the lock is persisted (`localDataOwnerUid`, `localDataContested`,
  `pendingLocalDataWipe`) and seeded in `main()` before `runApp`, never derived from `SyncStatus` —
  status is transient, and each transition that released the lock reopened the hole.

  `localDataContested` is one **device-level** flag recording that somebody was refused here, and it
  is deliberate and required: a session-less launch is how the owner opens the app offline *and* how
  a refused account returns after force-quitting the lock screen, so nothing derived from the
  session can tell them apart. It is written by `deviceRefusalRecorderProvider`, where the lock is
  decided — not on the sync path, which the refusal never has to reach.

  It is **not** the per-row attribution design that preceded all this, which let a refused account
  write and then tracked which rows it had touched: queue uid stamps, a foreign-row set, a withheld
  count, reconciliation, deletion skipping. Do not reintroduce any of those. Over four review rounds
  they produced two paths that destroyed the owner's pottery permanently and one that reported
  "All data backed up" while pieces were excluded. Making the device unwritable is the whole point —
  there is then nothing to attribute.
- **An owed wipe is only ever retried where the user expects it** — at an auth transition; from
  `DeviceLockedScreen` via `retryOwedWipe`, both when it opens on the owed-wipe reason (the flag
  locks the router before the shell can mount, so the auth transition never runs) and when
  `staleSyncBlockingWipeProvider` reports that the sync which blocked the last attempt has ended
  (a signal that lands mid-attempt is kept in one coalesced flag and paid once that attempt
  settles); or from the confirmed `eraseLocalDataNow`. Never from `syncNow`, the debounced
  `_pushQueue`, or the sync's own completion: a delete on the push path fires 500ms after any
  edit and would destroy the *current* account's work.
- **A destructive action the user has confirmed never ends in silence.** `eraseLocalDataNow` and
  `deleteAllData` both return a result the caller reports.

`test/providers/account_switch_test.dart` is the end-to-end guard, against a real Drift database.

## Design Constraints

- All features must work fully offline; sync is additive
- English only for V1 but use Flutter intl (no hardcoded strings)
- V1 is free — no paywalls, and no donation link or tip jar (the Ko-fi link was removed in 2026-08 by captain ruling; do not reintroduce one)
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
