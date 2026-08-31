# Babel — Reeder Classic UI · Batch 01

## Source of truth

1. `Reeder screenshots/4.PNG` — root Home screen with account entry.
2. `Reeder screenshots/2.PNG` — Feeds / Library hierarchy.
3. `Reeder screenshots/1.PNG` — selected-feed article list with thumbnails.
4. `Reeder screenshots/3.PNG`, `IMG_2771.PNG`, `IMG_2774.PNG` — reader top, body, and toolbar states.
5. Existing measured ledger: `Design/reeder-classic/REFERENCE_LEDGER.md`.
6. Babel product constraints: translation is a quiet reading layer, not an AI destination.

The stopped Soft Shell direction is not a visual source. Existing Babel code is implementation evidence only; when it conflicts with the locked screenshots, the screenshots win.

## Canvas and screen set

- Device frame: 402 × 874 pt (1206 × 2622 px at 3×).
- Batch 01 screens: `01 · Home`, `02 · Library`, four Feed presentation checkpoints (`03A`–`03D`), and three Reader states: `04A · Reader / Original`, `04B · Reader / Translating`, `04C · Reader / Translated`.
- Batch 01 appearance: fully composed Light screens. Semantic color variables include Light and Dark modes so the same components can be switched later without rebuilding.
- Screen background: warm reading surface, not pure dashboard white.

## Measured visual contract

### Global

- Typeface: SF Pro. No Inter fallback in the authored Figma file.
- Primary ink: near-black warm gray, approximately `#3A3A3A`.
- Secondary ink: approximately `#787878`; tertiary metadata uses lower contrast.
- Light background: measured `#F5F2F1`.
- Dark background token: measured `#1C1C1C`.
- Light selection surface: measured `#D8D5D6`.
- Hairline: 0.5 pt, low-opacity neutral.
- Major horizontal text inset: 20 pt. Compact list structures may use 10–16 pt outer insets where the screenshot shows it.
- Icons: monochrome, thin-to-regular SF Symbols geometry; no colored icon tiles except real feed favicons.

### 01 · Home

- Root-home structure follows `Reeder screenshots/4.PNG`: status bar, sparse two-action navigation, centered brand-mark region, short separator, one account card, and the compact three-state bottom toolbar.
- Home navigation shares the global top control centerline. Account/view toggle uses x = 32; Add uses x = 370.
- Brand-mark region is 68 × 68 pt at (167, 132), followed by a 182 × 0.5 pt divider at (110, 246).
- The current geometric `B` is a temporary placeholder requested during review. It is not the final Babel logo and must remain replaceable through the `Home Mark` component without moving surrounding layout.
- Account card is 382 × 93 pt at (10, 276), with an 8 pt radius, monochrome cloud icon, and the three lines `Feeds`, `Syncing...`, and `43,717 Unread Items`.
- Bottom toolbar reuses the approved compact `Context=Library, Selection=Unread` component at y = 802.

### 02 · Library

- Large `Feeds` title: approximately 36 pt semibold in the expanded state.
- Sync subtitle: approximately 16 pt regular, secondary ink.
- Folder/feed row height: 44 pt.
- Feed icon: approximately 19 pt.
- Top-level icon/text column: approximately 32 pt from the left; nested feed content: approximately 54 pt.
- Unread counts align to a stable right column approximately 36 pt from the right edge.
- Selected feed is the only rounded selection surface; rows are otherwise flat.
- No cards around folder groups.

### 03 · Feed

