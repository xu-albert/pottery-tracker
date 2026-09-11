# Pottery Tracker — Test Plan

This document is the project's single test plan. It combines a comprehensive testing
strategy (§1–5, §7–12) with the manual feature/regression catalog that predates it (§6,
carried forward unchanged in substance). Update it whenever features are added or
changed, and whenever a bug fix lands (see §4's rule).

Related docs this plan links to rather than duplicates: `AGENTS.md` (offline-first sync
architecture, account-switch/lock design, Android release risk), `docs/android-release.md`
(manual Play/Firebase console steps), `testing/searchable-pickers.md` (a standalone manual
+ agent script for the material pickers, still current), `firestore.rules` / `storage.rules`
(the authoritative access-control source).

**Audit note (2026-09-02):** the previous version of this file was a manual/feature QA
checklist only (its old §1–12, now folded into §6 below) plus one automated-tests list
(old §10, now folded into §2). It had no test-pyramid statement, no integration/contract
section, no regression catalog, no performance/load section, no security/privacy section
beyond a two-line accessibility stub, no release checklist, and no single "run everything"
section — those are new here (§1, §3, §4, §5, §7, §8, §9, §10, §12). §11 (Gaps) is new and
supersedes the old inline `**TODO:**` markers in §6, which are intentionally left in place
since they're feature backlog, not test backlog.

---

## 1. Test Strategy & the Test Pyramid

Pottery Tracker is a single-developer, offline-first Flutter app with a thin Cloud
Functions backend. The pyramid is deliberately bottom-heavy: Drift/Riverpod logic is cheap
to unit-test in Dart's VM test runner (no simulator needed), so most of the suite sits
there (§2.1 counts the cases file by file); widget tests cover the handful of screens
with real branching logic; there are zero automated end-to-end tests (§5) because the two
things that would require — Camera and PHPicker multi-select — do not work in the iOS
Simulator at all (`AGENTS.md`, `TEST_PLAN.md` §6.4), so E2E coverage of the photo pipeline
is manual-only by necessity, not by neglect.

```
        ▲  Manual/Exploratory (§6) — full app, real device, pre-release
       ╱ ╲    ~40 scripted scenarios, iOS Simulator + physical device
      ╱   ╲
     ╱  E2E ╲  (§5) — none automated; camera/multi-picker require a real device
    ╱───────╲
   ╱  Widget  ╲ (§2.2) — 16 files, screens/components with branching UI logic
  ╱─────────────╲
 ╱   Unit / DAO   ╲ (§2.1) — 27 files: providers, services, DAOs, pure helpers
╱───────────────────╲
```

Cloud Functions (`functions/`) has its own small pyramid: `sanitize.test.js` unit-tests the
feedback sanitiser in isolation, `notify_discord.test.js` contract-tests the Discord webhook
shape against a mocked `fetch` (§3.1) — no emulator, no live Firestore trigger test exists
(§11).

**What "test" means here, precisely:**
- *Unit*: pure functions and single classes (a DAO, a provider's reducer, `sanitize.ts`)
  against an in-memory or mocked dependency, no widget tree.
- *Widget*: `flutter_test`'s `testWidgets` pumping a real widget subtree, mocked
  providers/services underneath.
- *Integration/contract* (§3): a real Drift/SQLCipher database, a real (temp-dir) file
  system, or a fake-but-schema-faithful Firebase SDK (`firebase_storage_mocks`, hand-rolled
  fakes in `test/helpers/firebase_mocks.dart`) — never a live Firebase project.
- *Manual* (§6): a human, an app build, and this document's checklists.

**Rule for new code:** a new DAO method, provider, or service function gets a unit test in
the same PR. A new screen or stateful widget gets at least a smoke widget test. A bug fix
gets a regression case (§4). Nothing here requires 100% coverage — there is no coverage gate
in CI (§10) — but every write path must be reachable from a test the way `AGENTS.md`
requires every write path to reach `SyncTrigger`.

---

## 2. Unit Tests

### 2.1 What exists

Convention: `test/<mirror-of-lib-path>/<subject>_test.dart`, one `test_test.dart` per
`lib/` file it exercises (not strictly 1:1 — a few files test a provider plus its
dependent notifier together). Run with `flutter test` or `flutter test path/to/file.dart`
for one file; `flutter test --plain-name "some test name"` for one case.

| File | Subject | Approx. cases |
|---|---|---|
| `test/android/data_extraction_rules_test.dart` | Android backup configuration as the backup agent parses it: `allowBackup` off, every domain excluded from both cloud backup and Android 12+ device transfer, nothing included | 2 |
| `test/database/materials_dao_junction_test.dart` | Clay/Glaze/Tag junction-table DAOs | 15 |
| `test/database/photos_dao_test.dart` | `PhotosDao` sort ordering, `getNextSortOrder`, batch reorder, per-piece delete scoping | 8 |
| `test/database/pieces_dao_test.dart` | `PiecesDao` archived filter, search matching, stream re-emission, CRUD, `getUntitledPieceTitles` | 12 |
| `test/database/sqlcipher_guard_test.dart` | `assertSqlCipherBacksSqlite3` (see §11 gap on its call site) | 18 |
| `test/database/local_database_bootstrap_test.dart` | Launch decision table (first launch / reinstall / update / restore / key mismatch), the three recovery paths, a process killed between the hardening rewrite's delete and add, a rotation that died after its copy landed (the copy is probed on key mismatch), a pre-unlock iOS launch (fails, never recovery), an Android key this device cannot decrypt (→ recovery) versus any other read failure (→ launch failure), and an erase owed on the old phone settled by every recovery exit, against a real Drift file with a SQLCipher stand-in (`test/helpers/fake_sqlcipher.dart`) | 27 |
| `test/database/transfer_key_backup_test.dart` | Passphrase-wrapped key file: round-trip, wrong passphrase → `WrongTransferPassphraseException`, atomic replace (a failed change keeps the previous backup), floor, no half-written file, a refused write never reports the key it was binding, the production keyer refuses without SQLCipher, `isNotADatabase` | 18 |
| `test/database/app_database_rekey_test.dart` | `AppDatabase.rekey`: a failed `PRAGMA rekey` is reported as `SqlCipherKeyingException` with the key redacted; the statement is quoted as given | 2 |
| `test/database/migration_test.dart` | The real `MigrationStrategy` walked from every historical schema version (discovered from the checked-in DDL in `test/database/fixtures/`, with a case failing if that set is not exactly 1 to `schemaVersion - 1`) to the current one: each upgrade completes and lands on exactly a fresh install's tables and columns, and the migrated database is writable through the DAOs; a version 1 piece survives with its clay and glaze text backfilled into the libraries and its clays numbered alphabetically | 11 |
| `test/models/display_date_test.dart` | `resolveDisplayDate` precedence: explicit date, then newest photo, then `createdAt` | 4 |
| `test/models/untitled_title_test.dart` | `isUntitledTitle` and `nextUntitledTitle` gap-filling numbering | 5 |
| `test/providers/account_deletion_record_test.dart` | Local record of a pending account deletion | 3 |
| `test/providers/account_switch_test.dart` | End-to-end account-switch/lock/wipe state machine, against a real Drift DB (`AGENTS.md`'s "end-to-end guard"), including what each partial wipe is reported as — photos left behind, and a key that could not be replaced — which is never "nothing was deleted" | 49 |
| `test/providers/auth_provider_test.dart` | `AuthState` transitions | 7 |
| `test/providers/sync_provider_test.dart` | `SyncState.copyWith` and notifier plumbing | 42 |
| `test/providers/sync_queue_durability_test.dart` | Real Drift + `PieceWriter` + persisted queue: a first sign-in retires its 36-entry bulk-upload snapshot without individually re-uploading photos, but sends queued tombstones — which no bulk upload of existing rows delivers — before it pulls, and keeps one whose push failed; edits during incremental/full-sync pull or upload retry survive and receive an owed drain; an edit merged into the entry being pushed is not acknowledged by that push; an edit during a drain receives a follow-up; exhausted pushes stay queued without a hot retry loop | 10 |
| `test/router/app_router_test.dart` | GoRouter redirect logic (device-lock gate, auth gate) | 2 |
| `test/services/encryption_key_service_test.dart` | Pinned secure-storage options (iOS `first_unlock_this_device`, Android OAEP/GCM) at the plugin call boundary; key generation; legacy→hardened migration with a migrating copy on disk throughout (crash between delete and add), read-back, nothing ever written back under `unlocked`, `KeyStorageException` only when item and copy are both gone; iOS null confirmed against protected-data availability (`KeyStoreUnavailableException`); Android `AEADBadTagException` reads as no key, every other failure propagates; fake platform in `test/helpers/fake_secure_storage.dart` | 38 |
| `test/services/feedback_service_test.dart` | Feedback Firestore write path | 4 |
| `test/services/image_service_test.dart` | Compression + raw-bytes fallback | 4 |
| `test/services/material_writer_test.dart` | Clay/glaze/tag create-and-select | 3 |
| `test/services/piece_writer_test.dart` | `PieceWriter` piece-row and photo writes against a real Drift DB, each pinned to its `SyncTrigger` enqueue (`AGENTS.md`'s "every write path" rule for screens) | 17 |
| `test/services/review_prompt_service_test.dart` | In-app-review gating (§6.12 mirrors this manually) | 9 |
| `test/services/sync_queue_entry_test.dart` | `SyncQueueEntry` (de)serialization | 14 |
| `test/services/sync_queue_test.dart` | Queue enqueue/drain/backoff | 9 |
| `test/services/sync_service_test.dart` | Push/pull, `pushAllLocal`, `deleteLocalData` (§11 gap: new local stores must be added here) including the key rotation at erase: `PRAGMA rekey` then store, and every way it can end with the old key still on the file — an unreadable key store, a rekey the database refuses, a key-back after a rejected store whether or not the key-back worked — reported as such, only once the photos, watermarks and ownership stamp are gone, and reporting a transfer backup that would not delete the same way — with the rotation's cause alongside it when both failed, and on its own even when the rotation worked, because that file is what Settings reads to claim a passphrase is set | 40 |
| `test/services/sync_trigger_test.dart` | DAO-write → queue-enqueue wiring (`AGENTS.md`'s "every write path" rule) | 13 |
| `test/widgets/vase_logo_test.dart` | `buildVasePath` pure path geometry | 5 |

### 2.2 Widget tests

| File | Subject |
|---|---|
| `test/features/album/album_screen_test.dart` | Loading/empty/error/data states |
| `test/features/album/widgets/album_grid_test.dart` | Active list + swipe-archive + undo; archive grid |
| `test/features/album/widgets/archive_thumbnail_test.dart` | Title overlay rendering |
| `test/features/album/widgets/empty_state_test.dart` | Illustration + message |
| `test/features/album/widgets/filter_chips_test.dart` | Active/Archive chip selection |
| `test/features/auth/device_locked_screen_test.dart` | Foreign-pottery vs. owed-wipe copy and actions (mirrors §6.1's "Device Locked" checklist), including the words each partial erase gets: photos left behind, and an erase whose key could not be replaced |
| `test/features/feedback/enjoyment_dialog_test.dart` | Soft-ask dialog paths |
| `test/features/feedback/feedback_screen_test.dart` | Form validation, submit states |
| `test/features/recovery/database_recovery_screen_test.dart` | Pre-app recovery screen: copy per cause, user class and platform (Android is never offered the iOS-only transfer passphrase), passphrase unlock (right/wrong/mismatched key), confirmed re-download and start-fresh, failure reported |
| `test/features/settings/settings_account_test.dart` | Sign-out/erase confirmation flow, including the words each partial outcome gets: a wipe that deleted nothing, one that left photo files, and one that erased everything but could not secure the device |
| `test/features/settings/settings_screen_test.dart` | Materials section, title |
| `test/features/settings/settings_support_section_test.dart` | Support section offers feedback only: no donation link, tip jar, or outside page (Ko-fi removed app-wide, 2026-08-18 ruling) |
| `test/features/settings/transfer_passphrase_sheet_test.dart` | Set/change/remove transfer passphrase: validation, file written with this device's key, flag and toasts |
| `test/widgets/splash_overlay_test.dart` | Splash animation completion gating |
| `test/widgets/stage_badge_test.dart` | Per-stage label text, tint and text colour (one case per `PieceStage`) |
| `test/widgets/tag_chip_test.dart` | Hash prefix, custom colour, stable palette pick for uncoloured tags, width cap |

### 2.3 What's missing

See §11 for the full prioritized list. Highlights: no test for `configureSqlCipher`'s call
site in `AppDatabase.open()` (§11-P0); no widget tests for the piece-detail screen,
manage-clays/glazes/tags screens, or the photo-reorder screen — all pure-checklist manual
coverage today (§6.5, §6.7).

### 2.4 How to run

```bash
flutter test                                    # whole Dart/Flutter suite (~40s)
flutter test test/services/sync_service_test.dart   # one file
flutter test --plain-name "pushAllLocal"        # one case by name, any file
flutter test --coverage                         # writes coverage/lcov.info (not gated in CI, see §10)
```

---

## 3. Integration & Contract Tests

Pottery Tracker has no live network calls in its own test run — everything below is
mocked or faked in-process. There is no Firebase emulator suite wired up (§11).

| Boundary | Real in tests? | How | Where |
|---|---|---|---|
| SQLCipher/Drift database | Yes — real Drift + `sqlite3` against a temp file, keyed with a real (test) passphrase, but plain `sqlite3` stands in for SQLCipher (`test/helpers/fake_sqlcipher.dart`): `PRAGMA key`/`rekey` are pinned as statements, never as encryption | `NativeDatabase` in a temp dir, torn down per test | `account_switch_test.dart`, `materials_dao_junction_test.dart`, `sqlcipher_guard_test.dart`, `local_database_bootstrap_test.dart`, `app_database_rekey_test.dart`, `transfer_key_backup_test.dart` |
| Local filesystem (photos, cache, database and transfer-backup files) | Yes — real files under a temp `docsDir` | `Directory`/`File` against `path_provider` overridden to a temp path | `account_switch_test.dart` (writes real photo bytes so the wipe has real files to orphan), `local_database_bootstrap_test.dart` (a database file restored with no key), `transfer_key_backup_test.dart` |
| Secure key storage (`flutter_secure_storage`) | Faked at the *platform* boundary, so the real `FlutterSecureStorage` serialises the options the service passed and a test can pin them | `FakeSecureStoragePlatform` installed as `FlutterSecureStoragePlatform.instance` (`test/helpers/fake_secure_storage.dart`), recording every write with its options | `encryption_key_service_test.dart`, `local_database_bootstrap_test.dart` |
| Firebase Auth | Faked | Hand-rolled fake in `test/helpers/firebase_mocks.dart` implementing the subset of the SDK surface the app calls | `auth_provider_test.dart`, `account_switch_test.dart` |
| Cloud Firestore (sync push/pull) | Faked | In-memory fake store, not `fake_cloud_firestore` or an emulator | `sync_service_test.dart`, `sync_provider_test.dart` |
| Cloud Storage (photo upload) | Faked | `firebase_storage_mocks` package | `sync_service_test.dart` |
| `firestore.rules` (feedback doc shape, per-user isolation) | Not tested at all | — | **Gap, §11-P1**: the field-allowlist, length caps, and `uid` binding in `firestore.rules` have no automated test; only the Cloud Function side (`sanitize.ts`) is unit-tested |
| `storage.rules` | Not tested at all | — | **Gap, §11-P2** |
| Cloud Function → Discord webhook | Contract-tested | `notify_discord.test.js` asserts the outgoing payload shape against a mocked `fetch`, not a live webhook | `functions/test/notify_discord.test.js` |
| App Check | Not exercised in tests (by design — it gates production traffic, not local logic) | — | — |

**Why fakes over an emulator:** the Firebase Local Emulator Suite would let `firestore.rules`
and `storage.rules` be tested for real (closing the two gaps above), at the cost of a Java
runtime dependency and slower CI. That trade-off is exactly the kind of call that belongs in
§11's backlog, not something to decide inside a docs PR.

---

## 4. Regression Catalog

Every `fix:`-prefixed commit becomes a row. "Guarding test" is the automated test that fails
if the bug comes back; **UNGUARDED** means none exists today. Built from `git log --oneline
--all --grep=^fix -i` (functions/CI history only goes back to PR #13; earlier `Fix ...`
commits, capitalized without a colon, predate the `fix:` convention and are catalogued
alongside it below where they're still live risks).

| Commit | Bug fixed | Guarding test |
|---|---|---|
| `fix(sync): report a drain's own outcome, not the latched status` | The debounced drain decided idle-vs-error from `SyncState.status`, which is what the *previous* run latched: once a failed drain set the error, a later drain that pushed everything left Settings showing "Sync error" with the stale message and never advanced `lastSyncedAt`, until the user tapped Sync Now or signed in again; a failed drain also reported no error at all, because exhausted retries were silent | `sync_provider_test.dart`: `"a recovered drain returns the device to idle and backed up"`, `"a drain that is still failing keeps the error"`, `"a best-effort photo file failure is not a drain failure"` |
| `fix(database): guard the tag colour migration step` | Upgrading a database at schema version 5 or lower threw `duplicate column name: color` and left the app unopenable (only a reinstall, destroying local pottery, cleared it): the `from < 6` step creates `tag_options` from the *current* Dart definition, which already has `color`, and the unguarded `from < 7` step then added it again. Edge-case finding E4 | `migration_test.dart` (v1-v5 all failed before the fix, v6-v8 passed); `"a version 1 piece survives the whole upgrade"` also pins the clay `sort_order` backfill, which only ran for v3 and left a v1/v2 upgrade's whole clay library at 0 |
| `fix(sync): retire the queue snapshot delivered by full sync` | A first sign-in bulk-uploaded every local row and photo but then left or individually reprocessed the same queued work, so the pending count stayed stale and later edits could re-upload every photo file; retiring the whole snapshot then acknowledged queued deletions the upload never sent, and the pull that followed resurrected the deleted pottery | `sync_queue_durability_test.dart`: `"first sign-in retires its queue snapshot without re-uploading photos"`, `"first sign-in tombstones a queued deletion before it pulls"`, `"a deletion whose tombstone fails stays queued"`; `sync_provider_test.dart`: `"full sync acknowledges only the entries it pushes"`, `"full sync sends a queued deletion before it pulls"` |
| `fix: preserve edits queued during sync and repay deferred drains` | Full-sync completion cleared unacknowledged edits and exhausted pushes; a debounce expiring while sync was busy was dropped; and a push acknowledged by entry equality took with it the revision an edit had merged into the entry mid-flight (entry `==` ignores `changedFields`, so the drain could not see it). Covers pt-sync-durability E1 and E2's owed-reschedule half | `sync_queue_durability_test.dart` (seven controlled-timer regressions; incremental loss, missing follow-up and the same-entity mid-push edit each reproduced before the fix), `sync_provider_test.dart` (`"full sync acknowledges only the entries it pushes"`) |
| `eda9c89` (#24) | Database key stored under migratable iOS keychain accessibility and legacy Android ciphers (security review M6/L2); hardening alone would have made a restored local-only database unreadable with no way out | `encryption_key_service_test.dart` (options pinned at the call boundary), `local_database_bootstrap_test.dart` ("restore onto a new phone … no key is created over it"), `database_recovery_screen_test.dart`; the native keychain behaviour itself is **UNGUARDED** (device only, §11-P0) |
| `cb0eadf` (#13) | Sign-out didn't erase local data; a refused account could write; feedback intake was unbounded | `account_switch_test.dart` (49 cases), `feedback_screen_test.dart`, `firestore.rules` allowlist (rules themselves **UNGUARDED**, §3) |
| `e75373c`/`3d4bc49` | Owed wipe never retried once the sync blocking it ended | `account_switch_test.dart`: `"a sync that outlives a confirmed wipe is published while it runs, and withdrawn when it ends"` |
| `75008bb` | Lock-exit request wasn't scoped; wipes were reported that hadn't happened | `account_switch_test.dart` (`eraseLocalDataNow`/`deleteAllData` result-reporting cases) |
| `52929e3` | Redirect had no fixed point when session + lock both vanished | `app_router_test.dart` |
| `40b38d6` | Read-only lock was derived from transient `SyncStatus` instead of persisted owner stamp — each transition that touched it reopened the hole | `account_switch_test.dart` (persisted-flag cases) |
| `823af77` | Per-row foreign-write attribution design (queue uid stamps, reconciliation) replaced by device-level lock — the old design produced two paths that destroyed the owner's pottery permanently | `account_switch_test.dart`; `AGENTS.md` explicitly forbids reintroducing the old design |
| `58f7b2c` | Two wipe owners (sign-out wipe vs. owed-wipe retry) could clear each other's in-flight guards | `account_switch_test.dart` |
| `f937736` | Owed wipe was retried from paths the user didn't expect (`syncNow`, the debounced push) | `account_switch_test.dart`: `"a debounced push never resumes the wipe under the current account"` |
| `b876115` | Next account's first sync could push onto a device still holding the previous account's data | `account_switch_test.dart` |
| `c7ef44c` | Feedback could reach the maintainer's Discord channel un-sanitised | `functions/test/sanitize.test.js`, `functions/test/notify_discord.test.js` |
| `eccfeb0` | Unauthenticated `/feedback` writes were unbound (no field allowlist, no length caps) | `firestore.rules` rule itself **UNGUARDED** (§3); `feedback_service_test.dart` covers the client side only |
| `eda447f`/`e60f0ec` | Local data survived sign-out; last remaining sign-in provider could be disconnected (locking the user out) | `account_switch_test.dart`, `settings_account_test.dart` |
| `4f2ed70`/`9a3bc7c` (#14) | Android release build broken by `sqlcipher_flutter_libs` < 0.6.8 (`android:attr/lStar`, 4KB page alignment) | **UNGUARDED** — no CI job builds the Android release APK/AAB (§9, §11-P0); the pin itself is enforced only by `AGENTS.md` + human review of `pubspec.yaml` |
| `ceb5d3d` (#12) | Orientation could rotate on iPad despite portrait-only intent (multitasking exemption) | **UNGUARDED** — no automated test asserts `Info.plist`/`AndroidManifest.xml` orientation declarations stay in sync (§11-P2); currently a manual release check only (§6) |
| `3cd97cc` | Splash animation replayed on router rebuild | `splash_overlay_test.dart` |
| `be43539`/`bae2a7f` | Vase mark scaled per-axis instead of uniformly (aspect distortion) | `vase_logo_test.dart` |
| `d3fb87b` | Search results flickered on input | **UNGUARDED** — no widget test debounces/asserts search stability |
| `97d16ba` | Login screen flashed on launch; sign-out didn't persist | Superseded by the full sign-out/erase rewrite in `cb0eadf`; covered by `account_switch_test.dart` |
| `73c0f43` | Apple Sign-In spinner shown on the Google button | **UNGUARDED** — no widget test asserts per-button loading-state isolation |
| `7ef7bc5` | Camera crash from missing `NSCameraUsageDescription` | **UNGUARDED** by nature — Info.plist entries aren't unit-testable; covered only by the manual release checklist (§6, §9) |
| `59ef150` | "Delete all data" required sign-in first | `account_switch_test.dart` (no-account deletion cases) |
| `9a26c3b` | Date handling: time picker removed, display date shown in list view | `display_date_test.dart` (which date a piece shows); list rendering via `album_grid_test.dart` |
| `0029f6c`/`5dac32c` | Title field lost its value when another field was tapped | **UNGUARDED** — no piece-detail widget test exists at all (§2.3, §11) |

**Rule:** every future `fix:` commit adds a row to this table in the same PR, naming the
guarding test it added — or, if none was added, marking the row **UNGUARDED** and filing it
into §11 rather than leaving it silent. A `fix:` PR that touches this file only to add its
row, with no test, is a signal the review should push back on unless the fix is genuinely
untestable (an `Info.plist` entry, a build config pin).

---

## 5. End-to-End & UI Tests

There is no `integration_test/` directory and no automated E2E suite — `pubspec.yaml` has
no `integration_test` dependency. This is a deliberate consequence of the platform, not an
oversight: the two riskiest flows (Camera capture, PHPicker multi-select photo library) do
not function in the iOS Simulator at all (`AGENTS.md`; `TEST_PLAN.md` §6.4), so a `patrol` or
`flutter_driver` suite driving the simulator could not exercise them either — it would only
cover what the widget tests (§2.2) already cover, on a slower runner. `docs/design/splash-logo/`
round 26 (`round-26-handoff-*.png`) and the two `.mp4` captures under that directory are the
closest thing to recorded device evidence today, and they're a one-off design-approval
artifact, not a repeatable test.

**What would need to run where, if this changes:**
- **iOS Simulator** (any recent iPhone runtime) — everything except Camera and the
  PHPicker multi-select photo flow; sufficient for router/navigation/CRUD E2E.
- **Physical iOS device** — required for Camera and multi-select photo E2E (§6.4's NOTE),
  and for the App Store-distributed build's SQLCipher/App Check path.
- **Android** — no E2E has ever run, on emulator or device (`AGENTS.md`: "Android builds
  ... but has never run on a device" — the highest release risk in the project, tracked as
  a manual/release item in §6.9 and §9, not a testing gap this doc can close).
- No browser target — this is not a Flutter web-shipped app (the `web/` directory exists
  from `flutter create` scaffolding but is not part of the product).

§11-P1 proposes a minimal `integration_test/` smoke suite (auth skip → create piece from
Photo Library → edit metadata → archive) runnable headlessly on the iOS Simulator in CI,
explicitly scoped to avoid Camera/multi-select.

---

## 6. Manual & Exploratory Test Plan

This section is the project's pre-existing feature checklist, carried forward with its
structure and content intact. Each checkbox is a scripted scenario a human runs against a
build (iOS Simulator for everything except where noted; a physical device where the
Simulator can't exercise the path) and its expected result is the checkbox text itself.
Un-checked boxes are scenarios not yet re-verified since being written, not known failures.

### 6.1 Authentication & Onboarding

#### Sign-In Screen (`/sign-in`)
- [ ] "Sign in with Google" button launches Google sign-in flow
- [ ] "Sign in with Apple" button appears only on iOS
- [ ] "Skip for now" bypasses auth and enters app — offered only while nobody has a stake in this device; it disappears once an account has claimed it, been refused here, or is owed a wipe
- [ ] Auth state persists across app restarts (SharedPreferences)
- [ ] After sign-in or skip, user lands on Album screen

#### Edge Cases
- [ ] Force-quit and relaunch — user stays authenticated
- [ ] Sign out from Settings → local data erased, redirected back to sign-in screen

#### Device Locked (`/device-locked`)
Reached for two different reasons, which the screen tells apart. **Foreign pottery**: a session ended
involuntarily (offline launch, revoked token) and a *different* account signed in afterwards, so the
device still holds the previous account's pottery. **Owed wipe**: an explicit "Sign Out & Erase" set
the wipe going and it never finished, so the signed-out account's whole library is still here.

Foreign pottery:
- [ ] Signing in as a different account after an involuntary sign-out lands on the lock screen, not the album
- [ ] Nothing that can write is reachable while locked — album, create flow, piece editor, Settings and the Manage Clays/Glazes/Tags screens all come straight back to the lock
- [ ] "Sign In" ends the session and returns to sign-in **without** deleting anything — the label is deliberately not "as another account", since the reader may be the owner signing in as themselves
- [ ] The owner signing back in releases the lock and hands the app back on its own
- [ ] Force-quitting the lock screen and relaunching with no network lands back on the lock, not on the owner's album
- [ ] The owner's own offline launch (no network, nobody refused here) opens the album as usual

Owed wipe:
- [ ] Force-quit mid-wipe → the lock reads "This device still has to be erased" and says the pottery the user asked to have deleted is still here — never that it belongs to another account, because it is their own
- [ ] Opening the lock retries the wipe on its own; a failure that was transient clears without the user tapping anything
- [ ] Sign out while a long sync is running (many queued edits, network off): the lock opens while that sync is still unwinding, and once it ends the wipe is retried on its own — the device does not stay locked until "Erase This Device" is tapped
- [ ] Its primary action is "Erase This Device" — it never offers "Sign In", which would keep the data the user asked to destroy
- [ ] A "Delete Account & Data" whose local wipe failed lands here, and its message names erasing this device first — the one step reachable from the lock — before signing in again to retry the account
- [ ] A "Delete Account & Data" that did remove the account but whose local wipe failed arrives here signed out; once the wipe finishes, the device is unclaimed — never stamped for the deleted account — and signing in with the same provider works

Both:
- [ ] "Erase This Device" confirms first — "Cancel" is the default action and tapping outside the dialog does not erase
- [ ] Confirming the erase deletes everything on the device, releases the lock, and lets the signed-in account start fresh
- [ ] An erase that could not run (a sync or wipe in flight) says so rather than failing silently
- [ ] An erase that failed says so rather than closing the dialog on silence
- [ ] An erase that removed the pieces and materials but not every photo file says exactly that — never "Nothing was deleted" — and the lock stays up, still offering the erase that finishes it
- [ ] An erase that removed everything but could not secure the device — the database key not replaced, or the transfer backup not deleted — says exactly that, never that data was left behind, and the lock stays up offering the retry that finishes it
- [ ] The same from "Delete Account & Data" in a session with no account ("Skip for now"): the message says the pieces and materials are gone and some photo files remain — never "Nothing was deleted" — and the lock underneath agrees

**Regression note:** this whole area is the highest-churn part of the app (14 of the 25
`fix:` commits in §4). `account_switch_test.dart` automates the state-machine version of
every scenario above; this manual pass exists to catch what only shows up in real UI —
timing, copy, dialog defaults.

#### Splash Screen (`/splash`)
- [ ] Vase mark draws itself on over ~900ms at launch
- [ ] No flash or colour change between the native launch screen and the Flutter splash
- [ ] Animation always completes — never cut off mid-stroke, even when auth resolves fast
- [ ] App proceeds to Album (signed in) or Sign-In (signed out) once the stroke finishes
- [ ] Launch is not blocked if the animation stalls (3-second fallback releases it)
- [ ] No spinner on the splash — the draw-on is the only progress signal
- [ ] Home-screen app icon matches the drawn mark
- [ ] Icon reads clearly at small sizes (Spotlight, Settings, notifications)

### 6.2 Bottom Navigation

#### Shell Screen
- [ ] Home tab (left) → Album screen
- [ ] "+" button (center) → Create piece flow
- [ ] Settings tab (right) → Settings screen
- [ ] Tapping active tab preserves scroll position / state

### 6.3 Album Screen (Home)

#### Active View (default)
- [ ] Pieces shown as rows with title, updatedAt date, + horizontally scrollable photo thumbnails
- [ ] Newest-updated pieces appear first
- [ ] Tapping a row opens piece detail
- [ ] Scrollable photo row shows left/right fade gradients when overflowing
- [ ] Gradients hide when scrolled to edge
- [ ] Swipe left on a piece row → teal background with archive icon → piece archived
- [ ] "Piece archived" snackbar with "Undo" action shown for 2 seconds
- [ ] Tapping "Undo" restores piece to active list
- [ ] Light haptic feedback on swipe-archive

#### Archive View
- [ ] Tap "Archive" chip → shows 3-column grid of archived pieces
- [ ] Archive thumbnails are 1:1 square with title text overlay at bottom-right
- [ ] Title overlay has gradient fade from transparent to semi-black
- [ ] Long titles truncate with ellipsis
- [ ] Untitled pieces show "Untitled Piece N" on overlay
- [ ] Placeholder thumbnails (no cover photo) also show gradient + title
- [ ] Tapping thumbnail opens piece detail

#### Search
- [ ] Typing in search bar filters pieces in real-time
- [ ] Searches across: title, clay type, glazes, tags, notes
- [ ] Clearing search shows all pieces again
- [ ] Search field has no autocorrect

#### Empty States
- [ ] No active pieces → "No pieces yet" message with icon
- [ ] No archived pieces → empty state shown in archive view

#### Metadata in Home View
- [ ] **TODO:** Display tags, clay, glazes, and other metadata below each piece row in the home view

#### Edge Cases
- [ ] Piece with no photos → placeholder icon in row and archive grid
- [ ] Very long title → ellipsis truncation
- [ ] Single photo piece in row → no gradients shown

### 6.4 Piece Creation

#### Flow
- [ ] Tap "+" → bottom sheet with Camera / Photo Library
- [ ] Select source → pick image → processing spinner → navigates to detail
- [ ] New piece gets auto-title "Untitled Piece N" (lowest available number)
- [ ] First photo set as cover automatically

#### Untitled Piece Numbering
- [ ] First piece → "Untitled Piece 1"
- [ ] With "Untitled Piece 1" existing → new piece is "Untitled Piece 2"
- [ ] With "Untitled Piece 1" and "Untitled Piece 3" existing → new piece is "Untitled Piece 2" (fills gap)
- [ ] Renaming "Untitled Piece 1" to something else → next piece reuses number 1

#### Edge Cases
- [ ] Cancel source picker → returns to previous screen
- [ ] Cancel image picker → returns to previous screen
- [ ] Image compression fails → raw bytes saved as fallback
- [ ] Camera on iOS simulator → crashes (use Photo Library for testing)

### 6.5 Piece Detail Screen

#### Photo Gallery
- [ ] Photos displayed as 1:1 squares at 72% screen width
- [ ] Horizontal free-scrolling (no page snapping) with bounce physics
- [ ] Newest photo appears leftmost
- [ ] Left/right fade gradients appear when gallery is scrollable
- [ ] Gradients hide when scrolled to respective edge
- [ ] Single photo → centered, no gradients
- [ ] Date label shown below each photo (e.g. "Feb 12, 2026")
- [ ] Tap photo → fullscreen viewer with pinch-zoom (0.5x–4x)
- [ ] Long-press photo → bottom sheet with "Delete photo" option

#### Photo Management
- [ ] Add photo via camera icon in app bar → Camera / Photo Library picker
- [ ] New photo becomes cover automatically
- [ ] Delete photo → confirmation dialog → photo removed
- [ ] Deleting cover photo → next newest photo becomes cover
- [ ] Deleting all photos → no gallery shown, just metadata form

#### Batch Photo Upload (Photo Library multi-select)
- [ ] Photo Library option uses multi-select picker (select 1 or many)
- [ ] Progress dialog shows "Processing X of Y..." for multiple photos
- [ ] All selected photos added to piece gallery
- [ ] Last photo in batch set as cover
- [ ] Failed photos skipped; failure count shown in snackbar
- [ ] Cancelling multi-picker returns with no changes
- **NOTE: Multi-select (PHPicker) does NOT work on iOS simulator. Camera also crashes on simulator. Both require a real device to test.**

#### Photo Reordering
- [ ] "Reorder" button appears below gallery when 2+ photos exist
- [ ] "Reorder" button hidden when 0-1 photos
- [ ] Tapping "Reorder" opens full-screen list with thumbnails and drag handles
- [ ] Dragging a photo reorders the list
- [ ] Tapping "Done" saves new order; gallery reflects updated order
- [ ] Tapping back (without Done) discards changes
- [ ] **TODO:** Allow deleting photos from the reorder screen

#### Metadata Form
- [ ] Edit title → saves on keyboard "done"
- [ ] Title field defaults to uppercase first letter (TextCapitalization.sentences)
- [ ] Title field has no autocorrect suggestions
- [ ] Select stage (Greenware / Bisqued / Glazed / None) → saves immediately
- [ ] Clay field is a dropdown (not free text)
- [ ] Clay dropdown shows "None" + saved clays + divider + "+ Add New"
- [ ] Selecting a clay → saves immediately
- [ ] Selecting "None" → clears clay value
- [ ] Tapping "Add New" (icon + text, no duplicate +) → dialog with text input → creates clay + selects it
- [ ] Newly created clay appears in dropdown for other pieces
- [ ] Pieces with existing clay text values → preserved after DB migration
- [ ] Glazes field is a multi-select picker (not free text)
- [ ] Tapping Glazes → bottom sheet with checkboxes for each saved glaze
- [ ] Checking/unchecking glazes → "Done" button commits selection
- [ ] "None" checkbox clears all glaze selections
- [ ] "Add New" in glaze picker → dialog → creates glaze + auto-checks it
- [ ] Selected glazes displayed as comma-separated text on the field
- [ ] Pieces with existing free-text glazes → parsed into library on migration
- [ ] Tags field is a multi-select picker
- [ ] Tapping Tags → bottom sheet with checkboxes for each saved tag
- [ ] Checking/unchecking tags → "Done" button commits selection
- [ ] "None" checkbox clears all tag selections
- [ ] "Add New" in tag picker → dialog → creates tag + auto-checks it
- [ ] Selected tags displayed as comma-separated text on the field
- [ ] Tags searchable from album search bar (via denormalized column)
- [ ] Edit notes (multiline) → saves on keyboard "done"
- [ ] All material dialogs (clay, glaze, tag) default to uppercase first letter and have no autocorrect
- [ ] Notes field has no autocorrect
- [ ] Empty string fields saved as NULL in database

Also see `testing/searchable-pickers.md` for the searchable-picker variant of this form
(search-within-picker, recent-item pills) — a standalone script with both a human and an
agent/computer-use variant, current as of writing.

#### Actions (Icon Buttons in App Bar)
- [ ] Archive icon button → piece archived, navigates back to home
- [ ] Unarchive icon (on archived piece) → piece unarchived, stays on detail
- [ ] Trash icon (red tint) → confirmation dialog → piece + all photos deleted, navigates home

#### Title (Above Gallery)
- [ ] Title displayed above photo gallery with titleLarge styling
- [ ] Title is editable, saves on keyboard "done"
- [ ] Untitled pieces: title field is empty, hint shows "Untitled Piece N" with correct number
- [ ] Leaving title empty preserves "Untitled Piece N" in DB for album display
- [ ] Typing a name replaces the untitled name
- [ ] Pieces with custom titles show the title prefilled normally

#### Haptic Feedback (manual — requires physical device)
- [ ] Adding a photo → light haptic
- [ ] Deleting a photo (after confirm) → light haptic
- [ ] Archiving/unarchiving → light haptic
- [ ] Deleting a piece (after confirm) → medium haptic
- [ ] Creating a new piece → light haptic

#### Done Button
- [ ] Tapping "Done" saves pending form changes and navigates to home

#### Last Updated (Editable)
- [ ] Shows "Last updated {date} {time}" below metadata with edit icon
- [ ] Timestamp updates after any edit
- [ ] Tapping opens date picker then time picker
- [ ] Selected date/time updates the updatedAt in DB
- [ ] Cancelling date picker leaves date unchanged
- [ ] Cancelling time picker uses existing time with new date

### 6.6 Fullscreen Photo Viewer

- [ ] Black background with close button
- [ ] Pinch-to-zoom (0.5x min, 4x max)
- [ ] Tap back / close to return to detail

### 6.7 Settings Screen

- [ ] Shows "Signed in as {name}" or "Not signed in"
- [ ] "Sign Out" → confirmation says every piece, photo and material on this device is deleted; "Cancel" is the default action and tapping outside the dialog does not sign out
- [ ] Confirming "Sign Out & Erase" clears auth, deletes the local library and photo files, and redirects to sign-in
- [ ] Signing in as a *different* account afterwards uploads nothing belonging to the previous one
- [ ] Force-quit mid-wipe → the device comes back locked read-only, the lock screen finishes the wipe on its own without being asked, and nothing is uploaded before it does; Settings is not reachable at all while it is owed
- [ ] A "Sign Out & Erase" whose wipe failed says the device stays locked until the erase finishes — it never promises that the next sign-in will do it, because the lock is what retries it
- [ ] A "Sign Out & Erase" that erased everything but could not secure the device says that, not that data was left behind (same wording as the lock screen, §6.1)
- [ ] The only connected sign-in provider cannot be disconnected — its row is disabled and explains why
- [ ] "Materials" section with "Manage Clays", "Manage Glazes", and "Manage Tags" options
- [ ] "Cloud Backup" section shows the current sync status and a "Sync Now" action
- [ ] "Moving to a new phone" section explains that pottery kept on this phone alone travels only with a passphrase (signed in: that the account carries it instead)
- [ ] iOS only: a "Transfer passphrase" row whose subtitle reads Set/Not set from the backup file itself — set, change, remove, and a too-short passphrase refused (floor: `TransferKeyBackup.minPassphraseLength`; design: `docs/local-database-key.md`)
- [ ] Android: the section says local-only pottery does not move and offers no passphrase row at all
- [ ] Support section offers only "Send Feedback"; no Ko-fi support link or donation link is present
- [ ] Version row shows the `version` from `pubspec.yaml` (the authoritative source), not a hardcoded string

#### Manage Clays Screen (`/settings/clays`)
- [ ] Shows list of saved clay names in custom sort order
- [ ] Empty state: "No clays saved yet" when no clays exist
- [ ] "+" button in app bar → add dialog → creates new clay (appears at bottom)
- [ ] Edit icon on each clay → edit dialog → renames clay
- [ ] Delete icon on each clay → confirmation dialog → deletes clay
- [ ] Deleting a clay does NOT clear clay from existing pieces (value preserved)
- [ ] Adding duplicate clay name (case-insensitive) → reuses existing
- [ ] Changes reflected immediately in piece detail clay dropdown

#### Clay Reordering
- [ ] Drag handles visible on left side of each clay row
- [ ] Dragging a clay to a new position reorders the list immediately
- [ ] Reorder persists after leaving and returning to Manage Clays
- [ ] Custom order reflected in piece detail clay picker dropdown
- [ ] Newly added clays appear at the bottom of the list
- [ ] Scale + elevation animation on dragged item

#### Clay Rename Propagation
- [ ] Renaming a clay in Manage Clays → all pieces using that clay show the new name
- [ ] Renaming updates the piece detail clay display immediately

#### Manage Glazes Screen (`/settings/glazes`)
- [ ] Shows list of saved glaze names in custom sort order
- [ ] Empty state: "No glazes saved yet" when no glazes exist
- [ ] "+" button in app bar → add dialog → creates new glaze (appears at bottom)
- [ ] Edit icon on each glaze → edit dialog → renames glaze
- [ ] Delete icon on each glaze → confirmation dialog → deletes glaze + removes from pieces
- [ ] Adding duplicate glaze name (case-insensitive) → reuses existing
- [ ] Changes reflected immediately in piece detail glaze picker
- [ ] Drag handles visible on left side of each glaze row
- [ ] Dragging a glaze to a new position reorders the list immediately
- [ ] Scale + elevation animation on dragged item

#### Glaze Rename Propagation
- [ ] Renaming a glaze in Manage Glazes → all pieces using that glaze show updated name
- [ ] Denormalized glazes text column updated (for search)

#### Manage Tags Screen (`/settings/tags`)
- [ ] Shows list of saved tag names in custom sort order
- [ ] Empty state: "No tags saved yet" when no tags exist
- [ ] "+" button in app bar → add dialog → creates new tag (appears at bottom)
- [ ] Edit icon on each tag → edit dialog → renames tag
- [ ] Delete icon on each tag → confirmation dialog → deletes tag + removes from pieces
- [ ] Adding duplicate tag name (case-insensitive) → reuses existing
- [ ] Changes reflected immediately in piece detail tag picker
- [ ] Drag handles visible on left side of each tag row
- [ ] Dragging a tag to a new position reorders the list immediately
- [ ] Scale + elevation animation on dragged item

#### Tag Colors
- [ ] New tags auto-assigned a default color from 7 presets (cycling)
- [ ] Colored circle shown next to each tag in Manage Tags list
- [ ] Tapping circle opens color picker bottom sheet with 7 preset swatches
- [ ] Selected swatch shows checkmark and border
- [ ] Picking a color saves immediately; Manage Tags list updates
- [ ] Album view tag chips reflect custom color (tinted bg + darkened text)
- [ ] Tags without a custom color fall back to hash-based palette
- [ ] Color dot shown next to each tag in piece detail tag picker bottom sheet

#### Tag Rename Propagation
- [ ] Renaming a tag in Manage Tags → all pieces using that tag show updated name
- [ ] Denormalized tags text column updated (for search)

### 6.8 Data & Image Pipeline

#### Image Processing
- [ ] Main image: JPEG q75, max 1500px
- [ ] Thumbnail: JPEG q60, max 300px
- [ ] EXIF date extracted when available; falls back to current time
- [ ] Compression failure → raw bytes fallback

#### Database
- [ ] Pieces table: id, title, stage, clayType, glazes (denormalized), tags (denormalized), notes, isArchived, coverPhotoId, createdAt, updatedAt
- [ ] Photos table: id, pieceId, localPath, thumbnailPath, cloudUrl, dateTaken, createdAt, sortOrder
- [ ] ClayOptions table: id, name (unique), sortOrder, createdAt
- [ ] GlazeOptions table: id, name (unique), sortOrder, createdAt
- [ ] PieceGlazes junction table: id, pieceId, glazeOptionId, sortOrder
- [ ] TagOptions table: id, name (unique), color (nullable), sortOrder, createdAt
- [ ] PieceTags junction table: id, pieceId, tagOptionId
- [ ] Photos sorted by sortOrder DESC (newest first) everywhere
- [ ] Migration chain exercises cleanly on an old on-disk database. Every version below the current `schemaVersion` has a checked-in fixture walked to the current schema by `test/database/migration_test.dart`, so this manual step is confirmation on a real SQLCipher file, not the primary net; the suite fails if that fixture set is not exactly every version below `schemaVersion`

### 6.9 Cross-Cutting Concerns

#### Offline-First
- [ ] All features work without network connectivity
- [ ] Firebase sync is live: when signed in, local writes are pushed to Firestore/Cloud Storage; when offline, the sync queue holds them and retries

#### Localization
- [ ] All UI strings from `app_en.arb` (no hardcoded user-facing strings except error messages)

#### Accessibility
See §9 for the full accessibility test plan; this is the original three-line manual check,
kept for continuity with `flutter gen-l10n`/build habits:
- [ ] Semantics labels on interactive elements
- [ ] Minimum 48dp touch targets (Android) / 44pt (iOS)
- [ ] System font scaling respected

#### Error Handling
- [ ] Broken image files → placeholder icon shown
- [ ] Photo capture failure → SnackBar error message
- [ ] Database errors → "Error: {e}" displayed

#### Android (manual/release-only — see AGENTS.md, docs/android-release.md, §9)
- [ ] `flutter build apk --release -PrequireReleaseSigning=true` succeeds with a real `android/key.properties`
- [ ] The built AAB installs and launches on a physical Android device — **never yet done**; this is the single highest-risk unverified item in the project (`AGENTS.md`)
- [ ] The encrypted-DB path (`configureSqlCipher` → `AppDatabase.open()`) does not fall back to plaintext on-device
- [ ] Portrait lock holds on an Android large-screen/tablet device (the `PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY` opt-out, load-bearing only at targetSdk 37+)

### 6.10 Firebase Analytics & Crashlytics

#### Analytics Events
- [ ] `sign_in_attempted` — fires when user taps Google or Apple sign-in button (with `method` parameter)
- [ ] `sign_in_skipped` — fires when user taps "Skip for now"
- [ ] `filter_changed` — fires when user switches between Active/Archive filter chips (with `filter` parameter)
- [ ] `photo_viewed_fullscreen` — fires when user taps a photo to view fullscreen
- [ ] `photo_reorder_saved` — fires when user saves a new photo order (with `photo_count` parameter)
- [ ] `material_created` — fires when user creates a new clay, glaze, or tag (with `material_type` parameter)
- [ ] `piece_created` — fires when a new piece is created
- [ ] `piece_deleted` — fires when a piece is deleted
- [ ] `piece_archived` — fires when a piece is archived
- [ ] `piece_unarchived` — fires when a piece is unarchived
- [ ] `photo_added` — fires when a photo is added to a piece

#### Screen Tracking
- [ ] Auto screen tracking logs screen changes via `FirebaseAnalyticsObserver` on GoRouter

#### Crashlytics
- [ ] Test crash button visible in Settings under "Debug" section
- [ ] Tapping "Test Crash" triggers a `FirebaseCrashlytics.instance.crash()`
- [ ] Uncaught Flutter errors reported via `FlutterError.onError`
- [ ] Uncaught platform errors reported via `PlatformDispatcher.instance.onError`

#### Verification
- [ ] All analytics events fire without errors (no crashes or exceptions)
- [ ] Events visible in Firebase Console (DebugView) after ~24h or via debug mode
- [ ] Crashlytics test crash appears in Firebase Console

### 6.11 In-App Review Prompt + Feedback Form

#### Gating
- [ ] Fresh install creates 1, 2 pieces → no prompt fires.
- [ ] After 3rd piece, before 3 days since install → no prompt fires.
- [ ] After 3rd piece + 3 days + 2 sessions → soft-ask appears on next save.
- [ ] After any prompt fires → 90-day cooldown enforced.

#### Soft-ask paths
- [ ] "Yes, I love it!" → native review sheet (or silently no-op if iOS cap hit).
- [ ] "Could be better" → /feedback opens with form.
- [ ] Outside-tap dismiss → cooldown starts, no further action.

#### Feedback form
- [ ] Send disabled until message non-empty.
- [ ] Successful submit → toast, pops back, doc lands in Firestore `feedback/`.
- [ ] Failed submit (airplane mode) → error toast, form stays open.
- [ ] Anonymous user submit → doc has `uid: null`.
- [ ] Reply email field stops accepting input at 254 characters (the cap `firestore.rules` enforces).

#### Settings entry
- [ ] Settings → "Send Feedback" → /feedback opens directly (no soft-ask).

---

## 7. Performance & Load

There is no automated performance testing or budget enforcement today (§11-P3). What
exists is informal, and the informal targets are recorded here so they stop being tribal
knowledge:

| Budget | Target | How it would be measured |
|---|---|---|
| Cold launch → interactive album | Splash completes in ~900ms (fixed animation), app usable within ~1.5s of that on a mid-tier device | `flutter drive` with `--profile`, or Xcode Instruments' App Launch template — manual today |
| Image compression (per photo) | Sub-second for a typical phone-camera JPEG down to q75/1500px | `image_service_test.dart` asserts correctness, not wall-clock time |
| Batch photo upload (multi-select) | "Processing X of Y" dialog should not visibly stall between photos | Manual only (§6.5); simulator can't exercise the picker at all |
| Sync debounce | Drains within the short debounce window `AGENTS.md` describes; no numeric SLO documented | `sync_provider_test.dart`/`sync_queue_test.dart` assert ordering and retry, not timing |
| Local DB size / query time | No documented ceiling — Firestore's own budget (1GB, 50K reads/day, 20K writes/day on Spark) is the real constraint, not local SQLite | Not measured |
| App size | Not tracked | `flutter build ... --analyze-size` would produce this; not run today |

**Load** in the traditional sense (concurrent users hitting a server) doesn't apply — the
only shared backend surface is the `feedback` Cloud Function and Firestore/Storage under
each user's own `users/{uid}` tree, both bounded by Firebase Spark's daily quotas, not by
this app's request volume. §11-P3 proposes the smallest concrete step: recording actual
`flutter build --analyze-size` output and cold-launch timing once per release as a release
checklist line, before reaching for a dedicated perf-test rig this app doesn't need yet.

---

## 8. Security & Privacy

| Area | Control | Verified by |
|---|---|---|
| Local data at rest | SQLCipher-encrypted SQLite (`sqlcipher_flutter_libs` ≥ 0.6.8); `assertSqlCipherBacksSqlite3` refuses to hand back a connection that isn't actually encrypted | `sqlcipher_guard_test.dart` (the guard function only — **not** its call site, §11-P0) |
| Encryption key | Generated and stored via `encryption_key_service.dart` under pinned options: iOS `first_unlock_this_device` (never in a backup, never iCloud-synced), Android KeyStore RSA-OAEP + AES-GCM; legacy keys migrated with read-back verification. A restored database with no key is refused at launch (`LocalDatabaseBootstrap`) and routed to recovery; local-only users bridge devices with a passphrase-wrapped SQLCipher copy (`TransferKeyBackup`). Design: `docs/local-database-key.md` Rotated at Sign Out & Erase (`PRAGMA rekey`, then store; keyed back if the store fails) so a former owner's transfer file unwraps nothing new. The hardening rewrite keeps a migrating copy on disk so a crash between its delete and add loses no key. Android: `dataExtractionRules` keeps every domain out of cloud backup and device transfer, and a stored key this device cannot decrypt reads as missing (→ recovery) | `encryption_key_service_test.dart`, `local_database_bootstrap_test.dart`, `transfer_key_backup_test.dart`, `sync_service_test.dart` (rotation: statement order and key-back only — the rekey itself is device-only, §11-P0), `app_database_rekey_test.dart` (a failed rekey never quotes the key), `data_extraction_rules_test.dart`; real keychain replace-and-exclude behaviour is device-only (§11-P0) |
| Cloud data isolation | Firestore/Storage rules scope every path to `users/{uid}/...`, `request.auth.uid == userId` | `firestore.rules`/`storage.rules` themselves are **not** test-covered (§3, §11-P1/P2); only the app-side write path is |
| Cross-account data leakage | Device-level `localDataOwnerUid`/`localDataContested` lock (`AGENTS.md`) prevents one account's data from being pushed under another's identity or left readable to a refused account | `account_switch_test.dart` (49 cases) — the project's most heavily regression-tested area |
| Feedback endpoint abuse | Field allowlist, per-field length caps, server-set `createdAt`, `uid` bound to the caller's own token or absent — App Check is the volume/bot control, not the rule | `firestore.rules` inline comments explain the design; rule itself untested (§3); `sanitize.test.js`/`notify_discord.test.js` cover the Cloud Function side |
| Secrets | `android/key.properties` gitignored, never committed (`AGENTS.md`); no API keys are hardcoded — Firebase config files (`google-services.json`, `GoogleService-Info.plist`) are the standard client-safe config, not secrets | Manual: `git log -p -- android/key.properties` should return nothing; not automated |
| Auth provider disconnect | The last remaining sign-in provider cannot be disconnected (would strand the account) | `settings_account_test.dart` |
| App Check | Gates production Firestore/Storage/Functions traffic from non-app callers | Not exercised in tests by design — it's a production network control, not app logic |
| Third-party data flow | No analytics/crash SDKs beyond Firebase Analytics/Crashlytics/Performance; no ad SDKs; no donation link or other outside payment page (`AGENTS.md` Design Constraints) | Manual audit of `pubspec.yaml` dependencies; `settings_support_section_test.dart` pins the Settings support section to feedback only |

No secrets scanning or dependency-vulnerability scanning runs in CI today (§11-P3 lists
`dart pub outdated --mode=null-safety` / `npm audit` as a cheap addition for `functions/`).

---

## 9. Accessibility

Scope: Dynamic Type / system font scaling, VoiceOver (iOS) / TalkBack (Android), color
contrast, and touch-target sizing, per the Design Constraints in `AGENTS.md`.

| Check | Expected | Status |
|---|---|---|
| System font scaling | UI reflows without clipping or overlap up to at least the largest standard Dynamic Type / Android font-scale setting | Manual only — no `MediaQuery(textScaler:)` golden tests exist (§11-P2) |
| VoiceOver / TalkBack | Every interactive element (buttons, form fields, swipe-to-archive, drag handles) has a meaningful semantics label; swipe-to-archive in particular needs a non-gesture alternative for screen-reader users | Manual only; **not currently scripted anywhere** (§11-P1 — swipe-only actions are the classic a11y gap) |
| Touch targets | ≥48dp (Android) / ≥44pt (iOS) on every tappable element, including icon-only buttons (app bar icons, drag handles, color swatches) | Manual (§6.9); no automated `tester.getSize()` assertions in widget tests today |
| Color contrast | Tag chips (custom color + hash-fallback palette), archive-thumbnail title overlay gradient, and the sepia/cream splash background all meet WCAG AA against their backgrounds | Never measured; §11-P2 proposes a one-time manual contrast-checker pass per palette, not per-release |
| Reduced motion | Splash draw-on and drag-reorder animations respect `MediaQuery.disableAnimations` / iOS Reduce Motion | Not implemented or tested — **gap**, §11-P3 |
| Localization readiness | All user-facing strings route through `app_en.arb` (English-only for V1, but no hardcoded strings) | §6.9 manual check; no automated "no hardcoded string" lint exists (§11-P3) |

Accessibility here is manual-only end to end — there is no CI job that would catch a
regression before release. That gap is real (§11) but proportionate: this is a one-developer
app pre-scale, and the cheapest next step (§11-P1) is adding semantics-label assertions to
the widget tests that already exist, not standing up a new tool.

---

## 10. Release Checklist

What CI actually runs today (`.github/workflows/ci.yml`, two jobs) vs. what a human must do
before shipping.

### 10.1 CI-enforced (blocks merge to `main` via required checks)
- [ ] `dart analyze` — zero issues
- [ ] `dart format --set-exit-if-changed .` — no formatting diffs
- [ ] `flutter test` — full Dart/Flutter suite green (§2.1/§2.2 list what it runs)
- [ ] `npm test` in `functions/` — TypeScript compiles, `sanitize`/`notify_discord` tests green

### 10.2 Manual, required before every release
- [ ] Full pass of §6 relevant to what changed (not necessarily every checkbox every time — see §11 for a proposed smoke subset)
- [ ] iOS: build and run on the Simulator; Camera and multi-select photo flows verified on a **physical device** (§6.4, §6.5 NOTE)
- [ ] Android: `flutter build apk --release -PrequireReleaseSigning=true` succeeds locally with a real `key.properties` — release signing is not exercised in CI (`AGENTS.md`)
- [ ] Android: **install and launch on a physical device** — never done for this project (`AGENTS.md`); this is the top release risk and belongs on every release's checklist until it's finally verified once
- [ ] Firebase Console: confirm no unexpected quota pressure against Spark's 1GB Firestore / 5GB Storage / 50K reads / 20K writes-per-day ceilings
- [ ] `pubspec.yaml` `version` bumped (Settings screen reads it directly, §6.7)
- [ ] `docs/android-release.md` steps followed for anything Play-console-side (this doc doesn't duplicate them)
- [ ] Portrait-lock declarations still agree between `ios/Runner/Info.plist` and `android/.../AndroidManifest.xml` (`AGENTS.md` — two sites, must move together)
- [ ] Frozen dependencies (Firebase, `go_router`, `google_sign_in`, `sign_in_with_apple`, `flutter_secure_storage`, Riverpod, `sqlite3`) still untouched, or the freeze was deliberately lifted with Android verified first (`AGENTS.md`)

### 10.3 Not currently checked anywhere (candidates for §11)
- [ ] Automated Android build-and-boot in CI
- [ ] `firestore.rules`/`storage.rules` test coverage
- [ ] Coverage percentage tracked or gated

---

## 11. Gaps & Prioritized Backlog

Priority is risk × how cheap the fix is, not just severity. Each item names the file(s) it
touches so it's pickup-ready; none of this is implemented in this PR (docs-only, per the
brief — this is the backlog the plan promised instead).

### P0 — highest risk, should be next
| Gap | Risk | Effort |
|---|---|---|
| `configureSqlCipher`'s call site in `AppDatabase.open()` (`lib/database/database.dart`) has no test — only `assertSqlCipherBacksSqlite3` itself is unit-tested (`sqlcipher_guard_test.dart`). A regression here means the app silently writes plaintext. `AGENTS.md` already flags this as needing "a real SQLCipher-backed database" to cover. | High — this is the exact failure mode the whole guard exists to prevent, on the one path that isn't covered | Medium — needs an integration-style test that opens a real `AppDatabase` (not just the pragma probe) and asserts the on-disk file is unreadable without the key |
| The key migration's native half (`docs/local-database-key.md`, last section) has only been verified by reading the plugin's 9.2.4 Swift: that a write under `first_unlock_this_device` replaces the `unlocked` item, and that the item is then excluded from an encrypted backup restore. The Dart decision logic is fully tested; the keychain is not. | High — if the replace does not happen, the key silently keeps travelling in backups (the finding stays open); if the exclusion does not, the recovery screen is never exercised in the field | Medium, manual — one iPhone updated from 1.2.x (marker set, database opens), then an encrypted backup restored onto a second device (recovery screen appears, passphrase path opens the pottery), then Sign Out & Erase and relaunch (the rekeyed, empty database opens with no recovery screen — plain sqlite3 ignores `PRAGMA rekey`, so `sync_service_test.dart` pins only the statement order). Must precede the Android release, which ships the same code |
| Android has never run on a physical device or emulator; nothing in CI builds or boots the AAB (`AGENTS.md`). | High — release-blocking; unknown-unknown risk in the encrypted-DB path specifically | Large — needs actual device/emulator access, likely a manual one-time verification before it can even become a repeatable check |
| `account_switch_test.dart`'s `settle()` helper (lines 50–54) polls a **real** wall clock (`Future<void>.delayed(1ms)` × 50) rather than `fakeAsync`, to let the debounced sync chain finish. Under CI load or a slow machine this is a plausible source of flake in the project's single largest and most safety-critical test file (49 cases). | Medium-high — a flaky test in the account-switch guard erodes trust in exactly the suite `AGENTS.md` calls the "end-to-end guard" | Medium — migrating to `fakeAsync`/`FakeAsync.run` would need every `await` in the chain to be compatible with synchronous time control, which the debounce-heavy sync path may not tolerate cleanly; needs a spike first |

### P1 — real gap, moderate effort
| Gap | Risk | Effort |
|---|---|---|
| `firestore.rules` (feedback allowlist, per-user scoping) and `storage.rules` have zero automated coverage — only the Cloud Function side is tested. | Medium — a rules regression ships straight to production with nothing catching it pre-deploy | Medium — Firebase Emulator Suite + `@firebase/rules-unit-testing`; new toolchain for this repo |
| Swipe-to-archive has no non-gesture alternative and no accessibility test — a screen-reader user may not be able to archive a piece at all. | Medium — accessibility regression, silent | Small–medium — add a long-press or menu fallback action, then a widget test asserting it's reachable via semantics |
| No `integration_test/` smoke suite (auth-skip → create piece → edit → archive) runnable on iOS Simulator in CI. | Medium — the only thing standing between "all unit tests pass" and "the app actually opens" is a human | Medium — new dependency, new CI job, but scoped narrowly (§5) |

### P2 — worth doing, lower urgency
| Gap | Risk | Effort |
|---|---|---|
| No portrait-lock consistency check between `Info.plist` and `AndroidManifest.xml` — `AGENTS.md` documents the two sites must move together, but nothing enforces it. | Low-medium — regression already happened once (`ceb5d3d`) | Small — a script asserting both files' orientation keys, run in CI or as a pre-commit check |
| No dynamic-type / font-scale golden tests. | Low-medium | Small–medium |
| No color-contrast verification, even one-time, for tag chip palette or splash sepia background. | Low | Small |
| No widget tests for piece-detail screen, Manage Clays/Glazes/Tags screens, or the photo-reorder screen — pure manual coverage today. | Medium (piece-detail is the highest-traffic screen) | Medium — largest of the "add tests" items, worth splitting per screen |

### P3 — nice to have
| Gap | Risk | Effort |
|---|---|---|
| No coverage percentage tracked (`flutter test --coverage` exists but nothing reads `coverage/lcov.info`). | Low | Small |
| No dependency-vulnerability scan (`dart pub outdated`, `npm audit` for `functions/`). | Low | Small |
| No recorded `flutter build --analyze-size` or cold-launch timing per release. | Low | Small |
| Reduced-motion support for splash/drag animations. | Low | Small–medium |
| No lint against hardcoded user-facing strings bypassing `app_en.arb`. | Low | Medium (custom lint rule) |

---

## 12. Running Everything Headlessly

Everything below runs without a simulator, emulator, or browser — the full set CI runs
today, plus the pieces useful for local iteration.

```bash
# Flutter/Dart app
flutter pub get
dart analyze
dart format --set-exit-if-changed .
flutter test                      # the whole suite (§2.1/§2.2 list every file)
flutter test --coverage           # coverage/lcov.info (not currently read by anything)

# Cloud Functions (feedback sanitiser + Discord webhook contract test)
cd functions && npm ci && npm test
cd ..

# Code generation (not tests, but required before analyze/test after a schema
# or l10n change — run first if either fails with stale-generated-code errors)
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
```

This is exactly the two CI jobs in `.github/workflows/ci.yml` (`analyze-and-test`,
`functions`) plus the codegen steps CI assumes are already committed. There is no headless
path for §5/§6/§9's manual and device-only checks, or for §11-P1's proposed
`integration_test/` suite — those, by nature, need a Simulator, an emulator, or a physical
device, which is exactly why they're catalogued separately rather than folded in here.

---

## Changelog

| Date       | Change |
|------------|--------|
| 2026-02-12 | Initial test plan created covering all Phase 1 features |
| 2026-02-12 | Photo gallery redesign: PageView → horizontal ListView, 1:1 photos at 72% width, fade gradients |
| 2026-02-12 | Photo ordering: newest first (sortOrder DESC) in detail, album row, and archive |
| 2026-02-12 | Archive navigates back to home |
| 2026-02-12 | Archive thumbnails: 1:1 square, photo-only (title removed) |
| 2026-02-12 | Untitled piece auto-numbering: "Untitled Piece N" with lowest available number |
| 2026-02-12 | Detail redesign: title above gallery, archive/trash icon buttons replace overflow menu, darker sepia background |
| 2026-02-12 | Editable "last updated" date: album rows show updatedAt, detail screen date is tappable with date/time picker |
| 2026-02-12 | Haptic feedback: light on add photo, delete photo, archive; medium on delete piece; light on piece creation |
| 2026-02-12 | Photo date labels: dateTaken shown below each photo in detail gallery |
| 2026-02-12 | Batch photo upload: "Select Multiple" option, progress dialog, per-photo error handling |
| 2026-02-12 | Photo reordering: drag-to-reorder screen with Done button, batch sort order update |
| 2026-02-12 | Clay dropdown: replaced free-text clay field with single-select dropdown + "+ Add New" + clay options library (DB v3) |
| 2026-02-12 | Manage Clays: settings screen to add, edit, and delete saved clay options |
| 2026-02-13 | Clay reordering: drag-to-reorder in Manage Clays, sortOrder column (DB v4), custom order in clay picker |
| 2026-02-13 | Glaze library: multi-select picker replaces free-text field, GlazeOptions + PieceGlazes tables (DB v5), migration parses existing glazes |
| 2026-02-13 | Manage Glazes: settings screen to add, edit, delete, and reorder saved glaze options |
| 2026-02-13 | Clay/glaze rename propagation: renaming in Manage Clays/Glazes updates all pieces using that name |
| 2026-02-13 | Tags: multi-select picker, TagOptions + PieceTags tables (DB v6), Manage Tags screen with drag-to-reorder, tag rename propagation, search integration |
| 2026-02-14 | Custom tag colors: 7 preset swatches, auto-assign on creation, color picker in Manage Tags, accessible chip rendering in album view (DB v7) |
| 2026-02-14 | Untitled piece title as hint: title field empty for new pieces, "Untitled Piece N" shown as placeholder hint, DB value preserved when field left empty |
| 2026-02-14 | Input field UX cleanup: TextCapitalization.sentences on all inputs, autocorrect disabled, "Add New" button text de-duplicated |
| 2026-02-14 | Swipe-to-archive: left-swipe on album rows with teal background, haptic feedback, and 4-second undo snackbar |
| 2026-02-14 | Archive thumbnail titles: bottom-right title overlay with gradient fade on archive grid thumbnails |
| 2026-02-14 | Widget tests added covering album screen, filter chips, album grid, archive thumbnails, empty state, and settings; run `flutter test` to execute them |
| 2026-02-14 | Firebase Analytics & Crashlytics: 11 custom events, auto screen tracking, crash reporting with test crash button |
| 2026-05-09 | In-app review prompt + feedback form |
| 2026-07-28 | Splash logo draw-on: animated vase mark on cream, router holds /splash until the stroke finishes (3s fallback), native launch screens matched to cream, app icon regenerated from the same path |
| 2026-08-18 | Sign-out erases this device's local data behind a "Sign Out & Erase" confirmation, an unfinished wipe pauses backup until it completes, the last remaining sign-in provider cannot be disconnected, and the feedback reply email is capped at 254 characters |
| 2026-08-19 | A device still holding another account's pottery is locked read-only at `/device-locked`: no route that can write is reachable, and the only ways out are the owner signing back in or a confirmed erase |
| 2026-09-02 | Restructured around the 12-section testing-plan framework (strategy/pyramid, unit, integration/contract, regression catalog, E2E, manual — folded in unchanged, performance, security, accessibility, release checklist, gaps backlog, headless run guide); no test behavior changed, docs only |
| 2026-09-04 | Database key hardened to `first_unlock_this_device` / Android OAEP+GCM with a marker-verified migration; a restored database with no key gets a pre-app recovery screen (passphrase unlock, cloud re-download keeping photos, or confirmed start-fresh); transfer passphrase in Settings on iOS (Android keeps every domain out of cloud backup and device transfer via `dataExtractionRules` and says plainly that local-only pottery does not move); the hardening rewrite keeps a migrating copy so a crash mid-rewrite loses no key and never writes the key back under `unlocked`; a pre-unlock iOS launch fails and retries instead of deciding recovery; the database is rekeyed at Sign Out & Erase (a rotation that died after its copy landed is finished by the next launch; a failed rekey never quotes the key); the transfer backup replaces atomically and its "set" state is the file itself; every exit from recovery settles an owed wipe restored with the preferences. 121 test cases added |
| 2026-09-09 | Sync no longer clears the push queue when it completes: only entries whose push was acknowledged leave it, a push acknowledges only the revision it read, and a debounce that expired while a sync was running is repaid once that sync ends — so an edit made while a sync runs stays pending and is uploaded instead of being silently dropped. 7 test cases added |
| 2026-09-09 | A successful first/full sync now retires the exact revision-scoped queue snapshot its bulk upload delivered, while preserving writes made during the sync; the next edit no longer replays that snapshot or re-uploads its photo files. Queued deletions are not part of that snapshot — a bulk upload of existing rows sends no tombstone — so they are still pushed, before the pull that would otherwise bring the deleted pottery back. 4 regression cases added and 1 existing case strengthened |
| 2026-09-09 | Upgrading a database at schema version 5 or lower no longer throws `duplicate column name: color`: the tag-colour `addColumn` step is guarded to the one version range that needs it, the way the clay `sort_order` step already was. The clay `sort_order` backfill, which only ran when upgrading from exactly 3, now runs for every database below 4, so a v1/v2 upgrade no longer lands its whole clay library on `sort_order` 0. Every historical schema version now has a checked-in DDL fixture and is walked to the current version through the real `MigrationStrategy` — the project's first migration test, and it fails if a fixture is ever missing. 11 test cases added |
