# The local database key: where it lives, and what a phone backup carries

The local SQLite database is SQLCipher-encrypted. This documents how its key is stored, why
that storage was hardened, and how a user moving to a new phone keeps a readable database.
The code is the authority — `lib/services/encryption_key_service.dart`,
`lib/database/local_database_bootstrap.dart`, `lib/database/transfer_key_backup.dart` — this is
the map.

## What changed and why

Security review findings M6 and L2 (2026-08). The key was stored with `FlutterSecureStorage()`
platform defaults:

- **iOS:** `kSecAttrAccessibleWhenUnlocked`. Not iCloud-synced (`synchronizable: false`, correct),
  but *migratable*: it travels in an encrypted device backup. The database lives in `Documents/`
  and is backed up too, so a backup carried both halves of the encrypted store together.
- **Android:** `encryptedSharedPreferences: false` with the legacy RSA/ECB/PKCS1 + AES/CBC KeyStore
  path. `allowBackup="false"` already blocks the backup vector; the ciphers were simply old.

The captain's ruling (2026-08-18, `keychain-device-migration`): harden to
`first_unlock_this_device` **and** build a migration path so a restore onto a new phone keeps a
readable database, covering local-only users; cloud-sync users re-pull. Land before the Android
release, because changing the storage backend after release strands existing keys.

### Pinned options (`EncryptionKeyService`)

| Platform | Option | Value | Why |
|---|---|---|---|
| iOS | `accessibility` | `first_unlock_this_device` | `ThisDeviceOnly` keeps the item out of every backup. `first_unlock` rather than `unlocked` because the database opens at launch, and a launch can be a background one on a locked screen. |
| iOS | `synchronizable` | `false` | No iCloud Keychain. Was the default; pinned so a default change cannot flip it. |
| Android | `encryptedSharedPreferences` | `false` | Jetpack `EncryptedSharedPreferences` is deprecated upstream; the plugin's own KeyStore path re-encrypts existing values itself when its ciphers change. |
| Android | `keyCipherAlgorithm` | `RSA_ECB_OAEPwithSHA_256andMGF1Padding` | Modern wrap. `minSdk` 24 ≥ the API 23 floor, so the plugin never falls back. |
| Android | `storageCipherAlgorithm` | `AES_GCM_NoPadding` | Authenticated encryption for the stored value. |

Every call passes these explicitly; the default `FlutterSecureStorage` instance carries them too.
`flutter_secure_storage` stays at 9.2.4 (frozen); the native code of that version was read to
confirm the behaviours relied on below.

## Same phone, first launch after the update

`LocalDatabaseBootstrap.launch()` reads the key (reads ignore accessibility on iOS, so a key stored
under `unlocked` is found), then `hardenStoredKey`:

1. A marker (`db_encryption_key_storage_version` = `2`, itself in secure storage) says whether the
   key was last written under the pinned options. Present → nothing to do.
2. Otherwise write a **migrating copy** of the key first (`db_encryption_key_migrating`, under
   the pinned options) and read it back. Only then rewrite the key itself: an explicit delete
   with **no** accessibility in the query (so it matches the item whatever it was stored under),
   then an add. `kSecAttrAccessible` cannot be changed in place, and the plugin's own write only
   deletes after a `SecItemUpdate` naming the *new* accessibility fails to match — deleting first
   removes the dependence on that query semantics. The copy is why the instant between the delete
   and the add is survivable: a process that dies there (crash, jetsam, force-quit) leaves the
   copy, `readKey` falls back to it, and the next launch finishes the rewrite. A copy that does
   not read back leaves the key where it was — without it the rewrite would have no safety net.
   On Android the plugin re-encrypts on a cipher change. All of it is idempotent.
3. Read back. Matches → delete the copy, then write the marker (best effort, and never before the
   copy is gone, or a launch that trusts the marker would leave it behind). Does not match, or
   the add threw → the copy, itself under the pinned options, is what the device keeps, and the
   marker stays unset so the next launch tries again; nothing is ever written back under the old
   `unlocked` protections. `KeyStorageException` stops the launch only if neither the item nor
   the copy reads back: proceeding with the in-memory key would let the user add pottery no
   later launch can read.

Before any of that, a launch that finds *no* key confirms the keychain is actually open. Before
the first unlock after a restart — when iOS may prewarm the app — every item is inaccessible and
the plugin reports it as absent, which is not "no key". `readKey` checks protected-data
availability (`isCupertinoProtectedDataAvailable`) whenever it is about to answer null and throws
`KeyStoreUnavailableException` instead, so the launch fails to the retry screen rather than
deciding the database has no key and offering to delete it.

Then the database is opened and probed with one statement (`SELECT count(*) FROM sqlite_master`), so
a key that does not decrypt the file fails *here*, distinguishable, rather than on the album's
first query. The `setup: configureSqlCipher` guard call site stays in `AppDatabase.open(file, key)`
untouched.

## New phone: the three restore scenarios

