# Splash Logo Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the splash screen's placeholder lightbulb with a hand-drawn gooseneck vase mark that draws itself on over ~900ms at launch, and regenerate the app icon from the same shape.

**Architecture:** A single pure function `buildVasePath(Size)` returns the vase centerline as a `Path` and is the only source of shape truth. `AnimatedVaseLogo` traces it with `PathMetrics.extractPath`. The splash holds the router in place via a `splashCompleteProvider` flag that the animation sets on completion, backed by a 3-second fallback timer so a stalled animation can never brick launch.

**Tech Stack:** Flutter 3.41.0 / Dart 3.11.0, Riverpod (`StateProvider`), GoRouter, `CustomPainter` + `dart:ui` `PathMetrics`, `flutter_launcher_icons`, `flutter_test` (widget + golden tests), `fake_async`.

**Spec:** `docs/superpowers/specs/2026-07-27-splash-logo-animation-design.md`

## Global Constraints

- **No TODO/FIXME/HACK comments in code.** Project rule from `CLAUDE.md`. Track follow-ups in Claude memory files only.
- **No hardcoded user-facing strings** — use `flutter gen-l10n` / `lib/l10n/app_en.arb`. (The splash has no text, so this should not come up; do not add any.)
- **Package name for imports:** `pottery_tracker` (e.g. `package:pottery_tracker/widgets/vase_logo.dart`).
- **Palette, exact values:** cream `#EDE5DA` (`AppColors.cream`), charcoal `#3C3C3C` (`AppColors.charcoal`), from `lib/core/constants/app_colors.dart`.
- **Animation duration:** 900ms, `Curves.easeInOut`.
- **Fallback timer:** 3 seconds.
- **Light mode only.** Dark mode is explicitly out of scope per the spec — do not add dark variants or `Theme.of(context).brightness` branches.
- **No skip gesture.** Deliberately deferred pending device testing. Do not add a `GestureDetector` to the splash.
- **No new dependencies.** Everything needed is already in `pubspec.yaml`.
- **Branch:** `feature/splash-logo-animation` (already created and checked out).
- Run `dart format .` before each commit; CI runs `dart analyze` + `flutter test` on PRs.

## File Structure

| File | Responsibility |
| --- | --- |
| `assets/icon/vase_logo.svg` | Design source for the silhouette. Not bundled, not loaded at runtime. |
| `lib/widgets/vase_logo.dart` | `buildVasePath` (shape truth), `VaseLogo` (static), `AnimatedVaseLogo` (draw-on). |
| `lib/providers/splash_provider.dart` | `splashCompleteProvider` — the single "splash may exit" flag. |
| `lib/router/app_router.dart` | Holds `/splash` until auth resolves **and** the flag is set. |
| `lib/features/auth/screens/splash_screen.dart` | Hosts the animation, sets the flag, arms the fallback timer. |
| `tool/generate_icon_test.dart` | Renders `buildVasePath` to `assets/icon/icon.png` at 1024×1024. |
| `test/widgets/vase_logo_test.dart` | Golden for the static mark; `onComplete` timing. |
| `test/features/auth/splash_screen_test.dart` | Flag-setting and fallback-timer behavior. |
| `test/router/app_router_test.dart` | Redirect hold logic. |

---

### Task 1: Approve the silhouette (USER GATE — no subagent)

**This task cannot be delegated.** It ends in a human design decision. Every later task consumes its output.

**Files:**
- Modify: `assets/icon/vase_logo.svg`

- [ ] **Step 1: Produce silhouette variants**

Author 3–4 gooseneck bud vase silhouettes as SVG in a `100×120` viewBox, single `<path>` each, `fill="none"`, `stroke="#3C3C3C"`, `stroke-linecap="round"`, `stroke-linejoin="round"`. Vary: neck length and flare, body fullness, foot presence, and degree of left/right asymmetry. Render each on cream `#EDE5DA`.

Hand-drawn quality comes from geometry, not stroke variation (Flutter cannot stroke a variable width — see spec): slight left/right asymmetry, a rim that is not perfectly level, and a small deliberate gap where the stroke opens and closes.

- [ ] **Step 2: Send the comparison sheet to the user**

Present all variants side by side at splash size (~120pt) using `SendUserFile` with `display: "render"`. Ask which silhouette to proceed with.

- [ ] **Step 3: Send the weight and color sheet**

