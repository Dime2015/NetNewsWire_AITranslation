# Babel 2.0 Motion Contract

Status: normative design/engineering contract, v1.1 baseline (`reference` baseline
identifier), dated 2026-08-31 (`measured` document date)

This document defines the motion ownership, gesture arbitration, continuous progress
math, performance budgets, instrumentation, and device acceptance gates for Babel 2.0.
It is a contract for an independent product surface, not a patch list for the legacy
reader. Reeder Classic is used only as an interaction and feel reference. Babel 2.0
must keep its own information architecture, visual language, data model, and
implementation boundaries.

## 1. Evidence and number provenance

Every numeric value in this contract carries one of these provenance labels:

- `measured`: directly measured from a local asset, source code, or recorded metadata.
- `reference`: a static/visual checkpoint in the local Reeder reference ledger or Figma
  interaction contract. It is not proof of a runtime curve or timing.
- `target`: an explicit Babel 2.0 acceptance target to be validated on device.
- `to-tune`: an initial engineering range or hypothesis. It is not an acceptance fact.

The local evidence set is:

- [Reeder reference ledger](../reeder-classic/REFERENCE_LEDGER.md) — static geometry,
  palette, and capture limitations.
- [Reeder capture plan](../reeder-classic/REFERENCE-CAPTURE-PLAN.md) — provenance and
  the boundary between frame evidence and human feel acceptance.
- [Figma interaction contract](../../Figma%20Drafts/INTERACTION-CONTRACT.md) — Babel
  behavior/state contract and visual checkpoints.
- [Local reference recording](../../Resources/Reeder%20video.MP4) — `measured` media
  metadata only; its motion curve has not been fully frame-traced in this contract.

Known `measured` recording metadata: canvas `1206 × 2622 px`, `60 fps`, duration
`237.823333 s`. The ledger maps this to an iPhone 17 reference canvas with approximately
`3 px/pt`; that conversion is `reference`, not a device-independent layout rule.

The following are **not** currently backed by a complete frame-by-frame trace of Reeder:
exact easing curves, exact settle duration, exact velocity cutoff, exact edge activation
width, and exact spring damping. Any value for those items below is explicitly
`target` or `to-tune`. Static frames can prove checkpoints; they cannot prove
continuous feel. Only an instrumented physical-device run can close that gap.

Reference-only checkpoints used to align implementation and review:

- Feed hero: `169 pt` expanded from screen `y = 59 pt` to `228 pt`, `99 pt` compact;
  toolbar frame `[0, 802, 402, 72]` (`reference`, Figma contract).
- Reader controls-visible layout: `14 pt` empty-padding overlap; compact identity starts
  around `y = 103 pt` and article content around `y = 189 pt` in a `402 × 874 pt`
  reference frame (`reference`, Figma contract).
- Reader static capture: bright top-control band around `y = 140–196 px` in the local
  reference and around `y = 141–202 px` in the current Babel comparison (`reference`);
  these are screenshot coordinates, not scroll thresholds.

## 2. Motion invariants

1. One motion owner controls each route transition. A child `WKWebView`, table, or
   article renderer may report scroll intent, but cannot start a navigation transition.
2. Tracking is continuous. Finger movement maps directly to a normalized progress value;
   UIKit animations are used only to settle after release or cancellation.
3. Every transition is interruptible from its current rendered state. A second gesture
   never restarts from a stale model value or a hidden initial frame.
4. The current route, article identity, reading anchor, filter, and normalized progress
   survive chrome visibility changes and asynchronous content updates.
5. During a gesture, do not mutate scroll insets, content offsets, Auto Layout
   constraints, DOM structure, or navigation stack membership as a side effect of
   progress. Animate a prepared view hierarchy instead.
6. An async load may prepare content or replace text in place; it never owns a visual
   transition and never blocks the first finger-following frame.
7. All progress values are clamped. All completion and cancellation callbacks are
   idempotent. A cancelled transition leaves exactly one settled route and no orphaned
   gesture recognizer state.
8. Reduced Motion changes presentation (crossfade/no parallax where required), not
   route semantics, gesture ownership, or state persistence.

## 2A. Audited legacy failure modes

The following are `measured from current source` observations. They explain why the
existing motion must not be treated as the Babel 2.0 baseline:

