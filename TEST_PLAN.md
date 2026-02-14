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
- [ ] Pieces shown as rows with title, updatedAt date, + horizontally scrollable photo thumbnails
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
- [ ] Searches across: title, clay type, glazes, tags, notes
- [ ] Clearing search shows all pieces again
- [ ] Search field has no autocorrect

### Empty States
- [ ] No active pieces → "No pieces yet" message with icon
- [ ] No archived pieces → empty state shown in archive view

### Metadata in Home View
- [ ] **TODO:** Display tags, clay, glazes, and other metadata below each piece row in the home view

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
- [ ] Date label shown below each photo (e.g. "Feb 12, 2026")
- [ ] Tap photo → fullscreen viewer with pinch-zoom (0.5x–4x)
- [ ] Long-press photo → bottom sheet with "Delete photo" option

### Photo Management
- [ ] Add photo via camera icon in app bar → Camera / Photo Library picker
- [ ] New photo becomes cover automatically
- [ ] Delete photo → confirmation dialog → photo removed
- [ ] Deleting cover photo → next newest photo becomes cover
- [ ] Deleting all photos → no gallery shown, just metadata form

### Batch Photo Upload (Photo Library multi-select)
- [ ] Photo Library option uses multi-select picker (select 1 or many)
- [ ] Progress dialog shows "Processing X of Y..." for multiple photos
- [ ] All selected photos added to piece gallery
- [ ] Last photo in batch set as cover
- [ ] Failed photos skipped; failure count shown in snackbar
- [ ] Cancelling multi-picker returns with no changes
- **NOTE: Multi-select (PHPicker) does NOT work on iOS simulator. Camera also crashes on simulator. Both require a real device to test.**

### Photo Reordering
- [ ] "Reorder" button appears below gallery when 2+ photos exist
- [ ] "Reorder" button hidden when 0-1 photos
- [ ] Tapping "Reorder" opens full-screen list with thumbnails and drag handles
- [ ] Dragging a photo reorders the list
- [ ] Tapping "Done" saves new order; gallery reflects updated order
- [ ] Tapping back (without Done) discards changes
- [ ] **TODO:** Allow deleting photos from the reorder screen

### Metadata Form
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

### Actions (Icon Buttons in App Bar)
- [ ] Archive icon button → piece archived, navigates back to home
- [ ] Unarchive icon (on archived piece) → piece unarchived, stays on detail
- [ ] Trash icon (red tint) → confirmation dialog → piece + all photos deleted, navigates home

### Title (Above Gallery)
- [ ] Title displayed above photo gallery with titleLarge styling
- [ ] Title is editable, saves on keyboard "done"
- [ ] Untitled pieces: title field is empty, hint shows "Untitled Piece N" with correct number
- [ ] Leaving title empty preserves "Untitled Piece N" in DB for album display
- [ ] Typing a name replaces the untitled name
- [ ] Pieces with custom titles show the title prefilled normally

### Haptic Feedback (manual — requires physical device)
- [ ] Adding a photo → light haptic
- [ ] Deleting a photo (after confirm) → light haptic
- [ ] Archiving/unarchiving → light haptic
- [ ] Deleting a piece (after confirm) → medium haptic
- [ ] Creating a new piece → light haptic

### Done Button
- [ ] Tapping "Done" saves pending form changes and navigates to home

### Last Updated (Editable)
- [ ] Shows "Last updated {date} {time}" below metadata with edit icon
- [ ] Timestamp updates after any edit
- [ ] Tapping opens date picker then time picker
- [ ] Selected date/time updates the updatedAt in DB
- [ ] Cancelling date picker leaves date unchanged
- [ ] Cancelling time picker uses existing time with new date

---

## 6. Fullscreen Photo Viewer

- [ ] Black background with close button
- [ ] Pinch-to-zoom (0.5x min, 4x max)
- [ ] Tap back / close to return to detail

---

## 7. Settings Screen