For the chosen silhouette only, render a grid crossing stroke widths `{3.0, 4.0, 5.0, 6.0}` against near-black candidates `{#3C3C3C, #2C2C2C, #1A1A1A, #000000}`, **plus a 60×60pt render of each stroke width** so small-size legibility is judged before committing. Ask the user to pick one stroke width and one color.

- [ ] **Step 4: Record the decisions**

Write the approved single-path `d` attribute into `assets/icon/vase_logo.svg`, with the approved stroke width and color applied. This file is the input to Task 2.

- [ ] **Step 5: Commit**

```bash
git add assets/icon/vase_logo.svg
git commit -m "Add approved gooseneck vase silhouette as design source"
```

---

### Task 2: Port the silhouette into `buildVasePath` with a golden test

**Files:**
- Modify: `lib/widgets/vase_logo.dart` (full rewrite of the existing prototype)
- Create: `test/widgets/vase_logo_test.dart`

**Interfaces:**
- Consumes: the approved `d` attribute in `assets/icon/vase_logo.svg` (Task 1).
- Produces:
  - `Path buildVasePath(Size size)` — top-level function.
  - `class VaseLogo extends StatelessWidget` with named params `{required double size, Color? color, double strokeWidth}`.

**Conversion procedure (SVG `d` → Dart `Path`):** the SVG is authored in a `100×120` viewBox. Scale with `sx = size.width / 100`, `sy = size.height / 120`, and centre vertically with `oy = (size.height - 120 * sy) / 2`. Each SVG `C x1 y1, x2 y2, x y` becomes `path.cubicTo(x(x1), y(y1), x(x2), y(y2), x(x), y(y))`; `M x y` becomes `path.moveTo(x(x), y(y))`. Do **not** call `path.close()` — the open ends are the deliberate pen-lift gap.

- [ ] **Step 1: Write the failing test**

Create `test/widgets/vase_logo_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/core/constants/app_colors.dart';
import 'package:pottery_tracker/widgets/vase_logo.dart';

void main() {
  group('buildVasePath', () {
    test('scales to the requested size and stays inside its bounds', () {
      final path = buildVasePath(const Size(120, 120));
      final bounds = path.getBounds();

      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(120));
      expect(bounds.bottom, lessThanOrEqualTo(120));
    });

    test('is an open path so the pen-lift gap survives', () {
      final path = buildVasePath(const Size(120, 120));
      final metrics = path.computeMetrics().toList();

      expect(metrics, hasLength(1));
      expect(metrics.first.isClosed, isFalse);
      expect(metrics.first.length, greaterThan(0));
    });
  });

  group('VaseLogo', () {
    testWidgets('renders the mark', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            backgroundColor: AppColors.cream,
            body: Center(
              child: VaseLogo(size: 120, color: AppColors.charcoal),
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(VaseLogo),
        matchesGoldenFile('goldens/vase_logo.png'),
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widgets/vase_logo_test.dart`
Expected: FAIL — `buildVasePath` is not a top-level function yet (the prototype has it as a static on the private painter class).

- [ ] **Step 3: Rewrite `lib/widgets/vase_logo.dart`**

Replace the file entirely. Keep `VaseLogo` and `_VaseLogoPainter`, promote the path builder to a top-level function, and **delete the `filled` / `fillAfterTrace` / `fillOpacity` fill stage** — the mark is pure line and the option is now dead.

```dart
import 'package:flutter/material.dart';

/// The vase silhouette centreline, authored in a 100x120 design space and
/// scaled to [size]. Single source of shape truth for the logo, the splash
/// animation, and the generated app icon.
Path buildVasePath(Size size) {
  final sx = size.width / 100;
  final sy = size.height / 120;
  final oy = (size.height - 120 * sy) / 2;

  double x(double v) => v * sx;
  double y(double v) => v * sy + oy;

  final path = Path();
  // The path is intentionally left open — the gap is the pen lift.
  return path;
}

class VaseLogo extends StatelessWidget {
  const VaseLogo({
    super.key,
    required this.size,
    this.color,
    this.strokeWidth = 4.0,
  });

  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _VaseLogoPainter(
        color: color ?? Theme.of(context).colorScheme.primary,
        strokeWidth: strokeWidth,
        progress: 1.0,
      ),
    );
  }
}

class _VaseLogoPainter extends CustomPainter {
  _VaseLogoPainter({
    required this.color,
    required this.strokeWidth,
    required this.progress,
  });

  final Color color;
  final double strokeWidth;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = buildVasePath(size);

    if (progress >= 1.0) {
      canvas.drawPath(path, paint);
      return;
    }

    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
    }
  }

  @override
  bool shouldRepaint(_VaseLogoPainter oldDelegate) =>
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth ||
      progress != oldDelegate.progress;
}
```

