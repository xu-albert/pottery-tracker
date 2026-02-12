# Product Requirements Document: Pottery Tracker

**Version:** 1.0  
**Status:** Draft  
**Last Updated:** January 2026

---

## 1. Overview

### 1.1 Problem Statement

Hobby potters often work on multiple pieces over days or weeks, making it difficult to remember when they started a piece, track its progress, or maintain a visual record of their work. Existing solutions are either too complex (designed for production potters) or too generic (general note-taking apps that don't understand the pottery workflow).

### 1.2 Solution

Pottery Tracker is a simple, photo-first mobile app for iOS and Android that lets hobby potters log their pieces with minimal friction. Each piece is documented through photos, with dates automatically captured. The app serves as both a work log and a visual portfolio of the potter's creations.

### 1.3 Target Audience

Hobby potters who want a simple way to track and showcase their work. These users value ease of use over comprehensive studio management features. They may work in shared studio spaces or at home, often without reliable WiFi access.

---

## 2. Goals & Success Metrics

### 2.1 Product Goals

- Make it effortless to log a new piece (under 10 seconds to capture a photo and save)
- Provide a beautiful visual album of the user's pottery work
- Work reliably without internet connectivity
- Sync data to the cloud so pieces are never lost

### 2.2 Success Metrics

| Metric | Target | Rationale |
|--------|--------|-----------|
| Time to log a piece | < 10 seconds | Friction kills habit formation |
| Weekly active users (WAU) | Track growth MoM | Engagement indicator |
| Pieces logged per active user | > 2 per week | Core value delivery |
| App store ratings | > 4.5 stars | User satisfaction |

---

## 3. User Personas

### 3.1 Primary Persona: Weekend Potter

- **Name:** Sarah, 34
- **Background:** Takes weekly pottery classes at a local studio. Has been doing pottery for about a year as a creative outlet from her desk job.
- **Goals:** Wants to remember what she's working on between sessions, share progress with friends, and look back at how her skills have improved.
- **Pain Points:** Forgets which pieces are hers in the shared studio. Can't remember when she started something or what stage it's at. Has photos scattered across her camera roll with no organization.

### 3.2 Secondary Persona: Home Hobbyist

- **Name:** Mike, 52
- **Background:** Retired early and set up a small pottery wheel in his garage. Works on pieces a few times a week.
- **Goals:** Document his pottery journey, keep a visual record of everything he's made, occasionally share pieces with family.
- **Pain Points:** Not tech-savvy, wants something dead simple. Doesn't want to learn a complex app.

---

## 4. Features & Requirements

### 4.1 Core Features (V1)

#### 4.1.1 Piece Creation

Users can create a new piece by taking a photo or uploading from their camera roll. This is the only required action.

| Field | Required | Description |
|-------|----------|-------------|
| Photo(s) | Yes | At least one photo required. Multiple photos supported for progress tracking. |
| Date | Auto (editable) | Automatically captured from photo timestamp (capture time or EXIF metadata if uploaded). User can manually override. |
| Title/Name | No | Optional name for the piece. |
| Stage | No | Greenware, Bisqued, or Glazed. Optional dropdown. |
| Clay Type | No | Free text field for clay body used. |
| Glaze(s) | No | Free text field for glaze(s) applied. |
| Notes | No | Free text field for any additional notes. |

**User Flow:**
1. User taps "+" button
2. Camera opens (or option to choose from library)
3. User takes/selects photo
4. Piece is created immediately with just the photo
5. User can optionally add more details or additional photos

#### 4.1.2 Photo Management

- Each piece can have multiple photos to document progress over time
- Photos can be added via camera or photo library
- Date metadata is automatically extracted from each photo
- Photos within a piece are displayed chronologically
- User can set which photo is the "cover" photo for album view
- User can delete individual photos from a piece

#### 4.1.3 Piece Detail View

Displays all information about a single piece:
- Photo gallery (swipeable, tappable to view full-screen)
- Timeline showing when each photo was added
- All metadata fields (editable)
- Delete piece option (with confirmation)

#### 4.1.4 Album View

The main screen of the app. A visual grid displaying all pieces.

- **Layout:** Grid of piece thumbnails (3 columns)
- **Sorting:** Most recent activity first (based on latest photo date)
- **Thumbnail:** Shows cover photo for each piece
- **Search:** Search bar at top to filter pieces by title, clay type, glazes, or notes
- **Filtering (V1):**
  - "All" — shows all pieces
  - "Finished" — shows pieces marked as Glazed stage
- **Interaction:** Tap to open piece detail view

#### 4.1.5 Offline Support

The app must function fully without internet connectivity.

- All data stored locally on device using SQLite (via Drift or sqflite)
- Photos stored in app's local storage
- All CRUD operations work offline
- Sync occurs automatically when connectivity is available

#### 4.1.6 Cloud Sync

User data should be backed up and synced to the cloud.

- Use Firebase (Firestore + Cloud Storage) for cross-platform sync
- Automatic background sync when connectivity available
- Conflict resolution: most recent edit wins
- User authentication via Firebase Auth (Google Sign-In, Apple Sign-In, or anonymous)
- Sync status indicator in settings

---

### 4.2 Data Model

```
Piece
├── id: String (UUID, primary key)
├── title: String? (optional)
├── stage: Enum? (greenware | bisqued | glazed) (optional)
├── clayType: String? (optional)
├── glazes: String? (optional)
├── notes: String? (optional)
├── coverPhotoId: String? (reference to Photo)
├── createdAt: DateTime
├── updatedAt: DateTime
└── photos: List<Photo> (one-to-many relationship)

Photo
├── id: String (UUID, primary key)
├── pieceId: String (foreign key to Piece)
├── localPath: String (local file path)
├── cloudUrl: String? (Firebase Storage URL, nullable until synced)
├── dateTaken: DateTime (from EXIF or capture time, user-editable)
├── createdAt: DateTime
└── sortOrder: int
```

---

### 4.3 Technical Requirements

#### 4.3.1 Platform & Technology

| Requirement | Specification |
|-------------|---------------|
| Platforms | iOS 12+, Android 6.0+ (API 23+) |
| Framework | Flutter (latest stable) |
| Language | Dart |
| Local Storage | Drift (SQLite) or sqflite |
| Cloud Database | Firebase Firestore |
| Cloud Storage | Firebase Cloud Storage |
| Authentication | Firebase Auth (Google, Apple Sign-In, anonymous) |
| Image Handling | image_picker, image package |
| State Management | Riverpod or Provider |

#### 4.3.2 Performance Requirements

- App launch to album view: < 2 seconds
- Photo capture to piece created: < 1 second
- Album scroll: 60fps smooth scrolling
- Image thumbnails: lazy loaded, cached (use cached_network_image)
- Offline mode: no degradation in core functionality

#### 4.3.3 Storage Considerations

- Thumbnail images generated and cached for album view (low resolution)
- **Cloud sync images heavily compressed** to stay within free tier limits:
  - Target: ~100-200KB per photo (down from typical 2-5MB)
  - Use JPEG with quality ~70-80%
  - Resize to max ~1500px on longest edge (sufficient for viewing, not print-quality)
- Full-resolution originals optionally kept on device only
- Storage usage displayed in settings
- Estimated cloud usage: ~500 photos per 100MB

---

### 4.4 User Interface Specifications

#### 4.4.1 Navigation Structure

```
Bottom Navigation (3 tabs):

[Home]              [+]                [Settings]
Album View          New Piece          Settings
    │                   │                   │
    ├── Search          ├── Camera          ├── Account
    ├── Filter          └── Library         ├── Sync Status
    └── Piece Detail                        ├── Storage
            │                               ├── Support Dev
            ├── Photo Gallery               └── About
            ├── Edit Fields
            └── Add Photo
```

- Home: Album grid (main view)
- "+": Prominent center button, opens camera/library picker directly
- Settings: Account, sync, storage, donation link

#### 4.4.2 Visual Design Direction

**Color Palette (earthy, warm tones):**
- Background: Warm beige/cream (#F5F0EB or similar)
- Primary accent: Teal/dark cyan (#2D6E6E or similar)
- Card colors: 
  - Muted sage green
  - Dusty rose/terracotta
  - Soft peach
  - Muted blue-gray
- Text: Dark brown/charcoal for readability
- Icons: Matching earthy tones or teal accent

**Overall Aesthetic:**
- Clean and minimal
- Soft, rounded corners on cards and buttons
- Warm and inviting — appropriate for a craft/pottery app
- Avoid harsh whites; prefer warm off-whites and creams

**Bottom Navigation:**
- 3 tabs: Home (album view), Add (+), Settings
- Teal accent color for active tab
- Centered "+" button slightly larger/prominent for quick piece creation

#### 4.4.3 Key Screens

**Album View (Home Tab)**
- Search bar at top (searches title, clay type, glazes, notes)
- Filter toggle (All / Finished) below search or as segmented control
- Grid of piece thumbnails (3 columns, square aspect ratio)
- Warm cream/beige background
- Empty state with friendly onboarding message

**Piece Detail View**
- Large photo viewer (swipeable gallery)
- Photo count indicator (e.g., "2 of 5")
- Add photo button
- Metadata section:
  - Title (tap to edit, placeholder: "Untitled Piece")
  - Stage (dropdown: None, Greenware, Bisqued, Glazed)
  - Clay Type (text field)
  - Glazes (text field)
  - Notes (multiline text field)
- Photo timeline showing dates
- Delete piece button (in overflow menu or bottom)

**New Piece Flow (+ Tab)**
- Tapping "+" opens camera immediately (with library option)
- After capture: brief preview, then auto-save
- Lands on piece detail view for optional editing
- Back returns to album

**Settings (Settings Tab)**
- Account section (sign in/out, current account info)
- Sync status and last sync time
- Storage usage (local and cloud)
- "Support the Developer" donation link
- About / version info

---

## 5. Infrastructure & Costs

### 5.1 Hosting & Backend

This app uses Firebase for cloud sync:

- **Firebase Firestore** — stores piece metadata
- **Firebase Cloud Storage** — stores compressed photos
- **Firebase Auth** — handles user authentication

### 5.2 Firebase Free Tier Limits (Spark Plan)

| Resource | Free Allowance |
|----------|----------------|
| Firestore storage | 1 GB |
| Firestore reads | 50,000/day |
| Firestore writes | 20,000/day |
| Cloud Storage | 5 GB |
| Storage downloads | 1 GB/day |
| Authentication | Unlimited |

For a hobby app with modest usage, the free tier should be sufficient for hundreds of active users.

### 5.3 Estimated Annual Costs

| Item | Cost | Notes |
|------|------|-------|
| Apple Developer Account | $99/year | Required to publish on App Store |
| Google Play Developer | $25 one-time | Required to publish on Play Store |
| Firebase (Spark plan) | $0 | Free tier sufficient for small user base |
| Firebase (if exceeds free tier) | ~$1-10/month | Pay-as-you-go, unlikely for small app |
| **Year 1 Total** | **~$125** | |
| **Year 2+ Total** | **~$99/year** | Just Apple renewal |

### 5.4 Monetization (V1)

**Strategy:** Free app with optional donation

- All features free, no paywalls
- "Support the Developer" option in settings
- Links to Ko-fi, Buy Me a Coffee, or similar
- Alternatively: in-app tip jar (small IAPs like $1.99, $4.99, $9.99)

**Future consideration:** Premium features may be added later (unlimited collections, widgets, export options, etc.) but are out of scope for V1.

---

## 6. Non-Functional Requirements

### 6.1 Privacy & Data

- Sign-in optional (can use anonymous auth for sync, or local-only mode)
- Photos stored on device and user's Firebase storage
- No analytics that identify individual users (or use privacy-respecting analytics like Firebase with minimal data)
- Privacy policy required for both app stores

### 6.2 Accessibility

- Screen reader support (TalkBack on Android, VoiceOver on iOS)
- Support for system font scaling
- Minimum touch target sizes (48x48dp Android, 44x44pt iOS)
- Sufficient color contrast ratios

### 6.3 Localization

- V1: English only
- Design with localization in mind (no hardcoded strings, use Flutter's intl)

---

## 7. Future Considerations (Post-V1)

These features are explicitly out of scope for V1 but should be considered in the architecture:

- **Additional stages:** Custom stages or sub-stages
- **Tagging/categories:** Group pieces by project, technique, etc.
- **Export/Share:** Share individual pieces or albums
- **Kiln log:** Track firings separately
- **Glaze library:** Save and reuse glaze recipes
- **Tablet optimization:** iPad and Android tablet layouts
- **Widgets:** Show recent pieces on home screen (iOS and Android)
- **Web version:** Flutter web for desktop access

---

## 8. Open Questions

1. **App name:** "Pottery Tracker" is a working title. Final name TBD.
2. **Onboarding:** How much onboarding is needed for first-time users?
3. **Tip jar implementation:** External link (Ko-fi) vs. native in-app purchases?
4. **Auth flow:** Require sign-in for sync, or allow anonymous usage with optional sign-in later?

---

## 9. Appendix

### 9.1 Glossary

| Term | Definition |
|------|------------|
| Greenware | Unfired clay; the initial stage after forming |
| Bisqued | Clay that has been fired once (bisque fire) but not yet glazed |
| Glazed | Piece that has been glazed and fired (finished) |
| EXIF | Exchangeable Image File Format; metadata embedded in photos including date taken |

### 9.2 References

- [Flutter Documentation](https://docs.flutter.dev/)
- [Firebase Documentation](https://firebase.google.com/docs)
- [Material Design Guidelines](https://m3.material.io/)
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)

### 9.3 Recommended Flutter Packages

| Purpose | Package |
|---------|---------|
| Local database | drift or sqflite |
| State management | riverpod or provider |
| Image picker | image_picker |
| Image caching | cached_network_image |
| Firebase | firebase_core, cloud_firestore, firebase_storage, firebase_auth |
| Image compression | flutter_image_compress |
| EXIF reading | exif |
| Date picker | built-in or table_calendar |