- [ ] Shows "Signed in as {name}" or "Not signed in"
- [ ] "Sign Out" button → clears auth, redirects to sign-in
- [ ] "Materials" section with "Manage Clays", "Manage Glazes", and "Manage Tags" options
- [ ] "Cloud sync coming soon" placeholder
- [ ] "Support Developer — Coming soon" placeholder
- [ ] Version shows "1.0.0"

### Manage Clays Screen (`/settings/clays`)
- [ ] Shows list of saved clay names in custom sort order
- [ ] Empty state: "No clays saved yet" when no clays exist
- [ ] "+" button in app bar → add dialog → creates new clay (appears at bottom)
- [ ] Edit icon on each clay → edit dialog → renames clay
- [ ] Delete icon on each clay → confirmation dialog → deletes clay
- [ ] Deleting a clay does NOT clear clay from existing pieces (value preserved)
- [ ] Adding duplicate clay name (case-insensitive) → reuses existing
- [ ] Changes reflected immediately in piece detail clay dropdown

### Clay Reordering
- [ ] Drag handles visible on left side of each clay row
- [ ] Dragging a clay to a new position reorders the list immediately
- [ ] Reorder persists after leaving and returning to Manage Clays
- [ ] Custom order reflected in piece detail clay picker dropdown
- [ ] Newly added clays appear at the bottom of the list
- [ ] Scale + elevation animation on dragged item

### Clay Rename Propagation
- [ ] Renaming a clay in Manage Clays → all pieces using that clay show the new name
- [ ] Renaming updates the piece detail clay display immediately

### Manage Glazes Screen (`/settings/glazes`)
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

### Glaze Rename Propagation
- [ ] Renaming a glaze in Manage Glazes → all pieces using that glaze show updated name
- [ ] Denormalized glazes text column updated (for search)

### Manage Tags Screen (`/settings/tags`)
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

### Tag Colors
- [ ] New tags auto-assigned a default color from 7 presets (cycling)
- [ ] Colored circle shown next to each tag in Manage Tags list
- [ ] Tapping circle opens color picker bottom sheet with 7 preset swatches
- [ ] Selected swatch shows checkmark and border
- [ ] Picking a color saves immediately; Manage Tags list updates
- [ ] Album view tag chips reflect custom color (tinted bg + darkened text)
- [ ] Tags without a custom color fall back to hash-based palette
- [ ] Color dot shown next to each tag in piece detail tag picker bottom sheet

### Tag Rename Propagation
- [ ] Renaming a tag in Manage Tags → all pieces using that tag show updated name
- [ ] Denormalized tags text column updated (for search)

---

## 8. Data & Image Pipeline

### Image Processing
- [ ] Main image: JPEG q75, max 1500px
- [ ] Thumbnail: JPEG q60, max 300px
- [ ] EXIF date extracted when available; falls back to current time
- [ ] Compression failure → raw bytes fallback

### Database
- [ ] Pieces table: id, title, stage, clayType, glazes (denormalized), tags (denormalized), notes, isArchived, coverPhotoId, createdAt, updatedAt
- [ ] Photos table: id, pieceId, localPath, thumbnailPath, cloudUrl, dateTaken, createdAt, sortOrder
- [ ] ClayOptions table: id, name (unique), sortOrder, createdAt
- [ ] GlazeOptions table: id, name (unique), sortOrder, createdAt
- [ ] PieceGlazes junction table: id, pieceId, glazeOptionId, sortOrder
- [ ] TagOptions table: id, name (unique), color (nullable), sortOrder, createdAt
- [ ] PieceTags junction table: id, pieceId, tagOptionId
- [ ] Photos sorted by sortOrder DESC (newest first) everywhere
- [ ] Migration v4→v5: creates GlazeOptions + PieceGlazes, parses free-text glazes into library
- [ ] Migration v5→v6: creates TagOptions + PieceTags + adds tags column to pieces
- [ ] Migration v6→v7: adds color column to TagOptions

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
