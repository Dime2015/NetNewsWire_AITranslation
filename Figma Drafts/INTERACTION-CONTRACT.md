# Babel Figma Interaction Contract

Status: authored in Figma and structurally validated on 2026-08-30. This document is normative for coding. Static visual resemblance must not override the behaviors below.

## Stable Figma references

- File: `https://www.figma.com/design/0kFsVs9DLbE7Um96yrlBKg`
- Interaction page: `04 · Interaction & States` (`138:2`)
- Reader short/non-scrollable state: `04D1 · Reader / Short · No Sticky Header` (`180:370`)
- Reader long/collapse transition: `04D2 · Reader / Long · Shared Title Transition 50%` (`180:424`)
- Reader long/pinned downward state: `04D3 · Reader / Long · Pinned / Scroll Down` (`143:444`)
- Reader long/pinned upward state: `04D4 · Reader / Long · Pinned / Scroll Up` (`180:520`)
- Reader long/pinned downward-again state: `04D5 · Reader / Long · Pinned / Scroll Down Again` (`227:675`)
- Reader Compact Header component set: `143:73`
- Feed hero expanded state: `03A · Feed / Hero / Expanded` (`22:37`)
- Feed hero collapse checkpoint: `03B · Feed / Hero / Transition 50%` (`244:541`)
- Feed hero compact state: `03C · Feed / Hero / Compact` (`244:552`)
- Feed no-image fallback: `03D · Feed / No Hero Fallback` (`244:563`)
- Feed Toolbar component set: `22:35`
- Folder Row component set: `19:12`
- Reader scrolled contract: `146:2`
- Feed filter contract: `161:35`
- Control behavior matrix: `166:112`

## Starred / Unread / All

These are three mutually exclusive filters of the collection already visible in the current Library or Feed route. They are not destinations.

- Keep exactly one selection active.
- Keep the three family slots, centerlines, visible scale, and 44 pt hit targets fixed across all states.
- A tap changes the selected component state in place, applies the filter to the current scope, replaces the visible article collection, and resets the list to top.
- Preserve the current account, folder, or feed context.
- Do not push a controller, navigate to a new screen, present a card, open a filter menu, or present a sheet.
- Use a short selection-pill transition; the Figma prototype uses `CHANGE_TO` plus 180 ms Smart Animate.

Library variants:

- Unread `22:7`
- Starred `29:8`
- All `29:23`

Feed variants:

- Unread `22:18`
- Starred `146:1013`
- All `146:1026`

## Folder expansion

Folder rows expand and collapse inside the Library hierarchy.

- Collapsed `19:2` changes to Expanded `19:7`.
- Expanded `19:7` changes to Collapsed `19:2`.
- Reveal or hide direct child feed rows without leaving the Library route or changing its scroll position.
- Place the right/down chevron immediately left of the folder name. Do not add a trailing chevron.

## Feed source hero

The four Feed frames are checkpoints of one article-list route, not four destinations. The source hero is conditional presentation attached to the current feed.

Implementation boundary — migrate the existing feature; do not build another image resolver:

- Reuse `TimelineFeedHeader` and its current image chain: `FeedHeroIconLoader` → `FeedIconDownloader` → `FaviconDownloader`.
- Preserve the existing cache, suitability analysis, fallback, dominant-color treatment, and low-resolution softening rules. Figma does not replace or further specify that runtime logic.
- The Figma New York Times artwork is a visual specimen of the existing renderer: enlarge and `aspectFill` crop the resolved feed image, keep its identity recognizable, reduce its brightness without turning it into a black block, and fade it into the paper surface toward the lower edge.
- `03D` remains the visual checkpoint produced when the existing implementation does not present image artwork. Do not introduce a second fallback state machine during the UI migration.

Geometry and scrolling:

- Keep the status-bar surface fully opaque. The hero begins below the 59 pt status region and never underlaps system status items.
- Expanded state `03A` uses a 169 pt hero from screen y = 59 to 228. Navigation actions stay in their fixed slots over the hero; the feed mark is centered and the feed title/subtitle sit at the lower content edge.
- While the feed title overlaps image artwork in `03A` and `03B`, the title glyphs themselves have no shadow. Place the two-layer `Hero Title Readability Feather` behind the title: a low-opacity warm-paper luminance field whose center supports the text and whose blurred edges decay continuously to transparent. It must have no detectable border, corner, card surface, or box-shadow outline. The feather follows the title transition and is absent in the paper-only compact state `03C`.
- Keep the existing scroll-driven behavior in `TimelineFeedHeader`. Between `03A` and `03C`, it linearly interpolates hero height, image crop/opacity, source-mark position/scale, feed-title position/size, and list origin. `03B` is the 50% visual QA checkpoint, not a discrete runtime mode.
- At the collapse threshold, pin `03C`: the hero image has fully crossfaded away, the warm-paper compact header is 99 pt high below the status bar, and the small feed mark plus one-line title remain visible below the unchanged action row.
- Scrolling back toward the top reverses the same interpolation. Do not swap controllers, reset the filter, or reset the list position.
- The date header and every article-row instance translate with the list as one surface. Do not independently animate or reflow individual article rows during hero collapse.

