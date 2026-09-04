# Babel 2.0 App Icon Concepts

这是 Babel 2.0 的三版 App 图标概念探索。它们仅供用户选择方向，尚未接入任何 Asset Catalog，也没有修改现有 AppIcon。

## 共通设计合同

- `B` 是唯一清晰可读的主体；背后使用低调但仍可辨认的杂志封面/编辑版式水印。
- 水印只使用空白 masthead 条、栏线、页码感圆点、裁切标记和封面矩形层次，不包含可读标题或其他字母。
- 采用 Babel 当前 Soft Shell 视觉语言：橙色强调、石墨色文字、柔和纸面/灰色层次、平面连续和编辑感。
- 输出为完整不透明的 1024 × 1024 方形画布；不烘焙 iOS 圆角遮罩，交由系统处理。
- 不使用 Instapaper 或其他品牌的具体字形、比例、背景或商标元素。

## A · 经典编辑字标

文件：`babel2-icon-a-editorial.png`

以大比例粗衬线 `B` 作为传统杂志封面的主标题，纸面边框、栏线和裁切标记作为克制的背景水印。整体最接近“编辑部刊物”的气质，安静、成熟，小尺寸下轮廓最直接。

最终 prompt：

```text
Use case: logo-brand
Asset type: iOS app icon concept, final 1024×1024 square raster
Primary request: Refine the classic editorial Babel 2.0 lettermark concept. Create one original app icon with a large, custom bold serif capital “B” as the only clear readable character. Behind it, a subtle but unmistakable magazine-cover watermark made from offset cover rectangles, a masthead-like horizontal bar with no letters, column rules, crop marks, and abstract page-number dots; all watermark marks stay subordinate and contain no readable text.
Scene/backdrop: an opaque full-bleed square warm paper field covering every pixel of the 1024×1024 canvas
Subject: one centered black-warm graphite B, about 62% of canvas, optically balanced and legible at small size
Style/medium: flat vector-friendly editorial identity, crisp silhouette, premium restrained print-cover composition, light matte paper texture only
Composition/framing: generous clear margin, no transparent pixels, no rounded-corner mask, no mockup
Lighting/mood: even graphic lighting, calm and editorial
Color palette: Babel current Soft Shell colors: graphite #252729, paper #F3F4F4, muted line #D5D7D7, controlled accent orange #FF5A1F and tiny #FF6A2F
Text (verbatim): none; B is the only readable character
Constraints: preserve the strong B silhouette; opaque edge-to-edge square background; watermark visible but low contrast; original design only; iOS will apply its own mask
Avoid: transparency, rounded rectangle, phone/device mockup, 3D, bevel, glossy effects, heavy shadows, other letters, readable words, logos, trademarks, Instapaper or any other brand, copied I shape, image-generation watermark
```

核验：首次生成的纸张外缘出现透明区域，因此按单一针对性修改重新生成；最终版本为不透明 RGB 方图，`B` 轮廓清晰，背景版式可见但弱于主体，无可读副文字、圆角样机或水印。

## B · 负空间叠页

文件：`babel2-icon-b-layered.png`

以三层略微错位的编辑页面表达不同语言版本/译本之间的叠合关系。正面页面上的 `B` 以强烈的留白与黑白层次形成，橙色只出现在页边和登记标记，识别感比 A 更偏“印刷制作台”。

最终 prompt：

```text
Use case: logo-brand
Asset type: iOS app icon concept, final 1024×1024 square raster
Primary request: Create an original Babel 2.0 app icon concept, version B — a negative-space and layered-pages lettermark. The single clear focal subject is a bold capital “B” formed by precise negative space cut through two or three stacked editorial page planes. The B must read instantly as one letter, not as multiple symbols. Behind and around the B, show a restrained but noticeable magazine-cover watermark using layered page rectangles, quiet column rules, crop marks, and blank masthead bars; no readable words or letters.
Scene/backdrop: opaque full-bleed square icon canvas, warm paper and graphite editorial field
Subject: one unmistakable capital B created by negative space, with strong continuous outer contour; no other clear character
Style/medium: flat vector-friendly identity design, modern print-production geometry, crisp edges, controlled matte paper texture, premium and restrained
Composition/framing: centered B spanning about 60% of the square, layered pages offset only slightly to suggest translation between editions; generous margin; full square canvas; no baked rounded corners
Lighting/mood: even graphic lighting, subtle depth only through flat tonal layers, no photorealism
Color palette: Babel current Soft Shell colors — graphite #252729 and dark neutral #111314, paper #F3F4F4 and shell gray #E9EBEB/#D5D7D7, with controlled accent orange #FF5A1F as a small page-edge or registration mark
Materials/textures: flat ink and paper planes, faint print registration texture, no glossy surface
Text (verbatim): none; the B is the only readable character
Constraints: original design only; the B remains the dominant and legible shape at small icon size; watermark is clearly magazine-cover-like yet subordinate; opaque edge-to-edge square; iOS applies its own mask
Avoid: any other letter or readable text, logos or trademarks, Instapaper or other brand cues, copied I shape, decorative illustration, 3D, bevel, realistic paper stack, dramatic shadows, phone/device mockup, rounded-rectangle mockup, transparent background, image-generation watermark
```

