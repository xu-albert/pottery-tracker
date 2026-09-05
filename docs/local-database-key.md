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
2. Otherwise rewrite the key under the pinned options: an explicit delete with **no**
   accessibility in the query (so it matches the item whatever it was stored under), then an add.
   `kSecAttrAccessible` cannot be changed in place, and the plugin's own write only deletes after a
   `SecItemUpdate` naming the *new* accessibility fails to match — deleting first removes the
   dependence on that query semantics. On Android the plugin re-encrypts on a cipher change. Both
   are idempotent.
3. Read back. Matches → write the marker (best effort). Does not match, or the write threw →
   write the key back under the **legacy** options (`unlocked`) so the device is no worse off,
   leave the marker unset so the next launch retries. If even that does not read back →
   `KeyStorageException` and the launch stops: proceeding with the in-memory key would let the
   user add pottery no later launch can read.

Then the database is opened and probed with one statement (`SELECT count(*) FROM sqlite_master`), so
a key that does not decrypt the file fails *here*, distinguishable, rather than on the album's
first query. The `setup: configureSqlCipher` guard call site stays in `AppDatabase.open(file, key)`
untouched.

## New phone: the three restore scenarios

A backup restore brings `Documents/` — database, photos, and (if set) the transfer backup — and
`NSUserDefaults` (the owner stamp, watermarks, the sign-in flag). It does **not** bring the key.
`launch()` finds a database file and no key and returns `LocalDatabaseUnreadable`; `main` runs
`DatabaseRecoveryScreen` *before* the app, outside its providers and router, and only hands over a
database once one can actually be opened. Nothing is ever created over the user's file.

| Restored device has… | User class | What the user sees | What happens |
|---|---|---|---|
| database + **transfer backup** | either | "This phone can't open your pottery journal" with the backup explanation, a passphrase field and **Unlock** (primary). Wrong passphrase → inline "That passphrase doesn't match." | `TransferKeyBackup.read(passphrase)` unwraps the key; the database is opened and probed with it *first*, then the key is stored under the pinned options. Everything is in place — stamp, sign-in flag, photos. Next launch is ordinary. |
| database + **owner stamp**, no backup | cloud-sync | Same title; "This journal was backed up to an account. Sign in with it and your pieces are downloaded again; the photos already on this phone are kept." **Sign in and download again** (primary) behind a non-destructive confirmation. | `redownloadFromCloud()`: delete the database and its `-wal/-shm/-journal`, the transfer backup, the owner stamp, the contested flag, every `lastPulledAt_*` watermark (else the next pull is incremental and skips everything) and the sync queue; set `hasCompletedOnboarding=false` so the router lands on sign-in; create a key, open empty. **Photo files are kept**: `pullAll` downloads only photos whose `localPath` is missing, so the restored files are reused. |
| database only, **no stamp, no backup** | local-only | Same title; "This journal was kept on the old phone only and never signed in, so there is no cloud copy to download. Without its transfer passphrase, its pieces can't be recovered here." Only **Start fresh without them**, red, behind a destructive confirmation that names the one remaining way out (set a passphrase on the old phone, back up again). | `startFresh()`: as above, plus the `photos/` directory and the image-picker temp files. Reported if it fails; never silent. |

A key that is present but does not decrypt the file (`keyMismatch`, rare) reaches the same screen
with a different first paragraph and the same options. Ownership state is never touched by the
passphrase path, and the persisted lock inputs (`localDataOwnerUid`, `localDataContested`,
`pendingLocalDataWipe`) are cleared only by the two discard paths, consistent with
`SyncService.deleteLocalData`.

## The migration path for local-only users: a transfer passphrase

Of the three options considered — (a) an export/import flow, (b) a backup-restorable wrapped copy of
the key protected by something the user knows, (c) a one-time warning only — this ships **(b), with
(c) as its on-ramp**.

- (c) alone does not meet the ruling: a warned user still loses the database. It is kept as the
  way users learn the passphrase exists: a one-time dialog ("Moving to a new phone someday?") the
  first time a local-only user opens the app with at least one piece, pointing at Settings, plus a
  permanent explanation in Settings › *Moving to a new phone*.
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

Settings › *Moving to a new phone* › **Transfer passphrase**: set / change / remove, with the
threat model in the sheet text. State is `transferPassphraseSetProvider`, seeded from the file
before `runApp`.

## Deliberately not changed

- `flutter_secure_storage`, `sqlite3`, `drift`, Firebase, Riverpod: frozen, untouched. Two
  packages that already resolved transitively (`flutter_secure_storage_platform_interface`,
  `plugin_platform_interface`) became direct **dev** dependencies so tests can install a fake
  platform; the lockfile changed only their dependency kind.
- The `setup: configureSqlCipher` call site in `AppDatabase.open` — only its signature gained
  `(file, key)`; the call is the same statement.
- `sync_provider.dart`: untouched. `sync_service.dart` gained one line (delete the transfer backup
  in `deleteLocalData`) and a public constant for the watermark prefix. `sync_queue.dart` and
  `auth_provider.dart` each made one private constant public so the bootstrap can clear them.
- The duplicate-column migration step (separate task), photo encryption at rest (L3, separate
  decision), `NSURLIsExcludedFromBackupKey` on the database (the design *relies* on the database
  being backed up).
- The database key is not rotated anywhere — not on wipe, not on recovery.

## What headless verification cannot cover

Real keychain behaviour — that the delete-then-add lands the item under
`first_unlock_this_device`, and that the item is then absent from a restore — is native iOS
behaviour exercised only on a device. The plugin's Swift for 9.2.4 was read (a delete with no
accessibility in its query matches the item under any; an add creates it under the one given), and
the service verifies by read-back with a legacy fallback, but the first release carrying this
should be checked once on a real iPhone: update from 1.2.x, confirm the marker is set and the
database opens; then an encrypted backup restore onto a second device, confirming the recovery
screen appears and the passphrase path opens the pottery. The Android path has never run on a
device at all (see `AGENTS.md`).