Stable chrome:

- Back, refresh, Search, and More retain the global x slots 32, 201, 330, and 370 and the same 44 pt hit targets in all four states.
- The Feed Toolbar remains fixed at `[0, 802, 402, 72]` and preserves the current Starred / Unread / All selection while the hero collapses.
- Search, translation, filter selection, loading, and More-menu behavior are unchanged by hero eligibility or collapse state.

## Reader scroll-driven states

All `04D1`–`04D5` frames describe the same Reader route and article. They are state/animation checkpoints, never new pages in the navigation stack.

Status-bar surface:

- The full region from the physical top edge through `safeAreaInsets.top` uses `BabelPalette.background` at alpha 1. It is a fully opaque page surface, not glass, blur, vibrancy, material, or a scroll-edge effect.
- Status items such as time, signal, Wi-Fi, and battery remain system-rendered foreground content; only their backing surface is owned by the Reader.
- Article content and the transparent `WKWebView` must never be visible through this region. The Reader root view provides the opaque backing color.
- Hiding or revealing the Reader's top control row must not change the status-bar surface opacity. The surface remains fixed and opaque in `04D1`–`04D5`.
- `BabelReaderViewController` hides the system `UINavigationBar` and uses custom Reader chrome. Do not inherit the shell navigation bar's transparent/Liquid Glass appearance into the Reader.

Eligibility:

- If the rendered article height does not exceed the readable viewport, the article has no usable downward scroll distance. Keep the ordinary reader header and toolbar behavior; never reveal the compact title, circular feed icon, or progress ring. This is `04D1`.
- Only a genuinely scrollable article may enter the collapse and pinned states. Do not force a compact header onto a short article by time, tap, or an artificial delay.

Long-article collapse:

- Drive the transition from actual scroll offset. Figma timeline time is only a QA proxy for the scroll range; production must not autoplay it.
- While scrolling downward through the collapse range, move the large title toward the compact-title position with linear interpolation.
- Over the same range, fade the circular feed icon and progress ring from opacity 0 to 1 with linear interpolation.
- Scroll the remaining article header/body normally behind the sticky region; do not crossfade to a different Reader page.
- At the collapse threshold, pin the compact title, circular feed icon, and progress ring in their settled position. This is `04D3`.

Direction response after pinning:

- Continuing downward keeps the compact identity pinned and linearly hides the top control row and bottom Reader toolbar.
- Reversing upward reveals the top controls in a row above the compact identity and reveals the bottom Reader toolbar with the inverse short linear fade/translation. This is `04D4`.
- In the controls-visible layout, overlap the two rows' empty vertical padding by 14 pt instead of stacking the full 58 pt controls frame and 86 pt compact-header frame as separate loose blocks. The compact-header frame begins at y=103 pt and article content at y=189 pt in the 402 × 874 reference frame.
- Reversing downward again linearly hides both control rows without hiding or moving the pinned compact identity. This is `04D5`.
- After pinning, require 12 pt of accumulated travel in one direction before changing toolbar visibility. Ignore tiny direction reversals and top/bottom elastic overscroll so the bars do not flicker.
- Animate the top and bottom control groups together over 180 ms with linear opacity and translation. Do not animate the pinned compact identity when visibility changes.
- Preserve the exact article, route, normalized reading progress, and scroll position through every state change.

Continuous reading progress:

- Compute a continuous normalized value, not discrete variants:
  `p = clamp((contentOffsetY - collapseStart) / (maxScrollableOffset - collapseStart), 0, 1)`.
- Render a full neutral track and one uninterrupted accent arc.
- The accent arc starts at 12 o'clock and grows clockwise.
- At `p = 0`, no accent arc is visible. At `p = 1`, the accent arc is a closed full circle.
- SwiftUI should use a continuously driven trim/stroke; UIKit should use a continuously driven `CAShapeLayer.strokeEnd`. Do not map progress to the nearest Figma sample.
- Figma variants 0% (`150:43`), 25% (`143:43`), 60% (`140:28`), and 100% (`143:58`) are visual QA checkpoints only.

Feed icon geometry:

- Progress frame: 48 × 48 pt.
- Runtime feed icon: 42 × 42 pt, centered at `(3, 3)`, clipped to a true circle.
- Keep the icon and progress track concentric. The progress ring must remain independent from the image crop.
- The Figma `T` source mark is a placeholder. Production must load the article feed's real favicon or configured source artwork.

## Translation

Translation is an asynchronous state change within the same Feed or Reader route:

`Original → Translating → Translation`

- In Feed, translate article titles in place.
- In Reader, replace skeleton regions progressively with streamed translated text while keeping article geometry stable.
- Do not open an AI destination or a translated-results page.
- Toggling back to Original restores original text without losing the feed/article context or Reader scroll anchor.

