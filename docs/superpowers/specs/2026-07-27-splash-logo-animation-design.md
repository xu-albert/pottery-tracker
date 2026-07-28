# Splash Logo Animation — Design

**Date:** 2026-07-27
**Status:** Approved, not yet implemented
**Branch:** `feature/splash-logo-animation`

## Goal

Replace the placeholder lightbulb icon on the splash screen with a new hand-drawn
gooseneck vase mark that draws itself on as the app opens. The same mark becomes the
app icon across all platforms, so the launch animation and the home-screen icon read as
the same object.

## Art Direction

A gooseneck bud vase — the silhouette of the current icon — reduced to a simple
line drawing. HEYTEA's mark is the reference for *style*, not a template: sparse,
confident, hand-drawn rather than plotted. Departures from that reference:

- **Thicker stroke than HEYTEA's hairline.** The mark must hold up at ~60pt on a home
  screen next to dense icons. A single weight is used everywhere rather than a separate
  heavier icon variant.
- **Near-black line on cream** (`#EDE5DA`). Exact value chosen from a rendered
  comparison sheet; `#3C3C3C` (`AppColors.charcoal`) is the starting candidate.

**Out of scope: dark mode.** A near-black mark on cream inverts badly on a dark
background, but dark mode is not on the near-term roadmap. Solving for a mode that does
not exist would constrain the art direction for no present benefit. Revisit if and when
dark mode is built.

## Approach

Three approaches were considered for producing the hand-drawn quality. The governing
constraint: **Flutter's canvas cannot stroke a path with varying width.** `drawPath`
with a stroke paint yields one uniform thickness, so pressure variation — the thick
downstroke and thin pen-lift of real drawing — is not available for free.

### Chosen: A — uniform stroke, organic curves

One centerline path, one stroke width, round caps. The hand-drawn quality comes from
the geometry: slight left/right asymmetry, a rim that is not perfectly level, a small
deliberate gap where the stroke opens and closes. `PathMetrics.extractPath` traces it
directly, which is already working in the existing prototype.

Low risk, no new dependencies, and the draw-on animation is essentially solved. Its
ceiling is a clean minimal line drawing rather than something that reads as ink.

### Recorded alternative: B — filled ribbon path

Author the outline of the stroke itself as a closed filled shape that swells and tapers,
the way real ink marks are vectorized. Genuinely ink-like, and the honest way to get
variable line weight.

Costs roughly double the path data, and the draw-on gets meaningfully harder: a fill
cannot be traced with `extractPath`, so the animation needs a clipping mask sweeping
along the centerline.

**Trigger to revisit:** the uniform stroke reads flat once seen at real size on device.
Because the centerline path is kept as a standalone pure function, a ribbon painter can
derive its outline from the same approved shape — the silhouette work is not lost.

### Rejected: C — `flutter_svg` + drawing-animation package

Ship the SVG as an asset and let a library handle rendering and tracing. Rejected: adds
two dependencies, the Flutter path-drawing packages are largely unmaintained, the icon
PNG would still need to be produced separately, and it replaces working code with a
third-party abstraction that offers less control over the animation.

## Architecture

### `lib/widgets/vase_logo.dart` (rewritten in place)

- **`buildVasePath(Size)`** — static, pure, returns the centerline `Path`. The single
  source of shape truth; every other component consumes it. This is the seam that keeps
  Approach B available: a ribbon painter derives an outline from this same centerline.
- **`VaseLogo`** — static mark, for the icon export and any in-app branding.
- **`AnimatedVaseLogo`** — the draw-on, via `PathMetrics.extractPath`. Parameters:
  `color`, `strokeWidth`, `duration`, `onComplete`.

The existing `fillAfterTrace` / `fillOpacity` fill stage is deleted. The mark is pure
line, and an unused option is a maintenance liability.

### Launch flow

The router currently redirects off `/splash` the moment auth resolves, so the splash
needs a way to say "not yet."

- Add **`splashCompleteProvider`** (`StateProvider<bool>`) in a new
  `lib/providers/splash_provider.dart`.
- Redirect holds on `/splash` while `authStatus == unknown || !splashComplete`.
- `AnimatedVaseLogo.onComplete` sets the flag.