- The collapsing Feed hero migrates the existing `TimelineFeedHeader` implementation. Its current `FeedHeroIconLoader` → `FeedIconDownloader` → `FaviconDownloader` source chain, cache, analysis, image treatment, and fallback stay authoritative.
- Expanded hero height is 169 pt below the opaque 59 pt status region. The resolved feed image is enlarged with `aspectFill`, cropped, moderately dimmed while remaining identifiable, and faded into the paper surface toward the lower edge. Navigation actions remain in their fixed slots; a centered circular feed mark and lower-edge title establish feed identity.
- The title glyphs remain effect-free. While the title overlaps the hero image, a two-layer `Hero Title Readability Feather` sits behind the complete title area. Its low-opacity warm-paper core and larger blurred outer field fade continuously to transparent, with no visible edge, rounded-card silhouette, border, or box shadow. The feather follows the transition checkpoint and disappears with the image in the compact paper-only state.
- The 50% checkpoint linearly migrates the source mark and title toward the compact header while moving the article timeline upward as one surface.
- The compact state removes the image, restores the warm-paper surface, and pins a 99 pt header containing the unchanged action row plus a small feed mark and one-line title.
- The no-hero checkpoint is intentionally the prior `03 · Feed` design, not a blank image placeholder. It is the visible result of the existing implementation's fallback, not a new Figma-defined fallback algorithm.
- Date section labels use compact uppercase metadata.
- Source metadata: approximately 11–12 pt; article title: 17 pt; preview: 17 pt with quieter color.
- Unread title uses semibold; read title uses regular and lower contrast.
- Favicon: approximately 26 pt.
- Thumbnail: measured 70 × 70 pt with restrained 5 pt radius.
- Rows are separated by vertical whitespace, not card containers or strong rules.
- Bottom toolbar stays flat; only the active `UNREAD` filter uses a compact pill.

### 04 · Reader

- Header actions: close, more, tag, Share Long Image. They sit in a quiet 58 pt control band below the status area. A normal tap shares the article as a generated long image; a long press opens the standard iOS share sheet.
- Article left/right inset: approximately 20 pt.
- Date/source metadata: compact uppercase, tertiary ink.
- Title: bold SF Pro, approximately 34 pt, tight line height.
- Author/source block: approximately 12 pt uppercase, tertiary ink.
- Body: approximately 19 pt regular with about 30 pt line height and generous paragraph spacing.
- Bottom toolbar: read, star, next, text/translation, and `译 / Original` state. Translation is visually equal to typography controls, not a primary CTA.
- No AI panel, sparkle icon, gradient, glass card, floating action button, or purple accent.

## Local component scope

- Navigation Bar / Library
- Navigation Bar / Home
- Navigation Bar / Feed
- Navigation Bar / Reader
- Home Mark
- Home Account Card
- Folder Row
- Feed Row
- Feed Row / Selected
- Article Row / Text
- Article Row / Thumbnail
- Reader Toolbar
- Feed Toolbar
- Translation Toggle
- Metadata Label
- Empty State (component only; not placed as a Batch 01 master screen). Its no-unread artwork is a custom monochrome confused bear surrounded by three question marks. The icon remains in the existing 40 pt slot; outline and facial details inherit `Babel/icon`, while the face interior inherits the empty-state background.

## Phase 0 gap analysis

### Exists in code, missing in the new Figma file

- Babel palette values and SF Pro typography decisions.
- Real data hierarchy and read/unread behavior.
- Reader translation action and toolbar semantics.
- Measured Reeder geometry in `REFERENCE_LEDGER.md`.

### Exists in Figma libraries, not yet adopted

- Apple `Status bar - iPhone` component.
- Apple iOS toolbar and separator assets.
- Apple semantic colors and body text styles.

These assets are candidates only. iOS 26 toolbar components use a newer material language than Reeder Classic and will not be imported wholesale. The status bar may be reused; the Reeder-specific chrome and list rows will be authored locally.

### Conflicts and resolutions

- Old Soft Shell uses orange accents, thick rounded icons, and shell/card framing. Resolution: reject as visual source for Batch 01.
- Current Babel `accent` differs between light and dark and some current controls are stronger than the reference. Resolution: keep accent out of the three master screens except authentic favicons and subtle state indication.
- The attached prompt asks for both light and dark interpretations. Resolution: build Light master screens plus Light/Dark semantic variables in Batch 01; duplicate and visually tune full Dark masters in Batch 02.
- The prompt says `Feeds / Library`, while one screenshot shows an account-entry card. Resolution: use the deeper `Feeds` hierarchy as the Batch 01 home/library screen because it contains the requested grouped subscriptions and unread counts.

## Acceptance boundary

- Figma structure and screenshots can verify hierarchy, dimensions, clipping, text wrapping, reusable instances, and token mode wiring.
- Only same-device visual comparison and the user's iPhone review can approve perceptual similarity.
- No percentage similarity claim is valid without locked same-state overlays.

## Batch 01 draft status — 2026-08-30