Two values come from Task 1 and must be filled in here:

1. **The path body.** Take the single `d` attribute from `assets/icon/vase_logo.svg` and convert each command into `moveTo`/`cubicTo` calls per the procedure above, inserting them between `final path = Path();` and `return path;`. Keep only the pen-lift comment; do not leave any instruction comments behind (project rule: no TODO/FIXME/HACK in code).
2. **`strokeWidth`'s default** — the width approved in Task 1 Step 3.

- [ ] **Step 4: Generate the golden and verify**

Run: `flutter test --update-goldens test/widgets/vase_logo_test.dart`
Then: `flutter test test/widgets/vase_logo_test.dart`
Expected: PASS. Open `test/widgets/goldens/vase_logo.png` and confirm it looks like the approved silhouette — a golden that captures a bug is still a passing test.

- [ ] **Step 5: Commit**

```bash
dart format .
git add lib/widgets/vase_logo.dart test/widgets/
git commit -m "Port approved vase silhouette to buildVasePath with golden test"
```

---

### Task 3: Draw-on animation with completion callback

**Files:**
- Modify: `lib/widgets/vase_logo.dart`
- Modify: `test/widgets/vase_logo_test.dart`

**Interfaces:**
- Consumes: `buildVasePath`, `_VaseLogoPainter` (Task 2).
- Produces: `class AnimatedVaseLogo extends StatefulWidget` with named params
  `{required double size, Color? color, double strokeWidth, Duration duration, VoidCallback? onComplete}`.

- [ ] **Step 1: Write the failing test**

Append to `test/widgets/vase_logo_test.dart`:

```dart
  group('AnimatedVaseLogo', () {
    testWidgets('fires onComplete once the stroke finishes', (tester) async {
      var completed = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AnimatedVaseLogo(
                size: 120,
                color: AppColors.charcoal,
                duration: const Duration(milliseconds: 900),
                onComplete: () => completed++,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 400));
      expect(completed, 0, reason: 'still mid-stroke');

      await tester.pump(const Duration(milliseconds: 600));
      expect(completed, 1);

      await tester.pump(const Duration(milliseconds: 500));
      expect(completed, 1, reason: 'must not fire twice');
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widgets/vase_logo_test.dart`
Expected: FAIL — `AnimatedVaseLogo` is not defined.

- [ ] **Step 3: Add `AnimatedVaseLogo`**

Append to `lib/widgets/vase_logo.dart`:

```dart
class AnimatedVaseLogo extends StatefulWidget {
  const AnimatedVaseLogo({
    super.key,
    required this.size,
    this.color,
    this.strokeWidth = 4.0,
    this.duration = const Duration(milliseconds: 900),
    this.onComplete,
  });

  final double size;
  final Color? color;
  final double strokeWidth;
  final Duration duration;
  final VoidCallback? onComplete;

  @override
  State<AnimatedVaseLogo> createState() => _AnimatedVaseLogoState();
}

class _AnimatedVaseLogoState extends State<AnimatedVaseLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _progress = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete?.call();
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) => CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _VaseLogoPainter(
          color: color,
          strokeWidth: widget.strokeWidth,
          progress: _progress.value,
        ),
      ),
    );
  }
}
```

Match the `strokeWidth` default to `VaseLogo`'s.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/widgets/vase_logo_test.dart`
Expected: PASS, all four tests.

- [ ] **Step 5: Commit**

```bash
dart format .
git add lib/widgets/vase_logo.dart test/widgets/vase_logo_test.dart
git commit -m "Add AnimatedVaseLogo draw-on with completion callback"
```

---

### Task 4: Hold the router on `/splash` until the animation completes

**Files:**
- Create: `lib/providers/splash_provider.dart`
- Modify: `lib/router/app_router.dart:26-41`
- Create: `test/router/app_router_test.dart`

**Interfaces:**
- Produces: `final splashCompleteProvider = StateProvider<bool>((ref) => false);`

Today the redirect sends the user away the instant `authStatus != unknown`, which would cut the stroke off mid-draw. After this task the splash exits only when **both** conditions hold.

- [ ] **Step 1: Write the failing test**

