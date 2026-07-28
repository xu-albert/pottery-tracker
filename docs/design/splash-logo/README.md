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