- Completed editable Figma masters: `01 · Home`, `02 · Library`, `03 · Feed`, and `04 · Reader` at 402 × 874 pt.
- Completed local reusable components for navigation, folder/feed rows, article-row variants, feed/reader toolbars, translation state, metadata, unread filter, status bar, and empty state.
- Completed structure-level screenshot validation for all three masters: no frame overflow, toolbar displacement, or cross-row title overlap remains in the composed screens.
- Figma MCP currently lists `SF Pro` as available but renders SF Pro text layers blank. The visible Figma draft therefore uses Inter as a documented render fallback. Production iOS typography remains SF Pro.
- Apple `Status bar - iPhone` was discoverable in the connected iOS library but import was rejected by the library permission boundary. A local editable status bar was authored instead.
- Feed thumbnails remain neutral 70 × 70 pt placeholders. Replacing them with extracted reference-safe image assets is pending and is not counted as complete visual fidelity.
- Full dark-mode master screens remain Batch 02 work; Batch 01 only establishes Light masters plus Light/Dark token collections.

## Review correction 01 — 2026-08-30

- Feed Toolbar now exposes selected states for `UNREAD`, `STARRED`, and `ALL`. The Library toolbar variants use a 26 pt vertical centerline; the denser Feed toolbar uses a 24 pt centerline. Every visible control in each variant was checked programmatically against that centerline.
- Superseded by Review correction 02: this pass grouped `Label` before `Chevron`; the direct Reeder screenshot recheck established that the source-of-truth order is `Chevron` before `Label`.
- The old loading/refresh mark was replaced in both Library and Feed navigation bars with a smaller counterclockwise refresh arrow and a lighter neutral backing disc.
- Article Row typography was tightened to match the 99 pt row geometry seen in the reference list: source 10 pt, time 11 pt, title 15.5 pt with a fixed 39 pt two-line region, and preview 14.5 pt with a fixed 19 pt one-line region. All fields use end truncation; all four Text/Thumbnail × Read/Unread variants were visually rechecked in the composed Feed screen.
- Figma reports fixed-height truncating text as `textAutoResize = TRUNCATE` and leaves `maxLines` unset. The visible two-line/one-line limits are therefore enforced by the 39 pt and 19 pt text-box heights, not by a stored `maxLines` value.

## Review correction 02 — 2026-08-30

- Rechecked `Reeder screenshots/2.PNG`. Folder rows now use the source-of-truth order `Chevron → Label → unread count`: the chevron sits to the left of the folder name in both collapsed and expanded variants.
- Superseded by Review correction 03: the Feed toolbar's trailing Search action was initially replaced by a standalone languages glyph; it now uses the shared two-state `Translation Toggle` component.
- Search moved into `Navigation Bar / Feed`, immediately to the left of More. Search occupies a 24 × 24 pt icon box at x = 318; More remains at x = 358, leaving a 16 pt visual gap. Both controls use y-center = 22 pt.
- All five visible controls in the Feed bottom toolbar use y-center = 24 pt after the replacement.
- Screenshot validation completed on the Folder Row component set, Feed navigation component, Feed toolbar component, full `01 · Library` master, and full `02 · Feed` master. No overlap or frame overflow was observed in these Figma renders.

## Review correction 03 — 2026-08-30

- `Translation Toggle` is now the single translation-control component for all authored Babel screens. It is a two-variant component set with the state axis `Display=Translation | Original`.
- `Display=Translation` means translated content is currently visible and renders bold `译` beside small `原文`.
- `Display=Original` means original content is currently visible and renders bold `原` beside small `翻译`.
- Both variants are 58 × 44 pt. The primary character uses Inter Semi Bold at 15 pt; the secondary label uses Inter Regular at 8 pt. Their fills remain bound to the existing primary and secondary semantic text-color variables.
- Feed Toolbar and Reader Toolbar now use instances from the same component set. The standalone languages glyph previously used for Feed title translation was removed.
- Full-screen screenshots of `02 · Feed` and `03 · Reader` were checked after propagation. Both current examples use `Display=Translation`; the Screens page contains no remaining node named `Translate Titles`.
- This change defines the Figma visual and state contract only. Production code must map the actual content state to the matching variant when implementation begins.

## Review correction 04 — 2026-08-30

