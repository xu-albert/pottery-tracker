# Pottery Tracker — Roadmap

## Design & Branding
- [x] **App logo/icon** — custom icon across all platforms
- [ ] **Re-examine color scheme** — current palette may need refinement once logo is finalized; consider harmonizing with the logo's colors

## UX Improvements
- [ ] **Onboarding walkthrough** — brief tutorial on first launch showing how to create a piece
- [x] **Haptic feedback** — light haptics on archive, delete, photo add
- [x] **Swipe-to-archive** from album row
- [ ] **Undo snackbar** after archive/delete instead of confirmation dialog
- [x] **Photo reordering** — drag-to-reorder photos in detail gallery
- [x] **Batch photo upload** — select multiple photos at once when adding to a piece
- [x] **Last updated date on album rows** — show "Last updated" text under thumbnails or right-aligned next to title in active view

## Features
- [x] **Tags / categories** — user-defined labels for organizing pieces (e.g., "mugs", "bowls", "gifts")
- [ ] **Custom tag colors** — let users pick a color per tag for quick visual identification in the album view
- [ ] **Glaze library** — save and reuse glaze recipes across pieces
- [ ] **Firing log** — track kiln firings (cone, temperature, schedule) and link to pieces
- [ ] **Timeline view** — show a piece's photo history as a visual timeline (greenware → bisque → glazed)
- [ ] **Export / share** — export a piece as a shareable image collage or PDF
- [ ] **Statistics dashboard** — total pieces, pieces by stage, monthly creation chart

## Technical / Infrastructure
- [ ] **Firebase sync (Phase 2)** — Google/Apple auth backend, Firestore, Cloud Storage
- [ ] **Dark mode** — respect system setting
- [ ] **Widget tests** — unit tests for DAOs, widget tests for key screens
- [ ] **CI/CD** — GitHub Actions for `dart analyze` + `flutter test` on PRs