核验：最终版本为不透明 RGB 1024 × 1024 方图；叠页层次和编辑版式水印明显，主体仍只有一个可读 `B`，没有额外可读字、品牌元素、圆角样机或生成水印。

## C · 主题色几何结构

文件：`babel2-icon-c-geometric.png`

用深石墨底、纸白几何 `B` 和少量 Babel 橙色校样线构成模块化封面网格。它最现代、最接近 Babel 的“跨语言编辑工作台”概念；网格和裁切结构可作为后续品牌系统的延展母题。

最终 prompt：

```text
Use case: logo-brand
Asset type: iOS app icon concept, final 1024×1024 square raster
Primary request: Create an original Babel 2.0 app icon concept, version C — a modern geometric editorial structure. Make a single bold, custom sans-serif capital “B” the only clear readable character, built from strong rectangular and curved geometric forms. Integrate the B with a precise modular magazine-cover grid: offset frame corners, crop marks, narrow columns, blank masthead bars, and a few abstract registration dots. The grid must be a subtle but clearly visible watermark behind the B, with no readable words or extra letters.
Scene/backdrop: opaque full-bleed square graphite editorial canvas, flat and quiet
Subject: one centered large capital B with clean geometric construction, occupying about 60% of canvas and remaining instantly legible at small iOS size
Style/medium: flat/vector-friendly modern identity mark, minimal geometry, crisp high-contrast silhouette, premium editorial system, no illustration
Composition/framing: centered, generous margins, balanced modular grid, accent shapes kept sparse; complete square canvas with no baked rounded-corner mask
Lighting/mood: even graphic lighting, precise and contemporary, no photorealism
Color palette: Babel current Soft Shell colors — deep graphite #111314 and #252729 as base, soft paper #F3F4F4/#E9EBEB for the B, current accent orange #FF5A1F as the dominant but controlled structural signal, tiny muted gray #626667 for watermark
Materials/textures: matte flat fills with a barely perceptible print grain; no gloss
Text (verbatim): none; B is the only readable character
Constraints: original design only; B is the visual priority; watermark/grid clearly magazine-cover-like but subordinate; opaque edge-to-edge square; iOS applies its own mask; keep accent orange intentional and sparse
Avoid: other letters, readable words or headlines, logos or trademarks, Instapaper or any other brand cues, copied I shape, decorative symbols, 3D, bevel, lighting effects, device mockup, phone frame, rounded-rectangle mockup, transparency, image-generation watermark
```

核验：最终版本为不透明 RGB 1024 × 1024 方图；几何 `B` 轮廓强、橙色结构标记克制、杂志网格可辨但不抢主体，无可读副文字、圆角样机或生成水印。

## 工具与颜色来源

- 生成工具：内置 `image_gen`（logo-brand，逐版独立调用）；没有使用 CLI/API，也没有用三宫格替代三次生成。
- A 的首轮输出因透明外缘被定向重生成；最终只保留修正版。
- 主题色来源：`Design/current/HANDOFF.md` 与 `Design/current/styles.css` 的 Soft Shell token：橙色 `#FF5A1F`（深色状态 `#FF6A2F`）、石墨 `#252729` / `#111314`、纸面 `#F3F4F4` / `#E9EBEB`、线条 `#D5D7D7` / `#626667`。
- Reeder 仅用于“克制、连续、编辑感”的抽象参考；没有复制任何具体图标字形、比例或商标。

## 禁止项记录

三版均明确禁止：其他品牌元素、具体 Instapaper 视觉、其他可读字母/单词、可读杂志标题、圆角设备样机、手机框、3D、浮雕、强高光、重阴影、透明背景、iOS 圆角遮罩和图像生成水印。