- The earlier loading-arrow drawing used a cubic Bezier approximation and was rejected because its curvature did not read as a true circle. That construction has been removed.
- Both `Navigation Bar / Library` and `Navigation Bar / Feed` now use the same SVG geometry: a fixed-radius circular arc (`r = 5 pt`) with a 2.2 pt round-capped stroke and a separate filled arrowhead at the upper-left.
- The backing disc is a true 24 × 24 pt ellipse. The arrow occupies a centered 16 × 16 pt frame; Library uses disc/icon origins `(189, 3)` / `(193, 7)`, while Feed uses `(189, 10)` / `(193, 14)` to preserve each navigation component's original vertical center.
- The disc remains bound to `color/background/selection` at 47% opacity. The arrow remains semantically bound to primary ink and uses 91% node opacity to match the measured Reeder screenshot tone without introducing an untracked raw color.
- Component metadata and full-screen screenshots for `01 · Library` and `02 · Feed` were checked after propagation. Both masters show the same centered, unclipped circular loading indicator.

## Review correction 05 — 2026-08-30

- Removed the standalone trailing chevron from the `Folders` section heading on `01 · Library`.
- The only remaining folder-state affordances are the chevrons placed to the left of individual folder names. Collapsed folders point right; expanded folders point down.
- The `Folders` label position, unread-count column, folder/feed rows, and bottom toolbar were not changed.
- The complete 402 × 874 pt Library master was screenshot-checked after removal.

## Review correction 06 — 2026-08-30

- Top and bottom chrome now follow explicit fixed-slot contracts across all three screens and all authored toolbar states. A control keeps the same semantic slot when it exists; when it does not exist, the slot remains intentionally empty rather than allowing neighboring controls to drift.
- Every bottom toolbar frame is 402 × 72 pt at screen y = 802, with the control centerline at screen y = 826. Bottom slot centers are x = 32, 104, 201, 290.5, and 362.
- Feed/Library bottom actions map to Read All, Star, Filter, List, and Translation. Reader actions map to Read State, Star, Next, Reading Controls, and Translation. The Unread, Starred, and All selected pills keep their own widths but stay centered on their corresponding family slot.
- Every top navigation component starts at screen y = 59, with its control centerline at screen y = 81. Structural top slot centers are x = 32, 201, 290, 330, and 370.
- Library maps Refresh to x = 201 and Add to x = 370. Feed maps Back to x = 32, Refresh to x = 201, Search to x = 330, and More to x = 370. Reader maps Close to x = 32, More to x = 201, Tag to x = 290, and Share Long Image to x = 370; x = 330 remains blank.
- The Library title and sync subtitle moved down 7 pt so the aligned top controls retain clear separation from the large title without moving the list content.
- Programmatic geometry validation passed all 29 expected component control centers and all 10 checked screen-level positions. Full Library, Feed, and Reader screenshots plus all Feed toolbar states and Reader Toolbar were visually inspected after propagation.

## Review correction 07 — 2026-08-30

- The Reader article-content frame remains fixed at screen y = 117; only its internal content rhythm changed.
- The blank space above the date/title group was reduced from 78 pt to 26 pt, exactly one third of the previous value requested in review.
- Date, title, byline, intro, blockquote, and closing paragraph all moved upward by 52 pt. Their new local y positions begin at 26, 55, 180, 274, 326/327, and 623 respectively.
- The top navigation and 72 pt bottom toolbar remain fixed. The updated 402 × 874 pt Reader screenshot shows no overlap between the article header and body, while exposing more article content in the first viewport.

## Review correction 08 — 2026-08-30

- Rechecked the bottom-toolbar artwork against the locked Reeder device captures. The previous Figma controls confused the outer control frame with the visible glyph size, making several controls—especially circles and list/reading controls—visually too large.
- The toolbar frame remains 402 × 72 pt at screen y = 802, and all five semantic slot centers remain unchanged. Only the visible artwork and selected-state surfaces were reduced.
- Icon control frames remain 24 × 24 pt for stable placement. Visible canonical artwork is now: circle 16 × 16 pt, star approximately 16 × 15.2 pt, Next 18 × 9 pt, and list/reading controls no wider than 18 pt with 2.2 pt lines.
- Translation Toggle keeps its shared 58 × 44 pt component frame, but visible typography was reduced from 15/8 pt to 13/7 pt for the primary and secondary labels.
- Selected pills are now Unread 78 × 26 pt, Starred 90 × 26 pt, and All 68 × 26 pt. Each pill is recentered on the same semantic slot used before the size reduction.
- Visual size and interaction size are separate contracts. Production must retain at least a 44 pt hit target around these controls without enlarging the visible glyphs.
- All four Feed/Library toolbar variants, Reader Toolbar, and the three 402 × 874 pt master screens were screenshot-checked. A final geometry audit passed all 34 expected centers and visible-size checks.