Exit happens when auth is resolved **and** the stroke has finished. When auth is slow the
animation is free — it runs inside time the launch was already spending. When auth is
fast, launch is delayed by up to the full ~900ms. That is the accepted cost of the
animation always being seen.

**Skip is deliberately not implemented,** pending on-device testing. The single provider
keeps the decision cheap to reverse: tap-to-skip is a `GestureDetector` setting the same
flag, with no restructuring.

### Failure handling

If `onComplete` never fires — disposed widget, stalled ticker, an exception in the
painter — the app would hang on the splash with no way forward. The splash arms a
**3-second hard fallback timer** that sets `splashCompleteProvider` regardless. A logo
animation must never be able to brick app launch.

### Timing and platform handoff

- Native launch screen (iOS `LaunchScreen.storyboard`, Android launch background) becomes
  solid cream with nothing on it — identical to the splash's first frame at
  `progress = 0`. Any mismatch shows as a flash at handoff.
- Draw-on duration **~900ms**, `Curves.easeInOut`.

Platform guidance behind those numbers:

- **Apple's HIG** states a launch screen "isn't an onboarding experience or a splash
  screen, and it isn't an opportunity for artistic expression," and Apple rejects launch
  screens containing animation or branding. This governs the *native* launch screen only.
  The compliant pattern — a static native launch screen handing off to an animated first
  in-app screen starting from an identical frame — is what this design uses.
- **Android's SplashScreen API** docs recommend the icon animation not exceed **1,000ms**
  on phones, and that the splash be dismissed as soon as the app is visually stable.
- Common industry guidance is to stay under **1.5s** total. The frequently cited
  abandonment figures (~8% per additional second) come from vendor blogs rather than
  peer-reviewed research and should be treated as directional. The better-supported
  finding is that animation reduces *perceived* wait even when actual wait is unchanged.

900ms sits under the Android ceiling and well under the 1.5s threshold.

## Art Direction Workflow

The silhouette is the risky part, and neither party can judge a vase from Bézier
coordinates. Shape is settled before any Dart is written:

1. SVG sheet of 3–4 gooseneck silhouette variants at splash size → pick one.
2. Second sheet of the chosen shape across stroke weights and near-black colors,
   including a 60pt render to judge small-size legibility.
3. Port the approved path into the Dart painter.

SVG iterates in seconds with no build cycle. After the port, the Dart path is the single
runtime source of truth and the SVG remains in the repo as design source only — matching
how `assets/icon/vase_logo.svg` is already treated (it is not bundled; there is no
`assets:` block in `pubspec.yaml` and no `flutter_svg` dependency).

## Icon Pipeline

The approved path renders at 1024×1024 on cream with no alpha into
`assets/icon/icon.png`, then `flutter_launcher_icons` regenerates iOS, Android, macOS,
and web. `remove_alpha_ios: true` is already configured in `pubspec.yaml`.

**This changes the home-screen icon for existing users.** Accepted, not a blocker.

## Testing

- `AnimatedVaseLogo` fires `onComplete` after its duration (`pumpWidget` + `pump`).
- The 3-second fallback fires when `onComplete` never does (`fake_async`, already a dev
  dependency).
- Splash holds while auth status is `unknown`, and leaves once both conditions are met.
- One golden test for the finished static mark. Goldens are brittle across platforms, but
  this feature is entirely visual — a silently regressing logo is precisely what goldens
  catch.

## Files Touched

| File | Change |
| --- | --- |
| `lib/widgets/vase_logo.dart` | Rewrite: new path, drop fill stage |
| `lib/features/auth/screens/splash_screen.dart` | Stateless → stateful; animation, completion flag, fallback timer |
| `lib/router/app_router.dart` | Redirect holds on `/splash` until animation completes |
| `lib/providers/splash_provider.dart` | New file: `splashCompleteProvider` |
| `assets/icon/vase_logo.svg` | Replace with approved silhouette (design source) |
| `assets/icon/icon.png` | Regenerate from approved path |
| `ios/Runner/Base.lproj/LaunchScreen.storyboard` | Solid cream, no content |
| `android/app/src/main/res/drawable/launch_background.xml` | Solid cream |
| `android/app/src/main/res/drawable-v21/launch_background.xml` | Solid cream |
| `test/` | Widget tests + golden |
| `TEST_PLAN.md` | Changelog entry and splash test cases |
