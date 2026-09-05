# Android release — console-side checklist

Everything on the **engineering** side of an Android release is in the repo. Everything below needs
a human with account access: a keystore that must never be committed, the Firebase console, and the
Google Play Console.

Work through the sections in order — later ones depend on earlier ones. Each step says who can do it
and what it unblocks.

---

## 0. What the repo already does for you

| Thing | State | Where |
|---|---|---|
| `applicationId` | `com.potterytracker.pottery_tracker` — **permanent once published** | `android/app/build.gradle.kts` |
| `minSdk` / `targetSdk` | 24 / 36, inherited from the Flutter SDK | `android/app/build.gradle.kts` |
| Manifest hardening | `allowBackup="false"`, `usesCleartextTraffic="false"`, network security config | `android/app/src/main/AndroidManifest.xml` |
| Portrait lock | `userPortrait` + restricted-resizability opt-out | see "Design Constraints" in `AGENTS.md` |
| Release signing | reads `android/key.properties` if present, falls back to the debug key with a warning | `android/app/build.gradle.kts` |
| Firebase Gradle plugins | `google-services`, `crashlytics`, `firebase-perf` all applied | `android/app/build.gradle.kts` |
| App Check provider | `AndroidProvider.playIntegrity` in release, `debug` in debug | `lib/main.dart` |
| Native 16 KB page-size compliance | satisfied — `libsqlcipher.so` is 16 KB-aligned since `sqlcipher_flutter_libs 0.6.8` | `pubspec.yaml` |

Nothing in this list needs you to do anything. Start at section 1.

---

## 1. Local Android toolchain (this machine, ~30 min)

`flutter build appbundle --release` currently prints:

```
Release app bundle failed to strip debug symbols from native libraries.
```

That is not a blocker, but it inflates the upload. `flutter doctor -v` shows why:

```
[!] Android toolchain - develop for Android devices
    ✗ cmdline-tools component is missing.
    ✗ Android license status unknown.
```

Fix:

1. Install **cmdline-tools**: Android Studio → Settings → Languages & Frameworks → Android SDK →
   SDK Tools tab → check *Android SDK Command-line Tools (latest)* → Apply.
2. Accept licenses: `flutter doctor --android-licenses`
3. Install **NDK 28.2.13676358** (the version Flutter 3.41.1 pins via `flutter.ndkVersion`):
   SDK Tools tab → check *Show Package Details* → NDK (Side by side) → 28.2.13676358.
4. Re-run `flutter doctor -v` and confirm the Android toolchain section is clean.

Do this before producing any artifact you intend to upload.

---

## 2. Generate the upload keystore (~15 min)

> **The keystore and its passwords never go in the repo.** `android/key.properties`, `*.jks` and
> `*.keystore` are gitignored at both the repo root and in `android/.gitignore`. Do not move them
> inside the working tree "just for a second".

### 2.1 Create the key

Run this **outside the repo**:

```bash
mkdir -p ~/keys
keytool -genkey -v \
  -keystore ~/keys/potter-journal-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

`-validity 10000` (~27 years) is deliberate — Google Play requires the upload key to stay valid well
past 2033. It will prompt for a keystore password, a key password, and a distinguished name (your
name / organisation / city / country). Any sensible values are fine; they are not shown to users.

### 2.2 Point the build at it

Create `android/key.properties` (gitignored — verify with `git status` that it does **not** appear):

```properties
storePassword=<the keystore password you just chose>
keyPassword=<the key password you just chose>
keyAlias=upload
storeFile=/Users/<you>/keys/potter-journal-upload.jks
```

`storeFile` may be absolute (recommended) or relative to `android/`.

### 2.3 Verify the build actually picks it up

```bash
flutter build apk --release -PrequireReleaseSigning=true
```

The `-PrequireReleaseSigning=true` flag makes the build **fail** rather than quietly fall back to the
Android debug key. Use it for every artifact you intend to upload. (CI can set the environment
variable `POTTER_JOURNAL_REQUIRE_RELEASE_SIGNING` instead, which does the same thing.)

Both switches fail closed on their **value**: either one counts as **on** whenever it is present in
any form — `-PrequireReleaseSigning` with no value, `=true`, `=1`, `=yes`, `=on`, any casing. Only an
explicit `false`, `0`, `no` or `off` turns strict signing back off, so a mistyped *value* can never
silently downgrade an upload artifact to the debug key.

A mistyped **flag name** is a different matter and the build cannot catch it: Gradle silently ignores
unknown `-P` properties, so `-PrequireReleaseSighing=true` leaves strict signing off and the build
falls back to the debug key. Never treat the flag as proof on its own — the certificate check below
(and `jarsigner -verify` in section 7 for the `.aab`) is what actually confirms an upload artifact is
signed with your key.

The warning and the strict-mode failure apply to release work only. A debug or profile build with no
`key.properties` stays silent, since nothing it produces is uploadable. When the build cannot be
positively identified as debug or profile, it is treated as a release.

Then confirm the certificate is yours and not the debug one:

```bash
apksigner verify --print-certs -v build/app/outputs/flutter-apk/app-release.apk
```

The `Signer #1 certificate DN` must be the name you entered in 2.1 — **not**
`C=US, O=Android, CN=Android Debug`. Play rejects debug-signed uploads outright.

