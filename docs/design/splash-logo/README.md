# Splash Logo — Design Archive

Every iteration behind the Pottery Tracker vase mark, kept for a future write-up.

Each round is stored twice: as **HTML** (vector — open in a browser and zoom freely,
and the SVG path data is readable in the source) and as **PNG** (a 2× headless-Chrome
screenshot). The HTML files are the primary artifact; the PNGs exist so the rounds can
be viewed without a browser.

**Final result:** `assets/icon/vase_logo.svg` — a *yuhuchunping* (Ming pear-shaped bud
vase), stroke 3.6, `#313131` on cream `#EDE5DA`. The runtime source of truth is
`buildVasePath()` in `lib/widgets/vase_logo.dart`.

---

## The brief

Replace a placeholder splash icon with a mark that **draws itself on** as the app
opens, and reuse it as the app icon. The stated direction: keep the gooseneck vase of
the existing icon, make it a simple hand-drawn silhouette, HEYTEA-inspired.

One constraint shaped everything that followed: **Flutter's canvas cannot stroke a path
with varying width.** `drawPath` with a stroke paint gives one uniform thickness, so
the pressure variation that makes real ink look drawn is unavailable. Every bit of
"hand-drawn" quality had to come from geometry instead.

---

## The rounds

### Round 1 — `round-01-gooseneck`
Four silhouettes, single open paths, the mouth gap doubling as the pen-lift.

**They read as light bulbs.** No foot and no lip flare: the body curved into a round
bottom like a balloon, and the two neck lines ran parallel to the top like antennae.
Presented with the honest assessment rather than asking for a pick.

### Round 2 — `round-02-lip-and-base`
Added a flared lip and a wider base. Better, but the "flat" base was still built from
cubics that rounded off, so it stayed balloon-ish.

### Round 3 — `round-03-flat-foot`
Replaced the base cubics with an actual straight segment, and made the foot visibly
narrower than the belly. **This is where they started reading as vases.** A rounded
bottom says balloon; a foot says vessel.

### Round 4 — `round-04-rim-ellipse`
The idea to add a **crooked rim ellipse** came from the client, and it was the single
biggest improvement in the whole process — it turned a flat outline into a vessel with
an opening. Four treatments: rim only, wider tilted rim, rim + foot arc, rim + inner
highlight.

Cost worth noting: the mark became **three subpaths** instead of one, which later
invalidated the implementation plan's single-path assumptions.

Also a drift: chasing the 3D cue pushed the flare down and shortened the neck, so these
read closer to bottles than to the gooseneck the brief asked for.

### Round 5 — `round-05-viewpoint`
Brief became "viewed from up top and to the side."

**A vase is rotationally symmetric, so orbiting it horizontally changes nothing.**
Moving "to the side" of a bud vase produces an identical silhouette. Only elevation
(which opens the rim ellipse) or tilting the vase itself changes what you see. Named
that explicitly rather than guessing, and rendered four readings of the request.

Result: rotating the whole vase tilted its *straight* base too, so it read as
**falling over** — a straight line, tilted, implies tilted ground.

### Round 6 — `round-06-lean`
Fix: keep the lean, but curve the foot. A curved base has no implied ground line, so
the lean reads as the vase leaning rather than the world tipping. Plus a longer neck
and a narrower foot.

### The reference
The client supplied a photo of a Ming **yuhuchunping** — a pear-shaped vase. Not
included here (third-party photo), but it changed everything by making the target
concrete: trumpet lip flaring sharply, neck narrowest near the top and widening all the
way down, widest point about two-thirds down, and a distinct raised footring.

**One reference image collapsed six rounds of guessing.**

### Round 7 — `round-07-yuhuchunping`
Redrawn to the reference. Much closer — but the body-to-foot transition made a squared
notch that read as a drawing error on three of the four variants. On `7-2` it worked,
because an added footring line explained the step as intentional. `7-2` was the pick.

### Round 8 — `round-08-smoothed-foot`
Smoothed the notch into continuous curvature.

**This was a mistake.** The Ming form *has* a raised footring; smoothing removed it, so
the vases now rested directly on their own belly — a different, less accurate object.
The notch was bad execution of a good idea, not a bad idea.

### Round 8b — `round-08b-compare-07-08`
Both rounds on one page, at the client's request. Seeing them together is what exposed
the error — neither round alone made it obvious. **Side-by-side comparison caught what
sequential review missed.**