| Current behavior | Code-level cause | Contract consequence |
|---|---|---|
| First scroll movement feels delayed or sticky | `BabelShellViewController` installs a full-screen nav pan and recursively makes descendant scroll views wait for it (`BabelShellViewController.swift`, source lines `13–37` and `145–151`) | Edge-only ownership; no global `require(toFail:)` relationship |
| Pop cannot be naturally reversed or interrupted | Custom animator uses `UIView.animate` and has no `interruptibleAnimator` (`BabelShellViewController.swift`, source lines `395–449`) | Direct progress driver plus sampled presentation-state interruption |
| Reader title/toolbar snaps | Reader toggles constraints, alpha, and transforms as binary states; scroll threshold is computed asynchronously after WebView load (`BabelReaderViewController.swift`, source lines `257–387` and `822–876`) | One continuous progress value; stable WebView geometry |
| Reader → Browser has no finger-following transition | Open-original pan acts only on `.ended`; Browser is then pushed with default navigation animation (`BabelReaderViewController.swift`, source lines `893–928`) | Prepare Browser first; right-edge tracking owns both routes |
| Next article breaks continuity and grows the stack | `showNextArticle` pushes another Reader controller (`BabelReaderViewController.swift`, source lines `1010–1019`) | Three-surface in-place pager; no push per article |
| Feed hero hitches during scroll | Hero mutates a height constraint, calls layout synchronously, and creates fonts/recomputes frames in `layoutSubviews` (`BabelTimelineViewController.swift`, source lines `901–919` and `992–1182`) | Layer transforms/opacity only in the tracking path |
| Web content carries legacy state | Shared pool plus class-removal workaround for legacy scripts (`BabelReaderViewController.swift`, source lines `11–16` and `257–274`; `SceneDelegate.swift`, source lines `240–249`) | Dedicated Babel 2.0 factory, script namespace, and route token |

Line ranges above are navigation aids, not an instruction to preserve the old code.
The old implementation’s `64 pt` pop activation width and `0.32` progress finish rule
are also `measured from current source`; neither is an approved Babel 2.0 value.

## 3. Unified ownership model

The Babel 2.0 navigation container is the only owner of push, pop, present, dismiss,
and active-interaction state. Reader and Browser are child routes, not parallel
navigation systems.

| Surface | Owner | Prepared siblings | Scroll/gesture input | Rendered output |
|---|---|---|---|---|
| Navigation pop | `Babel2NavigationController` + motion driver | previous/current route | left-edge pan | current/previous transforms, shadow, chrome |
| Reader → Browser | Reader route coordinator | Browser route + WebView/chrome | Reader right-edge horizontal pan | Reader/Browser cross-route transform |
| Article pager | `Babel2ReaderPagerViewController` | previous/current/next article | vertical pan after scroll boundary | three article surfaces and progress |
| Reader chrome | `Babel2ReaderChromeMotion` | expanded and compact chrome | Reader vertical scroll intent | title/icon/ring/top and bottom bars |
| Feed hero | `Babel2FeedHeroMotion` | expanded/compact layers in one route | Feed table scroll | height-independent layer transforms/opacity |
| Web content | dedicated Babel 2.0 WebView factory/pool | current and adjacent prepared content | vertical scroll, link taps | stable WebView geometry and content |

No motion owner may push a new Reader controller to represent the next article. The
pager keeps previous/current/next prepared and swaps identity at a settled boundary.

## 4. Gesture arena and priority

The priority order is strict and directional:

1. System-compatible edge navigation pop.
2. Reader article pager, only when the WebView/table is at the relevant vertical edge
   and the horizontal/vertical intent is unambiguous.
3. Reader → Browser right-edge action gesture.
4. Ordinary WebView, table, and collection scrolling.
5. Child controls, taps, menus, and text selection within their hit regions.

The exact recognizer implementation is an implementation decision; the arbitration
contract is not. Use edge recognizers for navigation ownership. Do not install a
full-screen navigation pan and require every descendant `UIScrollView` to fail it.
That pattern delays ordinary scrolling and produces the observed “sticky” first
movement. Do not allow Reader → Browser to begin from any horizontal point; reserve it
for the configured right-edge region. Browser back uses the same left-edge pop owner.

