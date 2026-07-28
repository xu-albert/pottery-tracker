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
- **Palette, exact values:** cream `#EDE5DA` (`AppColors.cream`) from `lib/core/constants/app_colors.dart`.
- **Approved design values (locked 2026-07-27 — do not substitute):**
  - Silhouette: the three subpaths in `assets/icon/vase_logo.svg`. A *yuhuchunping* — Ming pear-shaped bud vase: trumpet lip, long neck widening downward, belly widest low, raised footring.
  - Mark colour: **`#313131`**. Add to `lib/core/constants/app_colors.dart` as `AppColors.ink` — it is not in the palette yet.
  - Splash stroke width: **3.6**; the footring subpath draws at **2.7** (0.75× the body weight).
  - Icon stroke width: **1.55× the splash weight** (5.58 at equivalent scale).
  - The footring gap is the tightest part of the drawing and closes up if the stroke is made heavier. Do not increase these weights.
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

### Task 1: Approve the silhouette (USER GATE — COMPLETE)

**Completed 2026-07-27.** Ran as nine design rounds with the user; the approved
silhouette, stroke weights and colour are recorded in the Global Constraints above and
in `assets/icon/vase_logo.svg`. The steps below are kept as a record of how the values
were arrived at — **do not re-run them.**

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
  - `class VaseLogoPainter extends CustomPainter` with named params `{required Color color, required double strokeWidth, required double progress}`. **Public, not private** — Task 7's icon generator reuses it so the icon and the animation cannot drift apart.

**Conversion procedure (SVG `d` → Dart `Path`):** the SVG is authored in a `100×120` viewBox. Scale with `sx = size.width / 100`, `sy = size.height / 120`, and centre vertically with `oy = (size.height - 120 * sy) / 2`. Each SVG `C x1 y1, x2 y2, x y` becomes `path.cubicTo(x(x1), y(y1), x(x2), y(y2), x(x), y(y))`; `M x y` becomes `path.moveTo(x(x), y(y))`.

**The approved mark has three subpaths**, and all three go into the single `Path` returned by `buildVasePath`, appended in this order:

1. **rim** — the mouth ellipse. Ends with `Z`, so call `path.close()` after its last `cubicTo`. This is the only closed subpath.
2. **body** — the outline: trumpet lip, down the left side, across the base, up the right. Open; do **not** close it. Its two ends stop at the lip where the rim ellipse meets them.
3. **foot** — the footring line. Open; do **not** close it.

Do not merge, reorder, or drop a subpath — the footring line in particular is load-bearing. Without it the body's foot geometry reads as a drawing error (this was verified during design; see the spec).