## Review correction 09 — 2026-08-30

- Added the true root-home master from `Reeder screenshots/4.PNG`. The previous Library master remains the deeper Feeds hierarchy and has been renamed `02 · Library`; Feed and Reader are now `03 · Feed` and `04 · Reader`.
- Created `Navigation Bar / Home` and `Home Account Card` as reusable local components. The Home screen reuses the existing Status Bar and the already-approved compact Library/Unread Feed Toolbar.
- The Reeder cube was initially reconstructed during component exploration but was explicitly rejected before screen composition. Its artwork was removed and replaced with a restrained geometric `B` monogram inside the stable `Home Mark` component.
- The `B` is a temporary placeholder only. A later brand decision should replace the component artwork while preserving the 68 × 68 pt mark region and surrounding coordinates.
- Final Home geometry: Home Mark at (167, 132), 182 pt divider at y = 246, account card 382 × 93 pt at (10, 276), and bottom toolbar at y = 802.
- Full-screen screenshot validation completed. All 10 audited canvas/section coordinates passed and no descendant overflow was found.

## Review correction 10 — 2026-08-30

- The first Home Account Card cloud vector filled almost the entire 44 × 44 pt icon frame. Its 3.5 pt stroke crossed the left frame edge and visually clipped.
- The cloud artwork was reduced from 43 × 29 pt to 36 × 24.28 pt and recentered inside the unchanged 44 × 44 pt icon frame. Stroke weight scaled with the vector.
- Render-bound validation confirms the cloud is fully contained, with approximately 2.53 pt horizontal and 8.40 pt vertical padding after stroke expansion.
- The card frame, three text lines, account-card position, Home layout, and bottom toolbar remain unchanged. Component and full-screen screenshots were rechecked after propagation.

## Review correction 11 — 2026-08-30

- Corrected the semantic mapping: `All Filter Icon` and `Reading Mode Icon` are separate reusable component sets, not one global control.
- Library and Feed use the restored Reeder-style `All` icon: three left-aligned lines that shorten downward. It has 24 × 24 pt Toolbar and 15 × 15 pt Compact variants, including the compact icon inside the selected `All` pill.
- The rounded reading-page icon is reserved for Reader Toolbar on the article-content screen. Its three internal manuscript lines retain the less-crowded spacing accepted after the supplied reference was scaled down.
- Bottom-toolbar slot centers, selected-pill dimensions, control frames, and interaction-target guidance are unchanged. Production must map `All` and Reader mode to separate vector assets.

## Review correction 12 — 2026-08-30

- Replaced the Reader navigation bar's generic share artwork with the dedicated `Share Long Image` action requested in review.
- Interaction contract: a normal tap generates and shares the current article as a long image; a long press invokes the standard iOS share sheet for ordinary sharing destinations and formats.
- The new 24 × 24 pt monochrome glyph combines an open image frame, restrained mountain/sun detail, and a circular upload arrow at the upper right. It follows the supplied reference but removes nonessential detail so it remains readable beside the other toolbar-scale controls.
- The action frame remains at local `(358, 10)` inside `Navigation Bar / Reader`, preserving the fixed screen center `(370, 81)`. The old generic share vector was removed rather than hidden.
- The isolated action, complete Reader navigation component, and full `04 · Reader` master were screenshot-checked after propagation. No control slot, article content, or bottom-toolbar geometry changed.

## Review correction 13 — 2026-08-30