An iOS backup restore brings `Documents/` — database, photos, and (if set) the transfer backup —
and `NSUserDefaults` (the owner stamp, watermarks, the sign-in flag). It does **not** bring the key.
(Android restores nothing of the app's: see *Android* below.)
`launch()` finds a database file and no key and returns `LocalDatabaseUnreadable`; `main` runs
`DatabaseRecoveryScreen` *before* the app, outside its providers and router, and only hands over a
database once one can actually be opened. Nothing is ever created over the user's file.

| Restored device has… | User class | What the user sees | What happens |
|---|---|---|---|
| database + **transfer backup** | either | "This phone can't open your pottery journal" with the backup explanation, a passphrase field and **Unlock** (primary). Wrong passphrase → inline "That passphrase doesn't match." | `TransferKeyBackup.read(passphrase)` unwraps the key; the database is opened and probed with it *first*, then the key is stored under the pinned options. Everything is in place — stamp, sign-in flag, photos. Next launch is ordinary. |
| database + **owner stamp**, no backup | cloud-sync | Same title; "This journal was backed up to an account. Sign in with it and your pieces are downloaded again; the photos already on this phone are kept. Changes the old phone never finished backing up are lost." **Sign in and download again** (primary) behind a non-destructive confirmation that repeats the unsynced-change loss. | `redownloadFromCloud()`: delete the database and its `-wal/-shm/-journal`, the transfer backup, the owner stamp, the contested flag, every `lastPulledAt_*` watermark (else the next pull is incremental and skips everything) and the sync queue; set `hasCompletedOnboarding=false` so the router lands on sign-in; create a key, open empty. **Photo files are kept**: `pullAll` downloads only photos whose `localPath` is missing, so the restored files are reused. |
| database only, **no stamp, no backup** | local-only | Same title; "This journal was kept on the old phone only and never signed in, so there is no cloud copy to download. Without its transfer passphrase, its pieces can't be recovered here." Only **Start fresh without them**, red, behind a destructive confirmation that names the one remaining way out (set a passphrase on the old phone, back up again). | `startFresh()`: as above, plus the `photos/` directory and the image-picker temp files. Reported if it fails; never silent. |

A key that is present but does not decrypt the file (`keyMismatch`, rare) reaches the same screen
with a different first paragraph and the same options. Ownership state is never touched by the
passphrase path. Both discard paths clear `localDataOwnerUid` and `localDataContested`, consistent
with `SyncService.deleteLocalData`. `pendingLocalDataWipe` — an erase the old phone's owner
confirmed and never got, restored with the preferences — is cleared by *every* exit from recovery,
the passphrase unlock included. Each of them leaves the user with a database they chose, and the
lock screen would otherwise retry that erase without asking anything — over the journal the
passphrase just unlocked, or over the photo files **Sign in and download again** deliberately
keeps for the pull.

## The migration path for local-only users: a transfer passphrase

Of the three options considered — (a) an export/import flow, (b) a backup-restorable wrapped copy of
the key protected by something the user knows, (c) a one-time warning only — this ships **(b)**.

- (c) alone does not meet the ruling: a warned user still loses the database. The explanation
  lives permanently in Settings › *Moving to a new phone*, next to where the passphrase is set;
  there is no one-time dialog.
- (a) is the largest surface (a portable format including photos, share-sheet export, import
  parsing) and solves a different problem; it can be added later without touching this design.
- (b) is the smallest change that keeps the ruling's promise and adds **no dependency**: the wrap
  is SQLCipher itself. `TransferKeyBackup` writes a second SQLCipher database,
  `Documents/pottery_tracker_transfer_key.db`, holding one row with the database key, keyed with the
  user's passphrase — SQLCipher derives the file key with PBKDF2-HMAC-SHA512 (256,000 rounds in
  SQLCipher 4) and authenticates every page. It is opened through `configureSqlCipher`, so on a
  build where SQLCipher did not load it refuses rather than writing the key in the clear. It is
  written only when the user sets a passphrase, so a user who never does has nothing extra on disk.

**Threat model, stated plainly:** the backup file protects the key exactly as well as the passphrase
resists an offline guess by whoever holds the device backup. Hence the 8-character floor
(`TransferKeyBackup.minPassphraseLength`) and settings copy that asks for a phrase, not a PIN. A
user who sets a weak passphrase has chosen a weaker posture than the hardened default — knowingly,
and only for their own local-only data. Sign-out (`deleteLocalData`) and both discard paths delete
the file, so the next account on the device does not inherit a backup a passphrase they do not know
can open.