### Round 9 — `round-09-footring`
Three refined footrings against `7-2` as a control, with a **2× detail crop of just the
foot**. The zoom was the decisive view: it showed `7-2`'s footring line converging with
its base toward the ends, so the foot tapers to a wedge rather than holding an even
band. The refined `A` fixed exactly that.

`7-2` was chosen anyway — the wedge doesn't register at real viewing size.

### Rounds 10 & 11 — `round-10-weight-and-shade`, `round-11-final-ranges`
Stroke weights and near-black shades, at splash size and at 60pt icon size.

**The footring turned out to be the binding constraint on stroke weight** — it is the
narrowest gap in the drawing, so it clogs first. At splash size it starts filling in
around 6.0; at icon size, where everything scales 1.55×, it is nearly shut by 7.0. That
ceiling is tighter than the neck or body would ever have imposed.

Round 11 generated the requested finer ranges: weights 3.0→4.8 in 0.3 steps, and seven
interpolated shades from `#3C3C3C` to `#1A1A1A`.

**Final: stroke 3.6, `#313131`.**

### Round 12 — `round-12-aspect-distortion`
Not a design round. After the shape was locked and ported to Dart, the implementation
rendered the mark **20% too wide**.

The design space is 100×120 — a 5:6 ratio. The porting instructions scaled the axes
independently (`sx = width/100`, `sy = height/120`) while the widget passed a *square*
box, so at `Size(120, 120)` the x axis scaled by 1.2 and the y axis by 1.0. Measured
bounds aspect: **0.699** against the approved **0.582**. Every preview approved during
design had been rendered from `viewBox="0 0 100 120"`, which preserves the ratio; the
Dart port silently did not.

The archived page shows both at equal height, plus an overlay. The stretch reads
hardest in the neck — the slenderness the whole form depends on.

Two things about how it was caught are worth recording:

- **The golden test could not catch it.** A golden captures whatever the code produces,
  so it locks in a wrong shape just as happily as a right one, and passes forever after.
- **The code review didn't catch it either** — it flagged that the vertical-centering
  term was always exactly zero, and graded that Minor. That dead term was a *symptom* of
  the same broken formula, but the reviewer stopped at the arithmetic without asking what
  the shape actually came out looking like.

What found it was measuring the rendered bounds and comparing them against the design's
ratio. The fix scales by `min(w/100, h/120)` and centres on both axes, so the mark
letterboxes in any box and no caller can distort it — plus an aspect assertion so it
cannot silently return.

### Rounds 13 & 14 — `round-13-icon-at-real-sizes`, `round-14-icon-scale-in-tile`
Once the mark was in code, the generated `icon.png` had to be judged as an *icon*, not as
a drawing. Round 13 renders it at the sizes iOS actually uses — 180, 120, 80, 60, 40px.
Viewed at 1024 the stroke looked far too heavy; at real sizes it reads cleanly all the way
down. **Judging a mark at its authoring size tells you almost nothing about how it ships.**

Round 14 varies how much of the tile the vase fills — 61%, 66%, 72%, 78% — at four tile
sizes. 61% (the first generated value) reads timid beside denser home-screen icons; 78%
crowds the rounded corners. **72% was chosen**, and `markSize` in
`tool/generate_icon_test.dart` set to 740 of 1024.

A convenient property made this cheap: because the icon's stroke is derived from
`markSize`, changing it is a pure uniform zoom of the mark within a fixed canvas. The
comparison could therefore be composited in the browser from a single rendered PNG,
instead of re-rendering four times through Flutter.

### Round 15 — `round-15-device-*` — it actually works
Captured on the iPhone 16 Pro simulator: the vase app icon zooming open, the cream
launch screen, then the mark drawing itself on — rim first, down the neck, body, footring
last — completing once and holding before the app moves on. `round-15-device-launch.mp4`
is the raw recording; the PNGs are frame sequences at 20fps.

The verification itself produced a lesson worth keeping. The first attempt installed a
`flutter build ios --simulator --no-codesign` build directly with `simctl`, and the app
sat on a blank cream screen forever. That looked exactly like a critical bug in this
feature. It wasn't: an unsigned build has no keychain entitlement, so
`SecItemCopyMatching` fails with `-34018`, `flutter_secure_storage` cannot read the
SQLCipher key, and `AppDatabase.open()` throws in `main()` before `runApp` is ever
called — leaving the native launch screen up indefinitely.

Two things fell out of that:

- **Verify with the same toolchain that ships.** `flutter run` signs the app; a
  hand-installed unsigned build silently loses entitlements and fails in ways that
  impersonate application bugs.