## Other control behavior

- Feed Search: enter an in-place search mode scoped to the current feed/folder. Cancel restores the previous list and scroll context.
- Feed More: present scoped list actions as a menu or sheet, then dismiss to the same filter and scroll state.
- Reader Reading Controls: Reader-only menu or sheet for typography and appearance. Applying a choice updates the current article in place and preserves its reading position.
- Share Long Image: normal tap generates/shares the long image; long press opens the normal iOS share menu.
- Settings disclosure rows: push the named child page.
- Settings toggles: update immediately in place.
- Settings editors: push an editor; Cancel discards the draft; Save validates, persists, and returns.
- Loading indicator: passive status, not a button. Failure replaces it with a distinct retry action and readable error state.

## Settings short-choice popovers

Short enumerations are selected in place with an anchored popover. They do not push a controller or open a full-screen choice page.

- The closed row shows the setting title on the left and the current value plus a down chevron on the right.
- A tap presents a floating popover aligned to the right edge of the 362 pt settings content column. The popover overlays following rows; it never expands the layout or moves content downward.
- The popover uses the `Babel/Popover/Thick Glass` material: a translucent warm elevated fill, 32 pt background blur, a quiet inner highlight, a 0.5 pt translucent edge, and restrained dual shadows. Labels and checkmarks remain fully opaque.
- Keep one option selected. The selected option uses a fixed 18 pt checkmark slot; unselected options reserve the same slot at zero opacity, so labels never jump horizontally.
- Selecting an option updates the row value immediately and dismisses the popover. Tapping outside dismisses without changing the value.
- Present and dismiss with a short opacity plus scale transition centered near the row's trailing value. Production should use the native iOS menu/popover interaction where it provides equivalent geometry and behavior.
- Use this pattern for Timeline sort, Timeline grouping, Reader link handling, appearance mode, accent color, and interface language.
- Keep account destinations, API credentials, article-theme management/import, logs, support destinations, and other editor/destination rows on their existing navigation path.
- Keep boolean settings as switches. Do not convert a true Boolean into a two-item popover merely for visual consistency.

Figma state references:

- Timeline sort: `223:590`
- Timeline grouping: `224:632`
- Reader link handling: `224:1369`
- Appearance mode: `224:1482`
- Accent color: `224:1538`
- Interface language: `224:1609`

## Translation model catalog

Translation model selection is the deliberate exception to the short-choice popover rule. Tapping the `翻译模型` row pushes the dedicated editor at `110:560`; it must not present a menu, card, sheet, or popover.

- The closed row uses a trailing current value and right-pointing disclosure chevron.
- The editor keeps the current pending-selection behavior: Cancel discards the pending model; the checkmark saves it and returns.
- The first content control is `刷新模型列表`. Refresh keeps the user on this page, shows an in-place loading state, and replaces the catalog without resetting the navigation route.
- The first list section contains the ten models with the highest available runtime popularity score. Every row reserves a fixed 20 pt leading slot for the model vendor's repository logo, followed by an 8 pt gap and the model name; the trailing selection slot stays fixed. Figma labels are samples, not a frozen ranking.
- Remaining sections are grouped by vendor. Each section header places the repository vendor logo before the vendor name; unsupported vendors use the production letter-badge fallback.
- Each vendor section exposes exactly three representative popular models. If a vendor has fewer than three eligible models, show the available count without placeholders.
- Selecting a row changes the pending checkmark only. It does not auto-dismiss the page and does not save until the navigation checkmark is pressed.
- The catalog viewport scrolls vertically while the status and editor navigation bars remain fixed.

Figma references:

- Model editor: `110:560`
- Scroll viewport: `231:887`
- Refresh button: `231:889`
- Translation model disclosure row: `231:915`

Implementation sync note: the current source still uses `featuredCount = 15`, `perVendorLimit = 5`, and places refresh at the bottom. The approved design contract is Top 10, three per vendor, and refresh at the top; coding work must reconcile those constants and row order rather than treating the old implementation as the target.

## Validation boundary

Confirmed in Figma:

- Screen/component structure and stable node IDs.
- Explicit short-article no-sticky branch plus long-article transition, pinned-down, pinned-up, and downward-again frames.
- Linear manual keyframes for title collapse, compact-header reveal, and top/bottom control reveal/hide; exported videos were sampled at start, intermediate, and settled frames.
- Reader compact-header screenshots at representative progress points.
- Continuous single-arc geometry at 0%, 25%, 60%, and 100%.
- Filter labels, duplicate-icon visibility, fixed slots, and component reactions.
- Prototype reactions use `CHANGE_TO`, not navigation or presentation.

Still requires implementation and device acceptance:

- Real favicon loading and circular crop quality.
- Continuous progress behavior against actual article heights and safe-area changes.
- Scroll-offset threshold tuning, direction hysteresis, and toolbar reveal/hide timing on a physical iPhone.
- In-place filter data behavior in the current UIKit code.
