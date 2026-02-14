# Pottery Tracker — Roadmap

## Design & Branding
- [x] **App logo/icon** — custom icon across all platforms
- [ ] **Re-examine color scheme** — current palette may need refinement once logo is finalized; consider harmonizing with the logo's colors
- [ ] **In-app branding redesign** — incorporate app icon or other imagery into the app UI (e.g., sign-in screen, empty states, splash screen)

## UX Improvements
- [ ] **Onboarding walkthrough** — brief tutorial on first launch showing how to create a piece
- [x] **Haptic feedback** — light haptics on archive, delete, photo add
- [x] **Swipe-to-archive** from album row
- [x] **Undo snackbar** after swipe-to-archive
- [x] **Photo reordering** — drag-to-reorder photos in detail gallery
- [x] **Batch photo upload** — select multiple photos at once when adding to a piece
- [x] **Last updated date on album rows** — show "Last updated" text under thumbnails or right-aligned next to title in active view
- [x] **Archive thumbnail titles** — overlay piece title text at bottom-right of archive grid thumbnails with gradient fade

## Features
- [x] **Tags / categories** — user-defined labels for organizing pieces (e.g., "mugs", "bowls", "gifts")
- [x] **Custom tag colors** — let users pick a color per tag for quick visual identification in the album view
- [ ] **Glaze library** — save and reuse glaze recipes across pieces
- [ ] **Firing log** — track kiln firings (cone, temperature, schedule) and link to pieces
- [ ] **Timeline view** — show a piece's photo history as a visual timeline (greenware → bisque → glazed)
- [ ] **Export / share** — export a piece as a shareable image collage or PDF
- [ ] **Statistics dashboard** — total pieces, pieces by stage, monthly creation chart

## Testing
- [ ] **Test input capitalization on hardware** — verify TextCapitalization.sentences behavior on physical iPhone for title field and that dialogs (clay, glaze, tag) default to no forced capitalization
- [ ] **Handle duplicate metadata** — decide behavior when user creates a clay, glaze, or tag with a name that already exists (e.g., prevent, merge, warn). Also decide policy for duplicate piece titles (allow silently, warn, or append suffix)

## Technical / Infrastructure
- [ ] **Firebase sync (Phase 2)** — Google/Apple auth backend, Firestore, Cloud Storage
- [ ] **Dark mode** — respect system setting
- [ ] **Widget tests** — unit tests for DAOs, widget tests for key screens
- [ ] **CI/CD** — GitHub Actions for `dart analyze` + `flutter test` on PRs