The footring strokes thinner than the other two (0.75×). `computeMetrics()` yields metrics in subpath order, so the painter walks them with an index and applies the lighter weight at index 2. That single loop covers both the traced and the finished states — there is no need for a separate `progress >= 1.0` branch, since `extractPath(0, length * 1.0)` is the whole subpath. Name the index as a constant rather than writing a bare `i == 2`.

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

    test('has rim, body and footring as three subpaths in order', () {
      final path = buildVasePath(const Size(120, 120));
      final metrics = path.computeMetrics().toList();

      expect(metrics, hasLength(3));
      expect(metrics[0].isClosed, isTrue, reason: 'rim ellipse is closed');
      expect(metrics[1].isClosed, isFalse, reason: 'body outline is open');
      expect(metrics[2].isClosed, isFalse, reason: 'footring line is open');

      // The footring is much the shortest run; body much the longest.
      expect(metrics[2].length, lessThan(metrics[0].length));
      expect(metrics[1].length, greaterThan(metrics[0].length));
    });
  });

  group('VaseLogo', () {
    testWidgets('renders the mark', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            backgroundColor: AppColors.cream,
            body: Center(
              child: VaseLogo(size: 120, color: AppColors.ink),
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

Replace the file entirely. Keep `VaseLogo` and `VaseLogoPainter`, promote the path builder to a top-level function, and **delete the `filled` / `fillAfterTrace` / `fillOpacity` fill stage** — the mark is pure line and the option is now dead.

```dart
import 'package:flutter/material.dart';

/// The vase silhouette centreline, authored in a 100x120 design space and
/// scaled to [size]. Single source of shape truth for the logo, the splash
/// animation, and the generated app icon.
/// Index of the footring subpath within [buildVasePath]'s result. It strokes
/// lighter than the rim and body.
const _footringSubpath = 2;

/// How much lighter the footring draws than the body.
const _footringWeightRatio = 0.75;

Path buildVasePath(Size size) {
  final sx = size.width / 100;
  final sy = size.height / 120;
  final oy = (size.height - 120 * sy) / 2;

  double x(double v) => v * sx;
  double y(double v) => v * sy + oy;

  final path = Path();
  return path;
}

class VaseLogo extends StatelessWidget {
  const VaseLogo({
    super.key,
    required this.size,
    this.color,
    this.strokeWidth = 3.6,
  });

  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: VaseLogoPainter(
        color: color ?? Theme.of(context).colorScheme.primary,
        strokeWidth: strokeWidth,
        progress: 1.0,
      ),
    );
  }
}

class VaseLogoPainter extends CustomPainter {
  VaseLogoPainter({
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
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final metrics = buildVasePath(size).computeMetrics().toList();

    for (var i = 0; i < metrics.length; i++) {
      final metric = metrics[i];
      paint.strokeWidth = i == _footringSubpath
          ? strokeWidth * _footringWeightRatio
          : strokeWidth;
      canvas.drawPath(
        metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(VaseLogoPainter oldDelegate) =>
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth ||
      progress != oldDelegate.progress;
}
```

Fill in the body of `buildVasePath` from the three `d` attributes in
`assets/icon/vase_logo.svg`, converting each command into `moveTo` / `cubicTo` /
`close` calls per the procedure above and appending all three subpaths in order
(rim, body, foot) between `final path = Path();` and `return path;`.

Add `static const ink = Color(0xFF313131);` to `AppColors` in
`lib/core/constants/app_colors.dart` — the mark's approved colour, which the palette
does not yet have.

Leave no instruction comments behind (project rule: no TODO/FIXME/HACK in code).

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
- Consumes: `buildVasePath`, `VaseLogoPainter` (Task 2).
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
                color: AppColors.ink,
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
    this.strokeWidth = 3.6,
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
        painter: VaseLogoPainter(
          color: color,
          strokeWidth: widget.strokeWidth,
          progress: _progress.value,
        ),
      ),
    );
  }
}
```

Keep the `strokeWidth` default identical to `VaseLogo`'s (3.6).

**On the three subpaths:** the painter's loop advances every subpath by the same
*fraction* of its own length, so rim, body and footring all begin and finish together
rather than drawing one after another. That is intended — it reads as the whole mark
resolving at once. Do not sequence them; a staggered version was considered and would
divide the 900ms three ways, leaving each run too fast to register.

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
          color: AppColors.ink,
          duration: widget.animationDuration,
          onComplete: _release,
        ),
      ),
    );
  }
}
```

`AppColors.ink` (`#313131`) is added in Task 2; the splash consumes it. Leave `strokeWidth` unset so it takes `AnimatedVaseLogo`'s 3.6 default rather than restating the number here.

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
  testWidgets('generates a full-bleed 1024px icon with the mark inside', (
    tester,
  ) async {
    const canvas = 1024.0;
    const markSize = 620.0;
    const stroke = 18.6;

    // A path that spills past the canvas would ship a clipped icon.
    final markBounds = buildVasePath(const Size(markSize, markSize)).getBounds();
    expect(markBounds.left, greaterThanOrEqualTo(-stroke / 2));
    expect(markBounds.top, greaterThanOrEqualTo(-stroke / 2));
    expect(markBounds.right, lessThanOrEqualTo(markSize + stroke / 2));
    expect(markBounds.bottom, lessThanOrEqualTo(markSize + stroke / 2));

    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder);

    c.drawRect(
      const Rect.fromLTWH(0, 0, canvas, canvas),
      Paint()..color = AppColors.cream,
    );

    final inset = (canvas - markSize) / 2;
    c.save();
    c.translate(inset, inset);
    // Reuse the widget's painter so the icon and the splash animation cannot
    // drift apart — it already applies the lighter footring weight.
    VaseLogoPainter(
      color: AppColors.ink,
      strokeWidth: stroke,
      progress: 1.0,
    ).paint(c, const Size(markSize, markSize));
    c.restore();

    final image = await recorder.endRecording().toImage(
      canvas.toInt(),
      canvas.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    expect(image.width, 1024);
    expect(image.height, 1024);
    expect(bytes, isNotNull);

    final file = File('assets/icon/icon.png')
      ..writeAsBytesSync(bytes!.buffer.asUint8List());

    // A near-empty PNG means the path failed to render.
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(2000));
  });
}
```

`stroke = 18.6` is the approved 3.6 splash weight carried to this canvas: the mark renders at 620px here versus 120pt on the splash (5.17×), times the 1.55× icon uplift the design round settled on for small-size legibility, then rounded. The footring is drawn by the same painter loop at 0.75× of that.

If the icon looks too heavy at real size, the footring gap is what closes first — check it before adjusting anything else.

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