| Gesture | Start region / gate | Can recognize simultaneously with | Must yield to |
|---|---|---|---|
| Pop | left edge; `target` edge width `24–32 pt` (`to-tune`) | none while active | system modal dismissal if present |
| Reader → Browser | right edge; `target` edge width `24–32 pt` (`to-tune`), link action eligible | vertical scroll before intent lock | pop, text selection, native control tap |
| Vertical article pager | full content surface only at scroll boundary; vertical intent lock | chrome observation only | edge pop and right-edge action |
| WebView/table scroll | ordinary content surface | chrome observer | active edge transition |
| Tap/menu | control hit target `44 pt` (`reference` from Figma contract) | none while activating | active transition |

At gesture start, record the owning route, initial translation, initial content offset,
and a monotonic interaction token. Once intent locks, direction cannot change owner
mid-flight. Tiny reversals remain in the same owner and update progress continuously.

## 5. Motion driver lifecycle and API contract

The conceptual public surface is:

```text
MotionDriver<State, Intent>
  begin(intent, origin) -> token
  update(token, translation, velocity, timestamp)
  end(token, velocity) -> settlingToEnd | settlingToStart
  cancel(token, reason) -> settlingToStart
  interrupt(token, newIntent) -> token
  settleCompletion(token, outcome)
```

The names are a contract, not a mandate to copy a specific implementation. The driver
must expose these observable states:

`idle → tracking → settlingToEnd/settlingToStart → settled` or `cancelled`.

During `tracking`, render directly from the latest input. During settling, use one
interruptible property animator or equivalent time-based driver whose start value is
read from the actual presentation state. A new `begin` samples that presentation state
before taking ownership. `finish` and `cancel` are mutually exclusive and safe to call
more than once. A token from an older route cannot mutate a newer route.

Recommended target settling ranges are `0.20–0.34 s` (`to-tune`) for a full route
transition and `0.18 s` (`reference`, Figma reader chrome behavior) for top/bottom
control reveal/hide. These are not traced Reeder timings. Duration must be tuned by
device observation after the direct-tracking path is stable.

## 6. Navigation pop

### State machine

`idle → edgeArmed → tracking → settlingToEnd (pop) | settlingToStart (cancel) → settled`.

Rules:

- Prepare the previous route and its stable chrome before the first changed event.
- Do not wait for network, WebView navigation, layout, or snapshot generation after
  tracking begins.
- Pop commits only once at the settled end. Cancellation restores the current route
  without reconstructing it.
- A pop can be cancelled at any progress, including after a velocity projection.

### Progress and visual mapping

Let `W` be current route width (`measured` at runtime), `x` be rightward edge-pan
translation, and `p = clamp(x / W, 0, 1)` (`target` formula):

```text
currentX      = W * p
previousX     = -0.22 * W * (1 - p)       // 0.22 is `to-tune`
shadowOpacity = 0.18 * (1 - p)            // 0.18 is `to-tune`
```

The underlying route is revealed continuously; there is no discrete snapshot swap.
For release decision, compute a projected progress from current `p` and velocity in a
bounded projection window, e.g. `0.12–0.18 s` (`to-tune`), then finish if projected
progress exceeds `0.50` (`target/to-tune`). Otherwise cancel. The final threshold and
velocity cutoff must be measured against false-commit/false-cancel cases on device.

## 7. Reader → Browser

### State machine

`idle → rightEdgeArmed → tracking → settlingToEnd (Browser) |
settlingToStart (Reader) → settled`.

The Browser controller, web view configuration, initial chrome, and loading placeholder
must exist before `tracking`. A cold network load is never part of the finger-following
animation. If preparation fails, the gesture does not begin and Reader remains intact.

### Progress and cancellation

Let `W` be the route width and `x` be leftward translation magnitude from the right edge:

```text
p = clamp(-x / W, 0, 1)
readerX  = -W * p
browserX = W * (1 - p)
```

This mapping, including the `0–1` (`target` normalized bounds), is the Babel 2.0
`target` formula; it is not a frame-traced Reeder measurement.

Use the same bounded projection and `0.50` (`target/to-tune`) finish rule as pop. A
finger reversal must visibly reverse both routes. On cancellation, Browser is discarded
or returned to its prepared idle state; Reader’s article, anchor, and toolbar state are
unchanged. On commit, Browser becomes the sole current route; its left-edge back action
is owned by the unified pop transition.

