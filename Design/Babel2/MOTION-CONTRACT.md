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

### Immutable baselines and live-status boundary

The historical product baselines and contract-related commits below are immutable
references. They are not claims about the live branch, HEAD, or working tree:

| Reference | Meaning | Evidence boundary |
|---|---|---|
| `v0.5` → `649f85fd50e5fff21e75818193011250baf08d50` | Genesis v1 stable baseline | local annotated tag peeled SHA |
| `v1.0` → `d1679c7f253d37eda557970fca0827c096132a05` | Genesis v2 stable baseline | local annotated tag peeled SHA |
| `v1.1` → `a94c00626edf13bb3e869c35924bfd6ece7e6165` | pre-Babel 2.0 UIKit redesign baseline | local annotated tag peeled SHA |
| `9fda5c5650d06ff5155ead466adbe1b084ccdd44` | Babel 2.0 static AppIcon asset commit | immutable commit contents only |
| `ce7c0ea38da3cb8bcab9a01dd6bd712b215ae6d9` | prior Babel 2.0 product and motion contract version | immutable contents only; this amendment must be recorded by a new immutable contract commit |

At review time, the live branch, HEAD, working tree, uncommitted changes, and
implementation status must be read from Git together with
`Design/Babel2/Project/STATUS.md`. This contract is not a live-status source; a dated
evidence snapshot cannot be promoted to a live branch or working-tree claim.

At the date of this contract version, the following are **not** backed by a complete
frame-by-frame trace of Reeder:
exact easing curves, exact settle duration, exact velocity cutoff, exact edge activation
width, and exact spring damping. Any value for those items below is explicitly
`target` or `to-tune`. Static frames can prove checkpoints; they cannot prove
continuous feel. Only an instrumented physical-device run can close that gap.

Reference-only checkpoints used to align implementation and review. The latest user
decisions below supersede any older Draft checkpoint whose boundary differs:

- Feed hero: compact/list toolbar frame `[0, 802, 402, 72]` and the `99 pt` compact
  geometry remain `reference`; the expanded hero is now full-bleed through the physical
  top/status-bar/dynamic-island region, with its own fully opaque image/background and
  contrast scrim. The older “expanded begins below the 59 pt status region” clause is
  superseded for the expanded state.
- Reader controls-visible layout: `14 pt` empty-padding overlap; compact identity starts
  around `y = 103 pt` and article content around `y = 189 pt` in a `402 × 874 pt`
  reference frame (`reference`, Figma contract).
- Reader static capture: bright top-control band around `y = 140–196 px` in the local
  reference and around `y = 141–202 px` in the Babel comparison captured in the dated
  evidence snapshot (`reference`); these are screenshot coordinates, not scroll thresholds.

Latest product constraints carried by this motion contract:

- Babel 2.0 cold start lands directly in Feeds/Library root; the old account-card
  landing page is not a route.
- Reader enters with title/byline visible above the article body. One continuous motion
  surface moves them into the compact header on scroll; feed icon/progress fade in along
  the same progress, rather than appearing after an asynchronous snap.
- The Reader top long-image slot is ordinary system Share. Long image is a bottom-toolbar
  tap-only action; long-press is not a share path.
- Sync arrow is visible/rotating only during real syncing and hides on completion. It is
  not a generic article/translation loading indicator. Article/translation loading uses
  skeleton/passive state and must not show a system spinner alongside the sync arrow.
- All expanded/list/status-bar surfaces are fully opaque at their respective states.
  Horizontal article media is full-bleed 100vw and square-cornered; text/caption retain
  reading inset. Ordinary controls and links use neutral gray/black; user accent is
  reserved for Settings switches and the Reader progress ring.
- Library filter motion stays on one route: Starred/Unread/All taps drive one shared
  `pFilter` (or equivalent) across the selection pill, source/article list
  translate/crossfade, summary, and per-source counts. Counts are computed with the
  destination filter semantics. Rapid taps interrupt and reverse from the rendered
  presentation state; they do not reload the whole page or flash.