### 2.4 Back it up — this is the irreversible step

Store **both** the `.jks` file and its two passwords somewhere durable (password manager, encrypted
backup). Losing the upload key is recoverable via Google (see 3.3); losing it *without* Play App
Signing enabled is not.

### 2.5 Record the fingerprints — you need them in section 4

```bash
keytool -list -v -keystore ~/keys/potter-journal-upload.jks -alias upload
```

Copy the `SHA1:` and `SHA256:` lines. You will also want the **debug** key's fingerprints for
on-device testing before the app is on a Play track:

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey \
  -storepass android -keypass android
```

---

## 3. Google Play Console

### 3.1 Create the account — start this first, it has unpredictable lag

- US$25, one-time.
- An **individual** account requires government ID verification and a publicly displayed contact
  address; an **organisation** account requires a D-U-N-S number. Which one you pick, and the
  developer name that appears on the listing, is a decision — see section 8.
- Verification can take days. Everything from 3.2 onward is blocked on it.

### 3.2 Create the app

- App name: **Potter Journal**
- Default language, app-or-game, free-or-paid (free).
- The package name is fixed by the repo: `com.potterytracker.pottery_tracker`. It is **permanent for
  the life of the listing** and cannot be changed after the first upload.

### 3.3 Enrol in Play App Signing

Default for new apps — accept it. Google then holds the *app signing key*, and the `.jks` from
section 2 is only the *upload key*. This is the safety property that makes a lost upload key
recoverable.

**Consequence you must not skip:** the certificate users' devices see is Google's app signing
certificate, **not** your upload certificate. Its SHA-1 differs from the one in 2.5, and section 4
needs both.

### 3.4 Upload the first artifact

```bash
flutter build appbundle --release -PrequireReleaseSigning=true
# → build/app/outputs/bundle/release/app-release.aab
```

Play requires an `.aab` (App Bundle) for new apps; it splits per-ABI so a device downloads roughly a
third of the universal APK size. Upload to the **internal testing** track first — not production.

`versionCode` must strictly increase on every upload and can never be reused, even for a build you
immediately discard. It comes from the `+N` in `pubspec.yaml`'s `version:` line, which also drives
the iOS build number. In practice Android leads that counter and iOS follows; never hand-edit it
downward.

---

## 4. Firebase console — register the Android signing certificates

**This is what makes Google Sign-In work on Android.** Right now
`android/app/google-services.json` has an empty `oauth_client` array, which means no signing
certificate has ever been registered for the Android app. Until this is done, Google Sign-In on
Android cannot produce a usable credential.

1. Firebase console → project **pottery-tracker-31b1f** → Project settings → General.
2. Under *Your apps*, select the Android app `com.potterytracker.pottery_tracker`.
3. **Add fingerprint** — add all of these:
   - the **upload key** SHA-1 and SHA-256 from step 2.5,
   - the **debug key** SHA-1 and SHA-256 from step 2.5 (so sign-in works while testing locally),
   - the **Play App Signing** SHA-1 and SHA-256, from Play Console → Test and release → Setup →
     App signing.
4. Download the regenerated `google-services.json` and replace `android/app/google-services.json`
   in the repo. Commit it — it contains no secret; the API key in it is a client identifier, not a
   credential.
5. Confirm the new file's `oauth_client` array is **non-empty** and contains an entry with
   `"client_type": 3` (the web/server client). That entry is what lets Firebase Auth accept the
   Google ID token.

> **Forgetting the Play App Signing fingerprint is the classic failure.** Sign-in works in internal
> testing (upload key) and breaks the moment the app is promoted (app signing key). Add both.

> **Before you run `flutterfire configure`, read this.** `firebase.json` records the iOS app as
> `1:22629038852:ios:f3cd8152c04934a70fae51`, but `lib/firebase_options.dart` uses
> `1:22629038852:ios:21037012b59e03d00fae51` — two different iOS app IDs. iOS ships fine today, so
> `firebase.json` is presumably the stale one, but a `flutterfire configure` run would rewrite
> `firebase_options.dart` to whichever the tool decides is authoritative and could point iOS at the
> wrong Firebase app. Reconcile the two against the Firebase console *first*. The Android IDs are
> already consistent across `firebase.json`, `google-services.json` and `firebase_options.dart`, and
> Android is now listed in `firebase.json`'s `dart.configurations` so a future re-run regenerates it
> instead of dropping it.

Downloading a fresh `google-services.json` by hand (step 4 above) does **not** require running
`flutterfire configure` and does not carry this risk. Prefer the hand download.

**One thing that still needs a device to confirm:** the applied `google-services` Gradle plugin
generates a `default_web_client_id` string resource from the regenerated JSON, and `google_sign_in`
6.x on Android normally picks that up on its own. If sign-in returns a null `idToken` on a real
device, the fix is to pass `serverClientId:` explicitly to the `GoogleSignIn(...)` constructor in
`lib/services/auth_service.dart`, using the `client_type: 3` client ID from the JSON. That cannot be
verified without hardware, so treat it as a device-test item rather than a settled question.

---

## 5. App Check — Play Integrity

The Dart side is already correct (`lib/main.dart` selects `AndroidProvider.playIntegrity` in release
and `AndroidProvider.debug` in debug). **No code change is needed.** The console side is not done:

1. Firebase console → Build → **App Check** → Apps → the Android app.
2. Register the **Play Integrity** provider.
3. Link the Firebase project to the Play Console app (Firebase console → Project settings →
   Integrations → Google Play). Play Integrity cannot verify the app without this link, so do it
   after section 3.2.
4. For pre-Play device testing, register a **debug token**: run a debug build on the device, find the
   token Firebase logs on first launch, and add it under App Check → the Android app → Manage debug
   tokens.

If App Check enforcement is enabled for Firestore or Storage and this is misconfigured, the app will
not crash — `activate()` is wrapped in try/catch and logged as non-fatal — but server-side requests
will be rejected, which presents as a *sync bug*. Check App Check first when sync misbehaves on
Android.

---

## 6. Store listing requirements

| Item | Who | Notes |
|---|---|---|
| **Privacy policy URL** | you | Play requires a publicly hosted URL. None exists yet — see section 8. |
| **Data Safety form** | you | See the declaration notes below. Mismatches get apps pulled. |
| **Content rating** | you | IARC questionnaire, tied to the account. Asks honestly about user-generated content. |
| App icon 512×512 | to export | `assets/icon/icon.png` is 1024×1024. Play requires exactly 512×512 PNG and rejects other sizes, so downscale a 512×512 copy from that source before uploading. |
| Feature graphic 1024×500 | to create | — |
| ≥2 phone screenshots | needs a device | Cannot be produced headlessly. |
| Title, short + full description | to write | — |

**Data Safety — what the app actually collects,** read out of the code, so the form can be filled in
accurately:

- **Account identifiers** — Firebase Auth uid, email, display name.
- **Photos and user content** — piece photos and metadata, in Firestore + Cloud Storage.
- **Diagnostics** — Crashlytics and Performance.
- **Analytics** — Firebase Analytics, **without the advertising ID**. `firebase_analytics` (via
  `play-services-measurement-api`) merges `com.google.android.gms.permission.AD_ID`,
  `android.permission.ACCESS_ADSERVICES_AD_ID` and `android.permission.ACCESS_ADSERVICES_ATTRIBUTION`
  into the manifest by default; `android/app/src/main/AndroidManifest.xml` removes all three with
  `tools:node="remove"` and sets `google_analytics_adid_collection_enabled` to `false` so the SDK
  does not read the ID at runtime either. Decided 2026-08-18: accept reduced Analytics attribution.
  On the form, **do not declare advertising-ID collection**; declare Analytics as app-interaction
  data only.
  Before uploading, confirm the permissions are still absent from the built artifact:

  ```bash
  ~/Library/Android/sdk/build-tools/<version>/aapt2 dump badging \
    build/app/outputs/flutter-apk/app-release.apk | grep uses-permission
  # expect no AD_ID and no ACCESS_ADSERVICES_* lines
  ```

  A `firebase_analytics` upgrade that starts pulling a newer measurement SDK is the usual way one
  of these comes back.
- **Feedback** — free text plus device model, OS version, app version and locale
  (`lib/services/feedback_service.dart`).
- Encryption in transit: **yes**.
- Account deletion: **yes** — the app has a delete-all-data path, which satisfies Play's
  account-deletion requirement.

The app declares **no** `CAMERA` and **no** media-read permissions. `image_picker` uses the system
capture intent and the Android photo picker, neither of which needs one. That keeps the Data Safety
declaration light — don't add permissions that aren't needed.

---

## 7. Producing an upload artifact — the short version

Once sections 1–3 are done:

```bash
flutter clean
flutter pub get
flutter test                    # expect all green
flutter build appbundle --release -PrequireReleaseSigning=true
```

Then verify before uploading:

```bash
# the .aab is signed with YOUR key, not the debug key
jarsigner -verify -verbose:summary -certs \
  build/app/outputs/bundle/release/app-release.aab | head -20