## 8. Vertical article pager

Reader articles are one vertical paging surface. The current route holds three prepared
article surfaces: previous, current, next. Do not push a fresh Reader controller for
“next article”; stack growth and default push timing break continuity.

### State machine

`resting → boundaryArmed → tracking → settlingToNext/settlingToPrevious |
settlingToRest → resting`.

The pager may arm only when the current article’s scroll view is at the relevant edge,
the article has a neighbor, and vertical intent is locked. Normal article scrolling
continues until that boundary. A short article with no usable scroll distance remains a
normal Reader state; it must not enter compact-title or pager behavior merely because of
elapsed time.

### Progress and mapping

Let `H` be the viewport height (`measured` at runtime) and `y` be upward translation
magnitude for the next article:

```text
visualP = clamp(-translationY / H, 0, 1)
currentY = -H * visualP
nextY    = H * (1 - visualP)
```

The `0–1` range is a `target` normalized bound and the mapping is a `target` formula.
It is not an inferred Reeder timing or distance measurement.

The previous article uses the inverse mapping. Keep article identity and scroll anchors
stable during tracking. Velocity influences only the terminal decision, not the direct
mapping. If the projected progress is below `0.50` (`target/to-tune`), settle back;
otherwise settle to the neighbor. After commit, rebase the three-surface window in one
state update and preserve normalized reading progress as defined below.

## 9. Reader title collapse and continuous reading progress

Figma defines one long-article route with checkpoints, not separate pages. Figma’s
short-article branch explicitly forbids a sticky compact title when the article cannot
scroll.

### Eligibility and state machine

`expanded → collapsing → compactPinned → controlsChanging → compactPinned`.

Eligibility is `maxScrollableOffset > collapseStart` (`measured` at runtime). A short
article stays `expanded`. The compact identity may include title, feed icon, and progress
ring only after the article has a genuine usable scroll range.

### Collapse progress

Let `offsetY` be the actual WebView scroll offset, and `collapseStart` and
`collapseDistance` be route-specific calibrated values:

```text
pCollapse = clamp((offsetY - collapseStart) / collapseDistance, 0, 1)
```

The formula is `target`; `collapseStart` and `collapseDistance` are `to-tune` per
device/font/content class. The existing Babel implementation’s `70 pt` collapse
distance is `measured from current source`, not an approved motion constant. Do not
mutate scroll insets or WebView geometry on every update. Render the large title,
compact title, icon, ring, and article surface from this one `pCollapse`.

At `pCollapse = 1` (`target` settled endpoint), pin the compact identity. Title/icon/ring
interpolation is linear (`reference` from Figma); any additional scale/opacity curve
must be marked `to-tune`.
The progress ring is a full neutral track plus one uninterrupted clockwise accent arc,
starting at 12 o’clock (`reference`). Do not quantize to Figma’s 0/25/60/100% samples
(`reference` QA checkpoints).

Continuous normalized reading progress is:

```text
pReading = clamp(
  (offsetY - collapseStart) / (maxScrollableOffset - collapseStart),
  0,
  1
)
```

The denominator and offset are `measured` at runtime; the normalized formula is
`reference` from Figma. Render `pReading` directly into the ring. Preserve it across
translation, theme changes, chrome changes, and pager rebasing.

## 10. Reader toolbar hide/show

The pinned compact identity is independent from top/bottom control visibility. Hiding
bars must never move or animate the pinned identity.

### State machine

`shown → directionAccumulating → hidden` on downward travel, and
`hidden → directionAccumulating → shown` on upward travel. At the top boundary,
`shown` is forced. At the bottom boundary, do not let elastic overscroll flip state.

After pinning, require accumulated travel of `12 pt` (`reference`, Figma contract) in
one direction before changing visibility. Tiny reversals and rubber-band movement are
ignored until the accumulator crosses zero. The existing source’s `12 pt` direction
threshold is `measured from current source` and happens to match the Figma reference;
the contract still requires device confirmation.

Continuous bar progress uses:

```text
barP = clamp(barP - deltaY / hideDistance, 0, 1)
```

This is the `target` formula with `0–1` (`target` normalized bounds). `hideDistance` is
`to-tune`.

