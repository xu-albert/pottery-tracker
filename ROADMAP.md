# Pottery Tracker — Roadmap

## Design & Branding
- [ ] **App logo/icon** — generate with an AI art tool (suggestions: Midjourney, Recraft, or IconKit by Apple for simple SF Symbol-style icons)
- [ ] **Re-examine color scheme** — current palette may need refinement once logo is finalized; consider harmonizing with the logo's colors

## UX Improvements
- [ ] **Onboarding walkthrough** — brief tutorial on first launch showing how to create a piece
- [ ] **Haptic feedback** — light haptics on archive, delete, photo add
- [ ] **Swipe-to-archive** from album row
- [ ] **Undo snackbar** after archive/delete instead of confirmation dialog
- [ ] **Photo reordering** — drag-to-reorder photos in detail gallery
- [ ] **Batch photo upload** — select multiple photos at once when adding to a piece
- [ ] **Last updated date on album rows** — show "Last updated" text under thumbnails or right-aligned next to title in active view

## Features
- [ ] **Tags / categories** — user-defined labels for organizing pieces (e.g., "mugs", "bowls", "gifts")
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