- Added the complete Settings information architecture on the dedicated `03 · Settings` Figma page. It contains one category home, eight first-level category pages, and nine necessary second-level editing pages.
- Settings content is sourced from the current Babel/NetNewsWire iOS implementation rather than copied from Reeder. The mapping covers account providers and sync, OPML import/export, discovery credentials, timeline behavior, reader preferences, translation model/API, appearance/language, notifications, diagnostics, help, and About.
- Added reusable `Settings Root`, `Settings Back`, and `Settings Editor` navigation components plus disclosure, value, toggle, action, choice, section-header, and text-field components. Standard actions and selected states use monochrome ink; only destructive actions retain warning red.
- Deferred-save pages—Discovery API Keys, Article Theme, Translation Model, Translation API, and Interface Language—use the explicit Cancel / Save editor navigation. Immediate choices and one-tap actions use the ordinary Back navigation.
- Final audit: 18 screen frames at 402 × 874 pt, eight Settings Home category entrances, zero descendant overflow, zero non-Inter Figma fallback text, and zero incorrect editor-navigation assignments. Visual screenshots were checked for all first-level pages and all nine secondary pages.

## Review correction 14 — 2026-08-30

- Split the article-content design into three explicit, adjacent Reader masters: `04A · Reader / Original` (`22:38`), `04B · Reader / Translating` (`117:263`), and `04C · Reader / Translated` (`117:317`). All three preserve the approved 402 × 874 pt viewport, navigation slots, compressed article-header rhythm, and compact bottom-toolbar geometry.
- `04A` keeps the original-language article layout and selects the shared `Display=Original` translation-toggle variant, shown as bold `原` with small `翻译`.
- `04B` is a real motion state, not merely a static loading mockup. It uses the new shared `Display=Translating` variant, shown as bold `译` with small `生成中`, while paragraph-shaped skeletons progressively give way to translated text.
- The translating timeline runs for three seconds across four content segments. Each skeleton fades out as its replacement text fades in and rises 8 pt. The short overlap is intentional crossfading; it prevents blank gaps and preserves the article's line and paragraph geometry.
- `04C` shows the completed translated article and selects `Display=Translation`, shown as bold `译` with small `原文`. Its content styling and layout remain parallel to the Original state rather than becoming a separate AI-results surface.
- Motion validation used the exported Figma timeline itself: a 3.2-second low-resolution video was sampled at five stages. The first sample is skeleton-led, the intermediate samples show paragraph-level handoff, and the final sample contains translated text with all skeletons removed. No full-page flicker, toolbar movement, or article-content jump was observed.
- The connected Figma motion API permits keyframe and duration changes but does not expose loop-mode writes. The exported preview therefore loops. This is not the product contract: the iOS implementation must run this transition once, then stay in `04C · Reader / Translated` until the user switches back to the original.
- This establishes the Figma visual and interaction contract only. Production Swift/SwiftUI still needs to bind actual translation-stream events to the four staged content regions and the three translation-toggle states.

## Review correction 15 — 2026-08-30

- Replaced the previous Reeder-style descending three-line `All Filter Icon` with the newly supplied four-line reference: four equal-length, horizontal, round-capped strokes.
- The Toolbar variant remains inside its unchanged 24 × 24 pt frame and uses four 15 pt lines at 1.8 pt weight. The Compact variant remains inside its unchanged 15 × 15 pt frame and uses four 9.375 pt lines at 1.125 pt weight.
- Both vector blocks are mathematically centered in their component frames. A structural audit confirmed exactly four path segments per variant and identical segment lengths within each variant.
- The source component continues to drive both the ordinary All action and the Compact icon inside the selected All pill. All Feed Toolbar variants plus the Home, Library, and Feed master screens were screenshot-checked after propagation; bottom-toolbar slots, centerlines, pill dimensions, and hit-area guidance did not change.

## Review correction 16 — 2026-08-30

- Lowered the visual prominence of form surfaces on `21 · Discovery API Keys` and `52 · Translation API`. The original pure-white elevated fill read as a separate card layer against the warm Reader-style settings background.
- Added `color/background/input` to both semantic color collections. The Light token aliases `warm/100`, one restrained step below the `warm/50` page background; the Dark token aliases `neutral/900`, one step above the dark base. Both variables use `FRAME_FILL` / `SHAPE_FILL` scopes and the iOS code syntax `BabelPalette.inputBackground`.
- `Settings Text Field` Normal and Secure variants now bind to the dedicated input-background semantic. The existing 0.5 pt semantic hairline, 8 pt radius, 362 × 68 pt field geometry, label/value typography, and secure-value treatment remain unchanged.
- Five shared instances propagate the change: three fields on Discovery API Keys and two fields on Translation API. Both full 402 × 874 pt pages and the component set were screenshot-checked after the final adjustment.

## Review correction 17 — 2026-08-30

