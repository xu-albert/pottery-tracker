# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Rules

- **DO NOT write TODOs, FIXMEs, or HACKs in code comments.** Track all TODOs in Claude memory files only.

## Project Overview

Pottery Tracker is a photo-first mobile app for hobby potters to log and track their ceramic pieces. The full product requirements are in `pottery_tracker_prd.md`.

## Current Status

**Phase 1 (local-only) is implemented.** Firebase sync is Phase 2.

### What's built:
- Sign-in screen (Google/Apple buttons + "Skip for now") — UI gate only, no Firebase backend
- Album screen with 3-column grid, search bar, All/Finished filter chips, empty state
- Piece creation: tap + → bottom sheet (Camera/Photo Library) → compress & save photo → create piece in DB → navigate to detail
- Piece detail: swipeable photo gallery, metadata form (title, stage, clay type, glazes, notes), "Last updated" timestamp, add photo, delete photo (long press), delete piece (overflow menu), "Done" button
- Fullscreen photo viewer with pinch-zoom
- Settings: account info, sign out, sync placeholder, support developer placeholder, version
- Localization: all strings in `lib/l10n/app_en.arb`
- Drift (SQLite) database with Pieces and Photos tables + DAOs
- Riverpod state management throughout
- GoRouter with StatefulShellRoute for bottom nav + auth redirect

### Known decisions:
- Cover photo / thumbnail selection UI removed — will be reworked later. Currently auto-sets most recent photo as cover.
- Image pipeline uses in-memory compression (`compressWithList`) with raw-bytes fallback for reliability
- Camera crashes on iOS simulator — use Photo Library for testing

## Tech Stack

- **Framework:** Flutter 3.41.0 (Dart 3.11.0)
- **Local DB:** Drift (SQLite via `drift` + `drift_flutter`)
- **State Management:** Riverpod (`flutter_riverpod`)
- **Routing:** GoRouter (`go_router`)
- **Image handling:** `image_picker`, `flutter_image_compress`, `exif`
- **Auth (UI only):** `google_sign_in`, `sign_in_with_apple`
- **Cloud:** Firebase — not wired up yet (Phase 2)

## Common Commands

```bash
# Run the app
flutter run

# Run on iOS simulator (iPhone 16 Pro)
flutter run -d 596FA2B9-8F2D-4E57-BEF5-29F2C3DB6A1B

# Build release APK / iOS
flutter build apk
flutter build ios

# Run all tests
flutter test

# Analyze code
dart analyze

# Format code
dart format .

# Get dependencies
flutter pub get

# Generate Drift database code
dart run build_runner build --delete-conflicting-outputs

# Generate localization files
flutter gen-l10n
```

## Architecture

### Folder Structure

```
lib/
├── main.dart                          # Entry point (ProviderScope)
├── app.dart                           # MaterialApp.router with theme + l10n
├── core/
│   ├── constants/app_colors.dart      # Color palette
│   ├── constants/app_sizes.dart       # Spacing, radii, grid config
│   └── theme/app_theme.dart           # Material 3 theme
├── database/
│   ├── database.dart                  # AppDatabase (Drift)
│   ├── tables/pieces_table.dart       # Pieces table definition
│   ├── tables/photos_table.dart       # Photos table definition
│   ├── daos/pieces_dao.dart           # Piece CRUD + filtered watch queries
│   └── daos/photos_dao.dart           # Photo CRUD + watch by pieceId
├── models/piece_stage.dart            # PieceStage enum
├── providers/
│   ├── database_provider.dart         # DB singleton + DAO providers
│   ├── pieces_provider.dart           # Search, filter, filteredPiecesProvider
│   ├── photos_provider.dart           # photosForPieceProvider (family)
│   ├── image_service_provider.dart    # ImageService provider
│   └── auth_provider.dart             # AuthNotifier + SharedPreferences
├── services/
│   ├── image_service.dart             # Pick → EXIF → compress → save pipeline
│   └── auth_service.dart              # Google/Apple sign-in stubs
├── router/app_router.dart             # GoRouter config
├── features/
│   ├── auth/screens/sign_in_screen.dart
│   ├── shell/screens/shell_screen.dart        # Bottom nav
│   ├── album/
│   │   ├── screens/album_screen.dart
│   │   └── widgets/ (album_grid, piece_thumbnail, search_bar, filter_chips, empty_state)
│   ├── create_piece/screens/create_piece_screen.dart
│   ├── piece_detail/
│   │   ├── screens/piece_detail_screen.dart
│   │   └── widgets/ (photo_gallery, photo_fullscreen, metadata_form, photo_timeline)
│   └── settings/screens/settings_screen.dart
└── l10n/
    ├── app_en.arb                     # English strings
    ├── app_localizations.dart         # Generated
    └── app_localizations_en.dart      # Generated
```

### Data Model

Two core entities with a one-to-many relationship:

- **Piece** — (id, title, stage, clayType, glazes, notes, coverPhotoId, createdAt, updatedAt)
- **Photo** — (id, pieceId FK, localPath, thumbnailPath, cloudUrl, dateTaken, createdAt, sortOrder)

Stage is an enum: `greenware | bisqued | glazed` (all optional).

### Image Pipeline

Photos go through: `image_picker` → `readAsBytes()` → `FlutterImageCompress.compressWithList()` → `File.writeAsBytes()`. Main image: JPEG q75 max 1500px. Thumbnail: JPEG q60 max 300px. Falls back to raw bytes if compression fails. Saved to `getApplicationDocumentsDirectory()/photos/{pieceId}/{photoId}.jpg`.

### Offline-First + Cloud Sync

All data lives in local SQLite first. Firebase sync happens opportunistically when connectivity is available (Phase 2). Conflict resolution is last-write-wins based on `updatedAt`.

### Navigation

Bottom navigation with 3 tabs: Home (album grid), + (opens create flow), Settings. GoRouter with `StatefulShellRoute`. Auth redirect sends unauthenticated users to sign-in.

## Design Constraints

- All features must work fully offline; sync is additive
- English only for V1 but use Flutter intl (no hardcoded strings)
- V1 is free with optional donation — no paywalls
- Firebase Spark (free) plan: 1GB Firestore, 5GB Cloud Storage, 50K reads/day, 20K writes/day
- Accessibility: screen reader support, system font scaling, minimum touch targets (48dp Android / 44pt iOS)