- Timeline geometry has no independent spacer or transparent band between hero/source
  title/compact chrome and the first date header. Only the standard section-inset token
  may occupy that boundary (`to-tune`, pending Figma overlay measurement). The paper
  list surface remains continuous and opaque across expanded, intermediate `pHero`, and
  compact states; date header and article rows share one scroll surface.
- Naming follows Route A in the product contract: new Babel2 motion code, resources,
  tests, leaf filenames, types, methods, accessibility identifiers, log categories, and
  routes use Babel/Babel2 names. Existing parent target/directory names do not fail the
  gate merely by inheritance. Required old build/module references are build/test
  harness allowlist entries only; persisted/system identity is centralized behind the
  single `LegacyIdentityCompatibility` boundary, and an allowlist can never be a second
  persisted/system identity outlet. The phase covered by this contract executes no-new-name, user-visible
  Babel naming, and compatibility isolation only. Technical source/target/project/scheme/
  CI renaming waits for Babel 2.0 device stability; bundle/data identity and external
  repository identity require a separate migration project and explicit authorization.

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
9. Loading has one visible owner per surface. Sync owns the rotating sync arrow only
   while a real sync operation is active; article/translation preparation owns a passive
   skeleton or an explicit error/retry state, never a second spinner layered over sync.

## 2A. Audited legacy failure modes（audit-only historical reference）

The following are `measured from the audited source snapshot` observations. They explain
why the existing motion must not be treated as the Babel 2.0 baseline:

All old type names, file names, and paths in this subsection are explicitly
`audit-only historical reference`; they do not participate in Gate A and cannot be copied
into new Babel2 motion code, resources, tests, accessibility identifiers, log categories,
or routes.

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
are also `measured from the audited source snapshot`; neither is an approved Babel 2.0
value.

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

## 4A. Library filter transition

Starred, Unread, and All are presentations of one Library route, not three navigation
destinations. A tap in the fixed filter slot changes the route's filter state in place.
The transition owner must expose one normalized `pFilter` (or an equivalent shared
progress value):

```text
pFilter = clamp(elapsed / filterDuration, 0, 1)
```

The `180 ms` `filterDuration` is a linear Figma reference and a Babel `to-tune` target;
it must be calibrated against physical-device touch response. The same progress drives
the selection pill, source/article list translation and crossfade, summary, and
per-source counts. The target count is calculated from the destination filter's
semantics, so Starred hides sources/folders with no starred articles and shows only
the corresponding starred counts.

The transition must start from the currently rendered presentation state. A rapid tap
interrupts the active transition, samples its presentation progress, and reverses or
continues toward the newly selected filter without reconstructing the whole page,
reloading the data surface, or flashing a blank/skeleton state. Filter identity,
selection context, and route ownership remain stable throughout. Completion and
cancellation are idempotent, and stale filter tokens cannot publish counts or rows.

Unit tests must cover clamping, shared-progress mapping, destination-semantic counts,
rapid tap interruption/reversal, and stale-token rejection. Simulator checks are
structural diagnostics; physical-device checks must cover single taps, rapid alternating
taps, slow/reversed transitions, and no-flicker list/count presentation.

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
article stays `expanded` for chrome collapse purposes. On every Reader entry, title,
date, and byline are already visible above the article body; they must not be withheld
while WebView content or translation prepares. The compact identity may include title,
feed icon, and progress ring after the article has a genuine usable scroll range.

### Collapse progress

Let `offsetY` be the actual WebView scroll offset, and `collapseStart` and
`collapseDistance` be route-specific calibrated values:

```text
pCollapse = clamp((offsetY - collapseStart) / collapseDistance, 0, 1)
```

The formula is `target`; `collapseStart` and `collapseDistance` are `to-tune` per
device/font/content class. The existing Babel implementation’s `70 pt` collapse
distance is `measured from the audited source snapshot`, not an approved motion constant. Do not
mutate scroll insets or WebView geometry on every update. Render the large title,
compact title, icon, ring, and article surface from this one `pCollapse`.