Create `test/router/app_router_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/providers/splash_provider.dart';
import 'package:pottery_tracker/router/app_router.dart';

ProviderContainer _container({
  required AuthStatus status,
  required bool splashComplete,
}) {
  return ProviderContainer(
    overrides: [
      authProvider.overrideWith(
        (ref) => AuthNotifier.withState(AuthState(status: status)),
      ),
      splashCompleteProvider.overrideWith((ref) => splashComplete),
    ],
  );
}

void main() {
  group('splashCompleteProvider', () {
    test('defaults to false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(splashCompleteProvider), isFalse);
    });
  });

  group('router redirect', () {
    testWidgets('holds on /splash while auth is unknown', (tester) async {
      final container = _container(
        status: AuthStatus.unknown,
        splashComplete: true,
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/splash',
      );
    });

    testWidgets('holds on /splash while the animation is unfinished', (
      tester,
    ) async {
      final container = _container(
        status: AuthStatus.authenticated,
        splashComplete: false,
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/splash',
      );
    });

    testWidgets('leaves /splash once both conditions are met', (tester) async {
      final container = _container(
        status: AuthStatus.unauthenticated,
        splashComplete: true,
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/sign-in',
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/router/app_router_test.dart`
Expected: FAIL — `package:pottery_tracker/providers/splash_provider.dart` does not exist.

- [ ] **Step 3: Create the provider**

Create `lib/providers/splash_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set to true once the splash draw-on animation has finished (or its
/// fallback timer has fired). The router will not leave `/splash` until this
/// is true, so the launch animation is never cut off mid-stroke.
final splashCompleteProvider = StateProvider<bool>((ref) => false);
```

- [ ] **Step 4: Update the redirect**

In `lib/router/app_router.dart`, add the import:

```dart
import '../providers/splash_provider.dart';
```

Watch the flag alongside auth status, just below the existing `authStatus` watch:

```dart
final authStatus = ref.watch(authProvider.select((s) => s.status));
final splashComplete = ref.watch(splashCompleteProvider);
```

Then replace the `if (authStatus == AuthStatus.unknown) { ... }` block at the top of `redirect` with:

```dart
      if (authStatus == AuthStatus.unknown || !splashComplete) {
        if (loc != '/splash') return '/splash';
        return null;
      }
```

Leave the rest of `redirect` unchanged.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/router/app_router_test.dart`
Expected: PASS, all four tests.

- [ ] **Step 6: Commit**

```bash
dart format .
git add lib/providers/splash_provider.dart lib/router/app_router.dart test/router/
git commit -m "Hold splash route until draw-on animation completes"
```

---

### Task 5: Wire the splash screen with a fallback timer

**Files:**
- Modify: `lib/features/auth/screens/splash_screen.dart` (full rewrite)
- Create: `test/features/auth/splash_screen_test.dart`

**Interfaces:**
- Consumes: `AnimatedVaseLogo` (Task 3), `splashCompleteProvider` (Task 4).

If `onComplete` never fires — disposed widget, stalled ticker, an exception inside the painter — the redirect in Task 4 would strand the user on the splash forever. The fallback timer is what makes that impossible.

- [ ] **Step 1: Write the failing test**

Create `test/features/auth/splash_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/features/auth/screens/splash_screen.dart';
import 'package:pottery_tracker/providers/splash_provider.dart';
import 'package:pottery_tracker/widgets/vase_logo.dart';

Future<ProviderContainer> _pumpSplash(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SplashScreen()),
    ),
  );
  return container;
}