- **A blank launch screen is now an ambiguous failure mode.** Because the native launch
  screen is deliberately solid cream, "stuck before `runApp`" and "showing the splash"
  look identical. `main()` awaits `AppDatabase.open()` and `SharedPreferences` with no
  try/catch, so any failure there is an unrecoverable blank screen with no error UI.
  Worth guarding — noted as a follow-up, not fixed here since it predates this work.

### Rounds 16 & 17 — `round-16-icon-ground-sepia`, `round-17-ink-on-sepia`
Seeing the icon on a real home screen surfaced what no isolated render had: against
saturated neighbours, `#EDE5DA` reads as a **white square with a drawing on it**, not as a
warm ceramic tile. Round 16 renders eight grounds from the original cream through to a
toasted tan, at 180px and 60px, plus a mock home-screen row — which is the view that
makes the problem obvious.

**`#E3D3BD` was chosen.** Past roughly `#CFB490` the tile drifts from ceramic toward
khaki and starts competing with the mark rather than supporting it.

Round 17 tested a warmer ink (`#2E241C`) against the neutral `#313131` on that ground.
Real at 180px, essentially invisible at 60px — so the neutral ink stayed, keeping one ink
constant shared by the icon and the splash.

**The ground change is icon-only.** In-app surfaces stay `cream`; `AppColors.iconGround`
exists solely for the generated icon. The colour shift happens during the icon-zoom
transition, where it reads as the app opening rather than as an inconsistency.

### Rounds 18 & 19 — `round-18-animation-variants`, `round-19-symmetric-growth`
The first device viewing produced three separate notes: the animation drew "from both
sides", felt slow, and cut too abruptly into the app. Round 18 is an interactive harness
— open the HTML, every variant has a replay button — with eight draw-on timings and four
splash-to-app transitions.

**"From both sides"** was the rim ellipse starting near the right lip at the same moment
the body started at the left. Sequencing the subpaths removes it.

**"Drawn twice"** turned out to be neither a rendering bug nor bad path data, and it is
worth recording because the cause is non-obvious. The body is one continuous outline, so
tracing it travels *down the left side, across the base, and back up the right*. The
vase's neck is two nearly-parallel lines — and they sit at **opposite ends of the
timeline**, roughly 600ms apart at the original pace. Watching at speed, the second one
reads as the first being redrawn.

That is inherent to tracing a silhouette, and no amount of re-timing a single travelling
stroke fixes it. Round 19's **J / K / L** take a different approach: split the body into
its two profiles and grow them **together**, so paired features appear simultaneously. J
rises from the base to the lip — which also happens to be the right metaphor for a
pottery app, reading as the vessel being pulled up on a wheel. K is the same symmetry
falling from the lip instead.

Round 19 also carries a **3× slow-motion toggle**, because at 600ms the mechanics are
too fast to diagnose by eye — the thing that made the doubling explicable was watching
it slowed down.

### Round 20 — `round-20-left-start-easing`
Two refinements to B. The rim ellipse was re-rooted from its rightmost point `(64, 9.8)`
to its **leftmost** `(36, 9.9)` — the same place the body begins — so both strokes leave
one point and diverge, the rim sweeping up over the top while the body descends. That
reads as a single gesture splitting rather than two marks appearing in different places.

The second is easing. `easeInOut` is already slow-fast-slow, just the mildest version;
the round compares it against `easeInOutCubic`, `Quart` and `Quint`, with each variant's
speed profile drawn in the corner of its tile so the curve and its effect sit
side by side. Steeper curves read as more deliberate but risk looking like a stutter at
short durations.

The footring is the one stroke that cannot share the start point — it lives at the base.
It starts at its left end instead, so everything still travels left to right.

### Round 21 — `round-21-footring-direction`
Timing locked to `easeInOutQuart` at 750ms; the only variable is which end of the
footring the stroke starts from.

With the rim re-rooted to the top-left, *every* stroke was travelling left to right —
coherent, but uniform to the point of feeling mechanical. Reversing the footring so it
runs right-to-left gives the drawing a counterpoint: two strokes sweeping out from one
corner, one running back the other way.

At real speed the difference is close to subliminal, which is the interesting part — the
round ships with a **4× slow-motion toggle** and a direction-arrow overlay, because the
choice cannot honestly be made at 750ms. Variants R and S delay the footring so the
opposing direction becomes legible rather than merely felt.

### Round 22 — `round-22-footring-follows-stroke`
The footring still read as a separate mark. The instinct was that it should be part of
the pot's stroke rather than drawn independently — correct, but the fix is not the
obvious one.