`barP = 0` means shown and `barP = 1` means hidden. `hideDistance` is `to-tune`.
Top and bottom control groups map from the same `barP`; settle with a short linear
opacity/translation animation of `180 ms` (`reference` from Figma, target for Babel).
Chrome visibility changes are never binary-only in the tracking path.

## 11. Feed hero

The hero is conditional presentation attached to one Feed route. Expanded, 50%, and
compact are checkpoints of one continuous surface (`reference` checkpoint at 50%);
they are not controller destinations.

### State machine

`paperOnly/expanded → collapsing → compactPinned → expanding → expanded`.

The existing image resolution/cache/fallback chain is a data concern and stays outside
the motion driver. The motion driver receives a resolved image layer or a no-image
fallback layer and never launches image decoding during a gesture.

### Progress and mapping

Let `offsetY` be table content offset and `restOffset` the route’s top resting offset:

```text
pHero = clamp((offsetY - restOffset) / collapseDistance, 0, 1)
heroHeight = expandedHeight - collapseDistance * pHero
```

`pHero` and the linear interpolation rule are `reference` from the Figma contract.
The current source’s `expandedHeight = 169 pt`, `compactHeight = 99 pt`, and
`collapseDistance = 70 pt` are `measured from current source`; they are useful baseline
values, not automatically accepted Babel 2.0 constants. Confirm safe-area behavior on
device before assigning `target` status.

Map the same `pHero` to image crop/opacity, source mark position/scale, title position/
size, readability feather, and list origin. Do not call `layoutIfNeeded`, mutate table
insets, or independently reflow date/article rows for every scroll tick. The date header
and article rows translate as one list surface. At `pHero = 1`, the image is absent and
the compact paper header is pinned. Reversing uses the same mapping without resetting
filter, route, or scroll context.

## 12. WebView and content isolation

Use a dedicated Babel 2.0 WebView factory and pool. The old prewarming concept may be
borrowed, but the old configuration, legacy scripts, and shared mutable state are not a
motion foundation. The current reader removes a legacy reading-bar class from a pooled
WebView; that is contamination containment, not isolation.

Each prepared WebView must have stable configuration, script namespace, scroll delegate,
and route token. Article HTML replacement, translation streaming, image decode, and
progress measurement are scheduled around the motion driver. They cannot synchronously
rebuild the view hierarchy or trigger an unbounded DOM/layout pass in a tracking frame.

## 13. Performance budgets and red lines

Frame budgets are derived from display refresh, not from the Reeder recording:

- `60 Hz → 16.67 ms/frame` (`measured/calculated device display budget`).
- `120 Hz → 8.33 ms/frame` (`measured/calculated device display budget`).

`target`: no visible hitch in the acceptance matrix; investigate any missed frame,
long-frame cluster, or touch-to-render discontinuity. A 120 Hz device is the stricter
gate; a motion path that passes only at 60 Hz is not complete.

Forbidden in the direct tracking path:

- database, network, translation, or image decode work;
- WebView JavaScript evaluation, DOM replacement, or forced layout;
- `reloadData`, snapshot generation, or synchronous rasterization;
- constraint mutation followed by `layoutIfNeeded` on every scroll/pan tick;
- creating fonts, paths, gradients, or image filters per frame;
- adding/removing view hierarchies or navigation controllers;
- an unbounded `UIView.animate` started from every changed event.

Allowed per frame: bounded transform, alpha, crop/contents rect, shadow opacity,
`CAShapeLayer.strokeEnd`, and cached geometry updates. Any new exception requires a
profiling trace and a documented reason.

## 14. Signposts and measurement protocol

Instrument the motion layer with `os_signpost` intervals/events (names are normative):

| Signpost | Interval/event boundary | Required fields |
|---|---|---|
| `Babel2.Motion.Begin` | first ownership | route, intent, token |
| `Babel2.Motion.Track` | begin/end of active tracking | token, progress, recognizer |
| `Babel2.Motion.Settle` | terminal decision to completion | outcome, duration, projectedProgress |
| `Babel2.Motion.Interrupt` | old owner interrupted | old/new token, sampledProgress |
| `Babel2.Reader.Chrome` | collapse or bar visibility update | state, pCollapse, barP |
| `Babel2.Reader.Pager` | pager arm/commit/cancel | article IDs, p |
| `Babel2.Feed.Hero` | hero tracking | pHero, imageReady |
| `Babel2.Web.Prepared` | Browser/adjacent article ready | route token, warm/cold |