At `pCollapse = 1` (`target` settled endpoint), pin the compact identity. Title/byline
move from their initial above-body position into that identity through the same
continuous surface. The feed icon and progress ring fade in continuously during this
motion; they must not pop in as a late asynchronous state. Title/icon/ring interpolation
is linear (`reference` from Figma); any additional scale/opacity curve must be marked
`to-tune`.
The progress ring is a full neutral track plus one uninterrupted clockwise accent arc,
starting at 12 o’clock (`reference`). The accent value comes only from the user-selected
theme accent and is allowed to color the Reader ring; no other Reader/control color may
inherit it. Do not quantize to Figma’s 0/25/60/100% samples (`reference` QA checkpoints).

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
translation, theme changes, chrome changes, and pager rebasing. A theme change updates
the ring accent in place and does not recolor ordinary controls, links, stars, selection,
or reading-mode state.

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
threshold is `measured from the audited source snapshot` and happens to match the Figma reference;
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
they are not controller destinations. In expanded state the hero image/background
extends through the physical top, status-bar, and dynamic-island region. Its own image/
background and contrast scrim are fully opaque. Compact/list state uses fully opaque
solid chrome, and no date, article list, WebView, or other scroll surface may show
through the status bar.

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
The audited source snapshot’s `expandedHeight = 169 pt`, `compactHeight = 99 pt`, and
`collapseDistance = 70 pt` are `measured from the audited source snapshot`; they are
useful baseline values, not automatically accepted Babel 2.0 constants. Confirm safe-area
behavior on device before assigning `target` status.

Map the same `pHero` to image crop/opacity, source mark position/scale, title position/
size, readability feather, status-bar scrim, and list origin. Do not call `layoutIfNeeded`,
mutate table insets, or independently reflow date/article rows for every scroll tick.
The date header and article rows translate as one list surface. At `pHero = 1`, the image
is absent and the compact paper header is pinned as fully opaque chrome. Reversing uses
the same mapping without resetting filter, route, or scroll context.

### Timeline geometry acceptance (normative)

For every hero presentation checkpoint—expanded, any intermediate `pHero`, and compact—
there must be no independent spacer, transparent band, background leak, or view seam
between the hero/source title/compact chrome and the first date header. The only permitted
inset at that boundary is the standard section-inset token; its value is `to-tune` and
must be confirmed by a Figma overlay measurement, not invented as a state-specific gap.
The paper list surface is one continuous, fully opaque surface. The date header and
article rows share the same scroll surface and may not be independently reflowed to
manufacture the transition.

An automated geometry/snapshot check must cover expanded, intermediate, and compact
states, asserting the absence of the spacer/seam and the continuity/opacity of the paper
surface. Simulator inspection is a structural gate only. A target-iPhone screenshot and
scroll run must confirm the same geometry during forward and reversed hero motion.

## 12. WebView and content isolation

Use a dedicated Babel 2.0 WebView factory and pool. The old prewarming concept may be
borrowed, but the old configuration, legacy scripts, and shared mutable state are not a
motion foundation. The audited reader implementation removes a legacy reading-bar class from a pooled
WebView; that is contamination containment, not isolation.

Each prepared WebView must have stable configuration, script namespace, scroll delegate,
and route token. Article HTML replacement, translation streaming, image decode, and
progress measurement are scheduled around the motion driver. They cannot synchronously
rebuild the view hierarchy or trigger an unbounded DOM/layout pass in a tracking frame.

Reader entry must use a warm-or-progressive preparation path: the selected article’s
title, date, byline, body shell, and first readable content are available from the local
snapshot before navigation settles whenever the data exists. Prepare the current Reader
surface and, where budget permits, the adjacent article/browser surface off the tracking
path. Network fetch, translation, image decode, and WebView navigation may continue in
place, but none may block the first frame or temporarily replace visible title/byline
with a full-screen loading page. A cold/failed preparation uses a stable skeleton and
then an explicit error+retry state.

