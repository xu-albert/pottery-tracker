# Pottery Tracker — Test Plan

This document catalogs all testable features, functionality, and edge cases. Update this file whenever features are added or changed.

---

## 1. Authentication & Onboarding

### Sign-In Screen (`/sign-in`)
- [ ] "Sign in with Google" button launches Google sign-in flow
- [ ] "Sign in with Apple" button appears only on iOS
- [ ] "Skip for now" bypasses auth and enters app
- [ ] Auth state persists across app restarts (SharedPreferences)
- [ ] After sign-in or skip, user lands on Album screen

### Edge Cases
- [ ] Force-quit and relaunch — user stays authenticated
- [ ] Sign out from Settings → redirected back to sign-in screen

---

## 2. Bottom Navigation

### Shell Screen
- [ ] Home tab (left) → Album screen
- [ ] "+" button (center) → Create piece flow
- [ ] Settings tab (right) → Settings screen
- [ ] Tapping active tab preserves scroll position / state

---

## 3. Album Screen (Home)

### Active View (default)
- [ ] Pieces shown as rows with title + horizontally scrollable photo thumbnails
- [ ] Newest-updated pieces appear first
- [ ] Tapping a row opens piece detail
- [ ] Scrollable photo row shows left/right fade gradients when overflowing
- [ ] Gradients hide when scrolled to edge

### Archive View
- [ ] Tap "Archive" chip → shows 3-column grid of archived pieces
- [ ] Archive thumbnails are 1:1 square, photo-only (no title text overlay)
- [ ] Tapping thumbnail opens piece detail

### Search
- [ ] Typing in search bar filters pieces in real-time
- [ ] Searches across: title, clay type, glazes, notes
- [ ] Clearing search shows all pieces again

### Empty States
- [ ] No active pieces → "No pieces yet" message with icon
- [ ] No archived pieces → empty state shown in archive view

### Edge Cases
- [ ] Piece with no photos → placeholder icon in row and archive grid
- [ ] Very long title → ellipsis truncation
- [ ] Single photo piece in row → no gradients shown

---

## 4. Piece Creation

### Flow
- [ ] Tap "+" → bottom sheet with Camera / Photo Library
- [ ] Select source → pick image → processing spinner → navigates to detail
- [ ] New piece gets auto-title "Untitled Piece N" (lowest available number)
- [ ] First photo set as cover automatically

### Untitled Piece Numbering
- [ ] First piece → "Untitled Piece 1"
- [ ] With "Untitled Piece 1" existing → new piece is "Untitled Piece 2"
- [ ] With "Untitled Piece 1" and "Untitled Piece 3" existing → new piece is "Untitled Piece 2" (fills gap)
- [ ] Renaming "Untitled Piece 1" to something else → next piece reuses number 1

### Edge Cases
- [ ] Cancel source picker → returns to previous screen
- [ ] Cancel image picker → returns to previous screen
- [ ] Image compression fails → raw bytes saved as fallback
- [ ] Camera on iOS simulator → crashes (use Photo Library for testing)

---

## 5. Piece Detail Screen

### Photo Gallery
- [ ] Photos displayed as 1:1 squares at 72% screen width
- [ ] Horizontal free-scrolling (no page snapping) with bounce physics
- [ ] Newest photo appears leftmost
- [ ] Left/right fade gradients appear when gallery is scrollable
- [ ] Gradients hide when scrolled to respective edge
- [ ] Single photo → centered, no gradients
- [ ] Tap photo → fullscreen viewer with pinch-zoom (0.5x–4x)
- [ ] Long-press photo → bottom sheet with "Delete photo" option

### Photo Management
- [ ] Add photo via camera icon in app bar → Camera / Photo Library picker
- [ ] New photo becomes cover automatically
- [ ] Delete photo → confirmation dialog → photo removed
- [ ] Deleting cover photo → next newest photo becomes cover
- [ ] Deleting all photos → no gallery shown, just metadata form

### Metadata Form
- [ ] Edit title → saves on keyboard "done"
- [ ] Select stage (Greenware / Bisqued / Glazed / None) → saves immediately
- [ ] Edit clay type → saves on keyboard "done"
- [ ] Edit glazes → saves on keyboard "done"
- [ ] Edit notes (multiline) → saves on keyboard "done"
- [ ] Empty string fields saved as NULL in database

### Actions (Overflow Menu)
- [ ] "Archive" → piece archived, navigates back to home
- [ ] "Unarchive" (on archived piece) → piece unarchived, stays on detail
- [ ] "Delete" → confirmation dialog → piece + all photos deleted, navigates home

### Done Button
- [ ] Tapping "Done" saves pending form changes and navigates to home

### Last Updated
- [ ] Shows "Last updated {date} {time}" below metadata
- [ ] Timestamp updates after any edit

---

## 6. Fullscreen Photo Viewer

- [ ] Black background with close button
- [ ] Pinch-to-zoom (0.5x min, 4x max)
- [ ] Tap back / close to return to detail

---

## 7. Settings Screen

- [ ] Shows "Signed in as {name}" or "Not signed in"
- [ ] "Sign Out" button → clears auth, redirects to sign-in
- [ ] "Cloud sync coming soon" placeholder
- [ ] "Support Developer — Coming soon" placeholder
- [ ] Version shows "1.0.0"

---

## 8. Data & Image Pipeline

### Image Processing
- [ ] Main image: JPEG q75, max 1500px
- [ ] Thumbnail: JPEG q60, max 300px
- [ ] EXIF date extracted when available; falls back to current time
- [ ] Compression failure → raw bytes fallback

### Database
- [ ] Pieces table: id, title, stage, clayType, glazes, notes, isArchived, coverPhotoId, createdAt, updatedAt
- [ ] Photos table: id, pieceId, localPath, thumbnailPath, cloudUrl, dateTaken, createdAt, sortOrder
- [ ] Photos sorted by sortOrder DESC (newest first) everywhere

### Photo Ordering (Newest First)
- [ ] Detail gallery: newest photo leftmost
- [ ] Album row: newest photo leftmost
- [ ] Cover photo: set to newest on add; on delete, falls back to newest remaining

---

## 9. Cross-Cutting Concerns

### Offline-First
- [ ] All features work without network connectivity
- [ ] No Firebase calls in Phase 1

### Localization
- [ ] All UI strings from `app_en.arb` (no hardcoded user-facing strings except error messages)

### Accessibility
- [ ] Semantics labels on interactive elements
- [ ] Minimum 48dp touch targets (Android) / 44pt (iOS)
- [ ] System font scaling respected

### Error Handling
- [ ] Broken image files → placeholder icon shown
- [ ] Photo capture failure → SnackBar error message
- [ ] Database errors → "Error: {e}" displayed

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