Measure on physical devices with Instruments Animation Hitches/Core Animation and Time
Profiler, correlated to the signposts. Repeat on 60 Hz and 120 Hz hardware, cold and
warm WebView states, long and short articles, image/no-image feeds, light/dark theme,
and with translation updates queued. Capture touch-down time, first visual movement,
peak frame time, missed-frame count, settle duration, cancellation success, and final
route/anchor. Simulator results are structural diagnostics only, not feel acceptance.

## 15. Automated and device acceptance matrix

Automated tests should cover pure progress math, clamping, terminal projection, token
ownership, state transitions, and idempotent finish/cancel. UI tests should verify route
identity and anchor persistence; they cannot certify feel alone.

| Area | Scenario | Pass condition | Evidence |
|---|---|---|---|
| Pop | slow edge drag, release below threshold | current route remains; no stack corruption | automated + device |
| Pop | fast edge drag, reverse mid-flight | visual reversal follows finger; one final outcome | device + signpost |
| Pop | non-edge table/WebView horizontal movement | no pop recognizer activation | UI test + device |
| Browser | right-edge start, cancel at 10/50/90% (`target` checkpoints) | Reader remains identical; Browser not adopted | device |
| Browser | right-edge finish, Browser cold/warm | first movement is local; no network hitch | signpost + device |
| Browser | Browser left-edge back | same pop contract and anchor behavior | device |
| Pager | at top/bottom, slow drag and velocity release | neighbor commit/cancel follows projection; three-surface window rebases once | automated + device |
| Pager | rapid next/previous reversal | no duplicate article, stale token, or stack growth | stress device |
| Collapse | long article slow down/up through range | title/icon/ring track continuously and reverse without snap | device |
| Collapse | short article | no compact identity or artificial collapse | UI test + device |
| Toolbar | downward/upward micro-reversals under `12 pt` | no flicker | device + signpost |
| Toolbar | top/bottom elastic overscroll | bars do not change spuriously; top forces shown | device |
| Hero | expanded → 50% → compact → reverse | one route/list surface; no row reflow or image snap | device |
| Hero | image ready late / no image fallback | motion unaffected; fallback remains valid | stress device |
| Async | translation/theme/filter update during tracking | no ownership change, layout jump, or anchor loss | stress device |
| Refresh | 60 Hz and 120 Hz | no visible hitch; budgets respected | Instruments + device |
| Stress | 30 repeated transitions (`target` stress count) and rapid interruptions | no retained controllers, broken tokens, or stuck recognizers | device + memory trace |

Acceptance is two-stage: automated/static checks establish invariants and math; a
physical iPhone run establishes continuity, touch-following, perceived latency, and
visual stability. A screenshot or static overlay cannot close the second stage.

## 16. Legacy boundaries and first implementation slice

The first implementation slice should introduce an isolated motion/navigation layer and
route-level adapters, then migrate one interaction at a time. It should not become a
second formal app target. Data/domain objects may be reused where behavior is not owned
by the legacy UI.

Do not use these as the Babel 2.0 motion base: `BabelShellViewController`’s full-screen
pan policy and non-interruptible animator; `BabelReaderViewController`’s push-per-article
pager, binary chrome animations, and shared legacy WebView pool; the old
`ArticleViewController`, `NNWArticlePaging`, `WebViewController`, `ArticleHeaderBar`,
`WebViewController+ReadingBar`, `ImageTransition`, `PoppableGestureRecognizerDelegate`,
`NNWControlBoard`, `NNWReadingModeBar`, `NNWFloatingModeBar`, old MainTimeline/MainFeed
controllers, or old `WebViewProvider`/`PreloadedWebView` configuration. Their source is
audit evidence only. Reuse of data, parsing, cache, and image suitability logic must be
wrapped by Babel 2.0 ownership boundaries.

The migration is complete only when the old owner is removed from the relevant route,
the new owner has signposts and pure math tests, and the corresponding device row in the
acceptance matrix passes. Reeder Classic remains a reference throughout; it is never a
permission to copy its assets, identity, or product behavior wholesale.