```

---

## 8. Still open — decisions, not tasks

These are genuine product choices. Nothing in the repo presumes an answer to any of them.

| Decision | Why it matters |
|---|---|
| Play Console account type (individual vs organisation) and public developer name | Gates account creation; the name is public on the listing. |
| Privacy policy content and hosting | Required for submission. Nothing exists in the repo or the app today. |
| Apple-sign-in on Android | Apple sign-in is iOS-gated, so an account created with Apple on iPhone **cannot** be signed into on Android at all. Accept it / implement Apple-on-Android / mitigate by prompting iOS users to link Google. |
| Cupertino widgets on Android | 11 files use `CupertinoAlertDialog` / `CupertinoTextField` / `CupertinoSearchTextField` unguarded. They render fine on Android but look iOS-styled inside a Material app. Ship as-is / adaptive dialogs / full Material conversion. |
| Ko-fi donation link | Resolved: removed from the app on every platform (2026-08-18 ruling, option B). Nothing left to check against Play's payments policy. |
| Analytics advertising ID | Resolved: stripped `AD_ID` (and the related `ACCESS_ADSERVICES_*` permissions) from the merged manifest (2026-08-18 ruling, option B); see section 0's Data Safety notes. |

---

## 9. Still unverified — needs a physical Android device

The automated test suite is host-VM only. These cannot be answered without hardware, and the
first one is the highest-risk unknown in the whole Android launch:

1. **Does the encrypted database open on Android?** `lib/database/database.dart` opens
   `libsqlcipher.so` via `openCipherOnAndroid`, which has never executed on an Android device.
   The app no longer fails silently here: if the library that loads is *not* SQLCipher, the first
   database access throws `SqlCipherUnavailableException` and the album screen renders
   `Error: SqlCipherUnavailableException: the local database is NOT encrypted…` instead of crashing.
   That text means the SQLCipher `.so`/framework did not link — not that the database is corrupt, and
   not that the app is broken. It is the guard doing its job: without it the app would have quietly
   written every piece, photo and note to disk in the clear.
   A `SqlCipherKeyingException` instead means the opposite: SQLCipher is there, but it rejected the
   key. Its sqlite3 result code is shown; the statement is not, because that statement quotes the
   database key and this error reaches both the screen and Crashlytics.
2. Does an *existing* encrypted database still open after the `sqlcipher_flutter_libs` 0.5.7 → 0.6.8
   swap? This changes the underlying native library from `net.zetetic:android-database-sqlcipher:4.5.4`
   to `net.zetetic:sqlcipher-android:4.10.0` — **so this needs re-testing on iOS too, not just
   Android.**
3. Does the `flutter_secure_storage` encryption key survive kill / relaunch / app upgrade on Android?
4. Camera capture and photo-picker round-trip on Android 13+.
5. Google Sign-In end to end, after section 4.
6. App Check / Play Integrity, only meaningful in a Play track.
7. In-app review — a no-op outside a Play track, and quota-limited.
8. Cupertino dialogs vs the Android back gesture.