void main() {
  testWidgets('renders the animated vase mark', (tester) async {
    await _pumpSplash(tester);
    expect(find.byType(AnimatedVaseLogo), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('sets splashComplete when the stroke finishes', (tester) async {
    final container = await _pumpSplash(tester);

    expect(container.read(splashCompleteProvider), isFalse);

    await tester.pump(const Duration(milliseconds: 950));
    expect(container.read(splashCompleteProvider), isTrue);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('fallback timer releases the splash if the stroke stalls', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SplashScreen(animationDuration: Duration(days: 1)),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 950));
    expect(
      container.read(splashCompleteProvider),
      isFalse,
      reason: 'animation is still running',
    );

    await tester.pump(const Duration(seconds: 3));
    expect(container.read(splashCompleteProvider), isTrue);
  });

  testWidgets('cancels the fallback timer on dispose', (tester) async {
    await _pumpSplash(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 5));
    // A surviving timer fails the test with "A Timer is still pending".
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/features/auth/splash_screen_test.dart`
Expected: FAIL — `SplashScreen` has no `animationDuration` parameter and renders an `Icon`, not an `AnimatedVaseLogo`.

- [ ] **Step 3: Rewrite the splash screen**

Replace `lib/features/auth/screens/splash_screen.dart` entirely:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/splash_provider.dart';
import '../../../widgets/vase_logo.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({
    super.key,
    this.animationDuration = const Duration(milliseconds: 900),
  });

  final Duration animationDuration;

  /// Upper bound on how long the splash may hold the router, regardless of
  /// what the animation does. A stalled draw-on must never block launch.
  static const fallback = Duration(seconds: 3);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _fallbackTimer;

  @override
  void initState() {
    super.initState();
    _fallbackTimer = Timer(SplashScreen.fallback, _release);
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    super.dispose();
  }

  void _release() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    if (!mounted) return;
    ref.read(splashCompleteProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Center(
        child: AnimatedVaseLogo(
          size: 120,
          color: AppColors.charcoal,
          duration: widget.animationDuration,
          onComplete: _release,
        ),
      ),
    );
  }
}
```

Use the stroke width and colour approved in Task 1 — if the approved colour is not `AppColors.charcoal`, add the chosen value to `lib/core/constants/app_colors.dart` as a named constant rather than inlining a hex literal.

Note the removed `CupertinoActivityIndicator`: the draw-on is itself the progress signal, and Android's guidance is that no additional spinner is needed once the splash only dismisses when the app is ready.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/features/auth/splash_screen_test.dart`
Expected: PASS, all four tests.

- [ ] **Step 5: Run the full suite**

Run: `flutter test`
Expected: PASS. The router change in Task 4 affects app-wide navigation — any existing test that renders the full router may now land on `/splash`. If one fails, override `splashCompleteProvider` to `true` in that test's `overrides` rather than weakening the redirect.

- [ ] **Step 6: Commit**

```bash
dart format .
git add lib/features/auth/screens/splash_screen.dart test/features/auth/
git commit -m "Replace splash placeholder with animated vase mark"
```

---

### Task 6: Match the native launch screens to the splash's first frame

**Files:**
- Modify: `ios/Runner/Base.lproj/LaunchScreen.storyboard`
- Modify: `android/app/src/main/res/drawable/launch_background.xml`
- Modify: `android/app/src/main/res/drawable-v21/launch_background.xml`

The native launch screen shows before Flutter boots. If it does not match the splash's frame at `progress = 0` — solid cream, nothing drawn — the handoff flashes. Apple's HIG also forbids branding or animation on the launch screen itself, so it must stay empty.

- [ ] **Step 1: Set the Android launch background to solid cream**

Replace the contents of **both** `launch_background.xml` files (the `drawable/` and `drawable-v21/` copies) with:

```xml
<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/launch_background" />
</layer-list>
```

Create `android/app/src/main/res/values/colors.xml` if it does not exist, and ensure it contains:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="launch_background">#EDE5DA</color>
</resources>
```

If a `<color name="launch_background">` entry already exists, update its value rather than adding a duplicate.

- [ ] **Step 2: Set the iOS launch screen to solid cream**

In `ios/Runner/Base.lproj/LaunchScreen.storyboard`, remove any `<imageView>` for `LaunchImage` and set the root view's background colour to cream by giving the view this child:

```xml
<color key="backgroundColor" red="0.929" green="0.898" blue="0.855" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
```

Those components are `#EDE5DA` normalised to 0–1 (237/255, 229/255, 218/255).

- [ ] **Step 3: Verify on the simulator**

Run: `flutter run -d B275B8A5-FB5F-4958-B32D-8882F8823A97`
Expected: launch shows cream, then the vase draws itself on, with **no visible flash or colour change** at the handoff. Watch specifically for a white frame between the native screen and the Flutter screen — that means the storyboard colour did not take.

- [ ] **Step 4: Commit**

```bash
git add ios/Runner/Base.lproj/LaunchScreen.storyboard android/app/src/main/res/
git commit -m "Match native launch screens to splash first frame"
```

---

### Task 7: Regenerate the app icon from the approved path

**Files:**
- Create: `tool/generate_icon_test.dart`
- Modify: `assets/icon/icon.png`

Deriving the icon from `buildVasePath` rather than exporting it by hand keeps the launch animation and the home-screen icon from drifting apart. PNG encoding needs the Flutter engine, so the generator runs as a widget test.

- [ ] **Step 1: Write the generator**

Create `tool/generate_icon_test.dart`:

```dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/core/constants/app_colors.dart';
import 'package:pottery_tracker/widgets/vase_logo.dart';

/// Renders the approved vase path to assets/icon/icon.png at 1024x1024.
/// Run with: flutter test tool/generate_icon_test.dart
void main() {
  testWidgets('generate app icon', (tester) async {
    const canvas = 1024.0;
    const markSize = 620.0;
    const stroke = 34.0;

    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder);

    c.drawRect(
      const Rect.fromLTWH(0, 0, canvas, canvas),
      Paint()..color = AppColors.cream,
    );

    final inset = (canvas - markSize) / 2;
    c.save();
    c.translate(inset, inset);
    c.drawPath(
      buildVasePath(const Size(markSize, markSize)),
      Paint()
        ..color = AppColors.charcoal
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    c.restore();

    final image = await recorder.endRecording().toImage(
      canvas.toInt(),
      canvas.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    File('assets/icon/icon.png').writeAsBytesSync(
      bytes!.buffer.asUint8List(),
    );
  });
}
```

`stroke` is scaled from the approved splash stroke width: the mark renders at 620px here versus 120pt on the splash, so multiply the approved width by ~5.2. Adjust if the result looks too heavy at 60pt.

- [ ] **Step 2: Generate the PNG**

Run: `flutter test tool/generate_icon_test.dart`
Then open `assets/icon/icon.png` and confirm it is a cream square with a centred charcoal vase, correctly proportioned and not clipped.

- [ ] **Step 3: Regenerate platform icons**

Run: `dart run flutter_launcher_icons`
Expected: iOS, Android, macOS, and web icon sets are rewritten. `remove_alpha_ios: true` is already configured, so no transparency warning should appear.

- [ ] **Step 4: Verify at real size**

Run: `flutter run -d B275B8A5-FB5F-4958-B32D-8882F8823A97`
Then background the app and look at the home screen. Expected: the icon reads clearly at its actual size and does not look faint next to other icons. If the stroke looks thin, raise `stroke` in Step 1 and repeat from Step 2.

- [ ] **Step 5: Commit**

```bash
git add tool/generate_icon_test.dart assets/icon/icon.png ios/Runner/Assets.xcassets android/app/src/main/res macos web
git commit -m "Regenerate app icon from the vase path"
```

---

### Task 8: Update the test plan and project docs

**Files:**
- Modify: `TEST_PLAN.md`
- Modify: `ROADMAP.md`

- [ ] **Step 1: Add splash cases to `TEST_PLAN.md`**

Add a section after "1. Authentication & Onboarding":

```markdown
### Splash Screen (`/splash`)
- [ ] Vase mark draws itself on over ~900ms at launch
- [ ] No flash or colour change between the native launch screen and the splash
- [ ] Animation always completes — never cut off mid-stroke
- [ ] App proceeds to Album (signed in) or Sign-In (signed out) once the stroke finishes
- [ ] Launch is not blocked if the animation stalls (3s fallback)
- [ ] App icon on the home screen matches the drawn mark
```

Update the changelog table at the top of the file with a row for this feature, matching the existing format.

- [ ] **Step 2: Tick the roadmap item**

In `ROADMAP.md`, under "Design & Branding", change:

```markdown
- [ ] **In-app branding redesign** — incorporate app icon or other imagery into the app UI (e.g., sign-in screen, empty states, splash screen)
```

to mark the splash portion done, leaving sign-in and empty states open:

```markdown
- [ ] **In-app branding redesign** — splash screen done (animated vase mark); sign-in screen and empty states still to do
```

- [ ] **Step 3: Verify the whole suite and analyzer**

Run: `flutter test && dart analyze`
Expected: all tests pass, no analyzer issues.

- [ ] **Step 4: Commit**

```bash
git add TEST_PLAN.md ROADMAP.md
git commit -m "Document splash animation in test plan and roadmap"
```

---

## Manual Verification

Automated tests cannot judge whether the animation *feels* right. After Task 8, on the simulator and ideally on the physical iPhone (`00008130-0006481026E2001C`):

1. Cold-launch the app several times. The 900ms hold should read as deliberate, not sluggish. If it drags, this is the moment to reconsider tap-to-skip — the spec deliberately left that reversible, and `splashCompleteProvider` is the only thing a skip gesture needs to touch.
2. Confirm the stroke reads as hand-drawn rather than plotted at real size. If it looks flat, that is the trigger to revisit Approach B (ribbon fill) from the spec — the approved silhouette carries over.
3. Check the home-screen icon beside dense icons like Instagram or Gmail.