**It cannot literally join the stroke.** The footring is a chord between `(33,100)` and
`(67,100)`, two points the body outline *already passes through*. Making it continuous
would require the pen to double back over ground it had covered. It is a detail line, not
part of the silhouette.

What actually made it feel disconnected was timing: it ran its own 750ms, so it finished
long before the body's stroke arrived at the base. The fix is to drive every subpath from
**one clock** and gate the footring on the body's own progress. Measuring where the body
path passes those two points gives a crossing window of **41% → 59%** of its length —
draw the ring only across that window and it appears under the pen as it sweeps by.

This round is also the first to abandon CSS/Web-Animations per-path timing for a single
`requestAnimationFrame` loop, because "follows the stroke" is a *relationship* between
paths, not four independent timelines. It carries a **pen-position marker** so the
relationship can actually be seen rather than assumed.

### Round 23 — `round-23-footring-left-to-right`
The footring reversal from round 21 was correct while the strokes were independent, and
wrong once they were synced — a decision that stopped being valid when its premise
changed.

The pen crosses the base **left to right**, reaching `(33,100)` at 41% and `(67,100)` at
59%. Once the ring is gated on that window, drawing it right-to-left runs it *against*
the stroke it is meant to be following, closing toward the pen instead of trailing it.
The asymmetry that read as deliberate counterpoint among independent marks reads as a
mistake among synced ones.

The round keeps a `W-rev` tile drawn against the pen, so the difference is visible rather
than asserted.

### Round 24 — `round-24-transitions-final-drawon`
The splash-to-app handoff, re-rendered with the *approved* draw-on rather than the
placeholder used in round 18 — a transition can only be judged against the animation it
actually follows.

**T4 was chosen:** a 250ms beat, then the mark fades and scales to 1.16 over 400ms while
the app arrives beneath it. Reads as moving past the mark rather than the mark being
switched off.

### Round 25 — `round-25-final-device-*`
The shipped sequence captured on device: a single mark at the top-left, the stroke
descending and the vessel resolving, a beat on the finished drawing, then the mark fading
and scaling away as the app arrives. `round-25-final-device-capture.mp4` is the raw
recording.

Verified against the three complaints that started this stretch of work: the stroke now
grows from one point rather than appearing on both sides, the eased 750ms reads as
deliberate rather than slow, and the handoff is a lift rather than a cut.

---

## The shipped animation

| Property | Value |
| --- | --- |
| Draw duration | 750ms |
| Easing | `Curves.easeInOutQuart` |
| Rim | starts at its leftmost point `(36, 9.9)`, sweeping up over the top |
| Body | starts at the same point, descending the left side |
| Footring | left to right, gated on the body's 41%→59% crossing window |
| Exit hold | 250ms |
| Exit lift | 400ms, fade to 0 while scaling to 1.16 |

---

## What generalizes

- **Render before asking.** Round 1 was presented as "these aren't good enough" rather
  than as a choice, because seeing them made the flaw obvious. A verbal description of a
  vase silhouette is nearly worthless; the render takes seconds and settles it.
- **Name the geometry.** "From the side" sounds meaningful and is a no-op on a
  rotationally symmetric object. Saying so directly saved a wasted round.
- **Watch for fixes that remove the feature.** Round 8 smoothed away the footring that
  made round 7 correct. Ask what a rough edge is *doing* before sanding it.
- **Comparisons beat sequences.** The round 7-vs-8 page and the 2× foot crop each
  revealed something that full-size, one-at-a-time review had not.
- **Constraints hide in the smallest gap.** Nobody predicts that a decorative footring
  line sets the maximum stroke weight for the entire mark at both sizes.
- **A reference image is worth many rounds.** Six rounds of approximation, then one
  photo made the target unambiguous.
- **Approving a design does not mean it shipped.** The port to code silently changed
  the proportions, and neither the golden test nor the code review caught it. Measure
  the built artifact against the approved one — for a shape, that means comparing
  actual rendered dimensions, not reading the code that produces them.

---

## Reproducing the renders

The HTML files are self-contained — open directly in a browser. To regenerate a PNG:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=2 --virtual-time-budget=3000 \
  --screenshot=out.png --window-size=1150,620 \
  "file:///absolute/path/to/round-XX.html"
```

ImageMagick is not a substitute here: without the `rsvg-convert` delegate installed it
falls back to an internal SVG renderer that silently drops grouped stroke attributes and
multi-line path data — it produced a page containing labels and background but no vases
at all.