Article media rendering is part of the prepared content contract: a landscape image
must be laid out at 100vw/full-bleed to both screen edges with square corners, while
body text and captions retain reading inset. Portrait/inline media is not forced to
full-bleed. No `figure`, link, or wrapper style may reintroduce a corner radius.

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
- a system activity spinner layered with the sync arrow, or a persistent sync arrow
  shown after the real sync operation has completed;
- an article/translation loading screen that hides already available title/byline/body
  content while waiting for network or translation work.

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
| `Babel2.Library.Filter` | filter transition ownership and settlement | fromFilter, toFilter, pFilter, token |
| `Babel2.Web.Prepared` | Browser/adjacent article ready | route token, warm/cold |
| `Babel2.Loading.Owner` | visible loading owner changes | surface, owner, state |

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
| Filter | Starred/Unread/All single tap | one route; pill, list, summary, and per-source counts share `pFilter`; destination-semantic counts | unit + simulator + device |
| Filter | rapid alternating taps / mid-flight reversal | starts from presentation state; no page reload, blank flash, stale counts, or filter token leak; `180 ms` linear reference/to-tune | unit + stress device + signpost |
| Collapse | long article slow down/up through range | title/icon/ring track continuously and reverse without snap | device |
| Reader entry | cold and warm article open | title/date/byline are visible above body on first settled frame; no full-screen loader or progress bar masks available content | device + signpost |
| Collapse | short article | no compact identity or artificial collapse | UI test + device |
| Toolbar | downward/upward micro-reversals under `12 pt` | no flicker | device + signpost |
| Toolbar | top/bottom elastic overscroll | bars do not change spuriously; top forces shown | device |
| Hero | expanded → 50% → compact → reverse | one route/list surface; no row reflow or image snap | device |
| Hero | expanded at status bar/dynamic island | image/background and scrim remain fully opaque; compact/list chrome is fully opaque; no date/article/WebView underlap | device + screenshot |
| Hero geometry | expanded/intermediate `pHero`/compact | no independent spacer, transparent band, background leak, or seam between hero/source title/compact chrome and first date header; one opaque paper surface and one date+rows scroll surface | geometry/snapshot + simulator + physical device |
| Hero | image ready late / no image fallback | motion unaffected; fallback remains valid | stress device |
| Media | landscape body image | 100vw/full-bleed to both screen edges, square corners; text/caption retain inset | device + screenshot |
| Async | translation/theme/filter update during tracking | no ownership change, layout jump, or anchor loss | stress device |
| Loading | sync, article, and translation operations overlap | exactly one visible owner per surface; sync arrow only during real sync; no system spinner duplication; failure becomes error+retry | stress device + signpost |
| Color | theme accent changes | only Settings switch and Reader progress ring use accent; ordinary icon/link/star/selection/read-mode remain neutral gray/black; no legacy mint/green | device + source check |
| Naming | new Babel 2.0 source/resource/test/doc | Gate A forbids new legacy tokens in code, resources, tests, user-visible copy, leaf filenames, types, methods, accessibility IDs, log categories, and routes; inherited parent target/directory names are ignored, while required old build/module references are explicit build/test harness allowlist entries and persisted/system identity is confined to the single `LegacyIdentityCompatibility` boundary; an allowlist cannot be a second persisted/system identity outlet | source check |
| Refresh | 60 Hz and 120 Hz | no visible hitch; budgets respected | Instruments + device |
| Stress | 30 repeated transitions (`target` stress count) and rapid interruptions | no retained controllers, broken tokens, or stuck recognizers | device + memory trace |

Acceptance is two-stage: automated/static checks establish invariants and math; a
physical iPhone run establishes continuity, touch-following, perceived latency, and
visual stability. A screenshot or static overlay cannot close the second stage.