**Rotation at erase.** The transfer file wraps whatever key the database had when it was written,
and a backup taken while the file existed keeps a copy of it after `deleteLocalData` has deleted
the original. Were the key never rotated, the next person on this device would be writing pottery
under a key the previous owner's passphrase still unwraps. So `deleteLocalData` rekeys the emptied
database in place (`AppDatabase.rekey`, `PRAGMA rekey`) and then stores the fresh key, in that
order. If the store fails, the file is keyed back and the old key stored again. A process that
dies in between leaves the file at the new key: once the store's migrating copy has landed, the
next launch finds that the stored key does not open the file, probes the copy, and finishes the
store (`LocalDatabaseBootstrap`); before the copy lands — the instant after the rekey — the
launch is a key mismatch over an *empty* database, where Start fresh costs nothing and clears the
owed erase. Every way the rotation can end with the old key still on the file — an unreadable key
store, a rekey sqlite3 refuses, a key-back after a store that failed, whether or not that key-back
itself worked — is reported the same way, because they leave the same state. The data is gone
either way, so it is never "nothing was deleted": the erase stays owed as *erased but not
secured*, and its retry rotates again. A transfer backup that will not delete is reported the same
way, even when the rotation worked and the copy that outlived the wipe unwraps nothing: that file
is what Settings reads to decide a passphrase is set, and only the erase ever removes it. No
error from that path quotes a key (`keyingFailure`, shared with `configureSqlCipher`), and
neither key ever enters a backup.

Settings › *Moving to a new phone* › **Transfer passphrase** (iOS): set / change / remove, with
the threat model in the sheet text. Whether one is set is read from the file itself, by the tile
and by the sheet, so nothing goes stale when an erase deletes it. A replacement is written to a
sibling temp file and renamed over the old one only once the key is inside, so a change that
fails partway keeps the previous passphrase working.

### Android

There is no transfer passphrase on Android, because nothing of the app's leaves the phone in a
backup or a transfer. `android:allowBackup="false"` keeps it out of Google Drive backups. That
alone is not enough on Android 12+: on some manufacturers' devices `allowBackup="false"` does
**not** disable device-to-device transfer, which would carry the whole data directory —
`app_flutter/pottery_tracker.db` *and* `shared_prefs/FlutterSecureStorage.xml` — to the new phone.
So `android:dataExtractionRules` (`res/xml/data_extraction_rules.xml`) excludes every domain the
backup agent walks from both `<device-transfer>` and `<cloud-backup>`, and
`test/android/data_extraction_rules_test.dart` pins that no domain is ever dropped from either.

Should a data directory reach another device anyway (a manufacturer's cloning tool that bypasses
the backup framework), the plugin cannot decrypt the stored key: its storage key is wrapped by a
KeyStore key that never leaves the device, and reading the value throws. On Android,
`EncryptionKeyService` reports that one failure as *no key* — the plugin reports every error under
a single code, so it is told apart by the `AEADBadTagException` the GCM decrypt raises — and the
launch lands on the recovery screen, where a restored iOS database goes, rather than on a launch
failure whose retry fails the same way forever; the next write replaces the value and reads back.
Any other read failure propagates to the launch-failed screen and its retry, as on iOS, where a
read error is a keychain state, not a verdict on the item. The screen says it in Android's own
terms — nothing was restored from a backup there, so its copy names the key this phone's secure
hardware no longer reads, and it never offers the passphrase.

The passphrase tile is behind `Platform.isIOS`; on Android the *Moving to a new phone* section
states plainly that pottery kept only on this phone does not move, and that signing in is what
carries it. Opting the files into Android backup was considered and declined: it would reopen
the vector the manifest closes, for a path Android users have never had.

## Deliberately not changed

- `flutter_secure_storage`, `sqlite3`, `drift`, Firebase, Riverpod: frozen, untouched. Three
  packages that already resolved transitively became direct **dev** dependencies —
  `flutter_secure_storage_platform_interface` and `plugin_platform_interface`, so tests can
  install a fake platform, and `xml`, so the Android backup rules are parsed rather than
  grepped; the lockfile changed only their dependency kind.
- The `setup: configureSqlCipher` call site in `AppDatabase.open` — only its signature gained
  `(file, key)`; the call is the same statement.
- `sync_provider.dart` changed only in what it hands `SyncService` (the key service).
  `sync_service.dart` deletes the transfer backup and rotates the key in `deleteLocalData`, and
  exposes the watermark prefix. `sync_queue.dart` and `auth_provider.dart` each made one private
  constant public so the bootstrap can clear them.
- The duplicate-column migration step (separate task), photo encryption at rest (L3, separate
  decision), `NSURLIsExcludedFromBackupKey` on the database (the design *relies* on the database
  being backed up).
- The database key is rotated only at erase (above) — never on recovery, never on a launch.

## What headless verification cannot cover

Real keychain behaviour — that the delete-then-add lands the item under
`first_unlock_this_device`, and that the item is then absent from a restore — is native iOS
behaviour exercised only on a device. The plugin's Swift for 9.2.4 was read (a delete with no
accessibility in its query matches the item under any; an add creates it under the one given), and
the service verifies by read-back with a migrating copy, but the first release carrying this
should be checked once on a real iPhone: update from 1.2.x, confirm the marker is set and the
database opens; then an encrypted backup restore onto a second device, confirming the recovery
screen appears and the passphrase path opens the pottery; then Sign Out & Erase and relaunch,
confirming the rekeyed, empty database opens with no recovery screen — plain sqlite3 ignores
`PRAGMA rekey`, so the tests pin only the statement order and the key-back, never that SQLCipher
rekeys the live keyed connection in place. The Android path has never run on a device at all (see
`AGENTS.md`); whether a given manufacturer's device-to-device transfer honours
`dataExtractionRules` is likewise only observable on two real devices.