- Added the dedicated `04 · Interaction & States` page (`138:2`). It contains the global behavior legend, Reader scrolled-state contract, interactive Feed-filter samples, and a normative control behavior matrix.
- Added `04D · Reader / Scrolled` (`143:444`) on the Screens page. After the large article title and byline leave the viewport, the same Reader route retains a compact sticky header below the status area; the bottom toolbar is hidden during downward reading.
- Added `Reader Compact Header` (`143:73`) with 0%, 25%, 60%, and 100% QA samples. These are not runtime modes. Production receives one continuous progress value `p ∈ [0,1]` and renders one uninterrupted clockwise arc beginning at 12 o'clock.
- The compact feed icon is 42 pt inside a 48 pt progress frame, is clipped to a true circle, and is concentrically wrapped by the independent progress track. The current `T` source mark is only a runtime-favicon placeholder.
- Completed the Feed Toolbar set with Feed/Starred (`146:1013`) and Feed/All (`146:1026`). All six Library/Feed states explicitly lock their label values, hide duplicate selected icons, preserve fixed slots, and expose 44 pt hit targets.
- Prototype reactions were read back from Figma after authoring. Every nonselected Starred/Unread/All hit target uses `CHANGE_TO` with a 180 ms Smart Animate transition and resets the list to top; none uses navigation, overlay, modal, card, menu, or sheet.
- Folder Row collapsed and expanded states now use in-place `CHANGE_TO` reactions and preserve the Library route and scroll position.
- Full screenshots were checked for the Reader Compact Header component set, `04D · Reader / Scrolled`, the Reader interaction contract, the Feed-filter interaction contract, and the control behavior matrix. Metadata checks found no screen overflow; the behavior-table overflow dividers discovered during validation were removed.

## Review correction 18 — 2026-08-30

- Replaced the single Feed master with four explicit presentation checkpoints on `02 · Screens`: expanded hero (`22:37`), 50% collapse (`244:541`), compact sticky header (`244:552`), and the preserved no-image fallback (`244:563`). They describe one route and one list, not four navigation destinations.
- The expanded hero begins below the fully opaque status bar, uses a full-width darkened editorial artwork treatment, keeps Back / Refresh / Search / More in their established slots, centers the source mark, and anchors the feed title at the lower edge.
- The transition checkpoint linearly moves and scales the source identity while translating the complete article timeline upward. The compact checkpoint fully removes the hero image and returns to the semantic warm-paper background with a small feed mark and one-line title.
- Superseded by correction 19: this pass over-specified a new hero eligibility/fallback contract even though the project already contains the production image pipeline.
- All four frames remain 402 × 874 pt. The opaque status surface, article-row instances, 70 pt thumbnails, and Feed Toolbar at `[0, 802, 402, 72]` were retained and screenshot-checked across the four checkpoints.

## Review correction 19 — 2026-08-30

- Replaced the nearly black prototype masthead with a real New York Times feed-icon sample cropped from the locked Reeder device capture. The mark is enlarged to bleed beyond the hero bounds, moderately dimmed, kept visibly textured, and faded into the warm paper surface at the bottom.
- The visual sample now demonstrates the existing renderer rather than inventing a new asset contract. Coding must reuse `TimelineFeedHeader`, `FeedHeroIconLoader`, `FeedIconDownloader`, `FaviconDownloader`, and their current cache/analysis/fallback behavior.
- Expanded, transition, and compact screenshots were checked after replacement. The article rows, date section, fixed top-control slots, and bottom toolbar were not rebuilt.

## Review correction 20 — 2026-08-30

- Superseded by correction 21: this pass incorrectly attached shadows to individual title glyphs.

## Review correction 21 — 2026-08-30

- Superseded by correction 22: the title-width plate still presented a detectable rounded-card boundary and looked like a UI label.

## Review correction 22 — 2026-08-30

- Removed the rounded plate, background blur surface, and box shadow. Added two boundaryless `Hero Title Readability Feather` layers behind the expanded and transition titles.
- A small low-opacity warm-paper core supports the title while a larger layer-blurred field spreads the luminance change outward until it becomes fully indistinguishable from the surrounding hero image. There is no border, corner silhouette, card fill, or per-glyph effect.
- The compact paper-only state remains feather-free. Full-screen validation confirmed the treatment improves separation without introducing a visible component behind the title.