## 16. Legacy boundaries and first implementation slice（audit-only historical reference）

The first implementation slice should introduce an isolated motion/navigation layer and
route-level adapters, then migrate one interaction at a time. It should not become a
second formal app target. Data/domain objects may be reused where behavior is not owned
by the legacy UI.

The old type names and paths in this section are `audit-only historical reference`; they
define the migration boundary only and are excluded from Gate A. Route A still requires
all new motion code and user-visible surfaces to use Babel/Babel2 names, with required
old build/module/test-harness references isolated in the explicit build/test harness
allowlist and persisted/system identity isolated behind the single
`LegacyIdentityCompatibility` boundary; the allowlist cannot be a second persisted/system
identity outlet.

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

## 17. Supersession note: latest user decisions over older Figma Draft clauses（audit-only historical reference）

This note records the motion-specific overrides without editing the source files under
`Figma Drafts/`. Every old clause, type, and path named below is an `audit-only historical
reference`; these citations do not participate in Gate A. The current contract and its
acceptance matrix are authoritative when an older static Draft describes a different
boundary.

- `Figma Drafts/INTERACTION-CONTRACT.md` Feed hero bullets (approximately lines 70–74),
  and `Figma Drafts/BATCH-01-SPEC.md` Feed bullets (approximately lines 57–61 and
  287–290), formerly put expanded hero below the opaque status region and forbade
  underlap. Superseded for expanded state: hero image/background extends through the
  status-bar/dynamic-island region with its own fully opaque image/background and
  contrast scrim. Compact/list chrome remains fully opaque; scroll content never shows
  through it.
- `Figma Drafts/INTERACTION-CONTRACT.md` Reader action rule (approximately line 152)
  and `Figma Drafts/BATCH-01-SPEC.md` Reader action/change-log rules (approximately
  lines 73 and 234–237) formerly made the top action `Share Long Image` and assigned
  ordinary sharing to long press. Superseded: top slot is system Share; long image is a
  bottom-toolbar tap-only action; long press is not a share route.
- The earlier Reader checkpoints did not require title/byline to be visible on the
  first settled frame. Superseded: title/date/byline are visible above body on entry;
  one continuous collapse surface moves them into compact chrome while icon/progress
  fade in, with no asynchronous snap or disappearance.
- Older loading/refresh component notes in `Figma Drafts/BATCH-01-SPEC.md` (approximately
  lines 145 and 169–173) record component geometry and reuse, but do not define a
  visibility/ownership rule. The latest user decision adds that missing rule: sync arrow
  is only shown and rotated during real syncing and hides on completion;
  article/translation loading uses skeleton/passive state, with no system spinner
  duplication.
- The latest user decision tightens the older generalized accent rule in
  `Figma Drafts/BATCH-01-SPEC.md` (approximately lines 120–121, which only keeps accent
  out of the three master screens except authentic favicon/subtle state); it does not
  claim those lines prescribed green links. The tightened rule is: neutral gray/black
  owns ordinary controls and links, no hard-coded legacy mint/green is allowed, and the
  user accent is reserved for Settings switches and the Reader progress ring.
- Any interpretation of rounded thumbnail/media guidance as a body-image rule is
  superseded: landscape body media is 100vw/full-bleed and square-cornered; text/caption
  retain reading inset, portrait/inline media is not forced full-bleed, and wrappers may
  not add radius.

The naming gate is also normative: all new Babel 2.0 motion code, resources, tests, and
documentation use Babel/Babel2 naming. Historical build/module/test-harness identifiers
may remain only in a clearly scoped explicit allowlist; historical persisted/system
identity may remain only behind the single `LegacyIdentityCompatibility` boundary. The
allowlist is never a second persisted/system identity outlet, and neither category may
appear in user-visible UI. The phase covered by this contract does not perform internal path/symbol/project/target/scheme/CI renaming; that work
waits for stable real-device acceptance. Bundle/data identity and external repository
identity require a separate migration project and explicit authorization.
