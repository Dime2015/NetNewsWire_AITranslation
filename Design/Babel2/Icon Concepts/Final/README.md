# Babel 2.0 AppIcon Final

状态：用户已选定 Dark；Light 已按“亮桌面+独立深色封面+干净纸页”修订并通过静态/小尺寸 QA；Mono/Tinted 已准备；Babel2 专属 asset catalog 已建立并 actool 通过；但当前没有独立 Babel2 app target，尚未完成 runtime appearance/home-screen 验收，Phase 1 feature gate/root wiring 时接入。

修订记录：第一版 Light 因全局过暗、纸张/页边像被烧焦而被用户拒绝；第二版虽已去除焦化感，但多数封面仍为浅米白，也被拒绝；两版均未保留为最终 master。当前 Light 已再次从 Dark 用户选图重新编辑，封面正面底色改为各自独立的深色，暗色不来自全局滤镜。

生成/整理时间：2026-08-31（Asia/Tokyo）

## 母版与三态关系

- Dark：唯一母版来源是用户选定附件 `/var/folders/bk/v080cwfd4sg7s5lx5xy70s540000gn/T/codex-clipboard-e2ccaf01-da32-4b87-b267-6081246b8dd2.png`。仅做 1254×1254 → 1024×1024 的等比例方形规范化，没有重新生成或改变构图。
- Light：以上述选定图为 image edit 目标，保持相同俯拍角度、杂志数量、B 轮廓、堆叠和封面语言；桌面改为明亮自然日光的暖浅橡木，纸张/页边保持暖白、象牙白、浅米色；至少约 70% 的可见封面正面改为彼此不同的深墨蓝、森林绿、酒红、炭灰、深棕、暗青、深紫、深芥末等底色，印刷图形则用暖白、浅米、粉灰、浅蓝等亮油墨。使用内置 ImageGen 再次严格构图编辑，输出后人工检查。
- Mono/Tinted：从规范化 Dark 图做保构图的单色派生；使用中性灰度、自动对比度和五级灰阶层级，不含彩色，不是重新绘制的 B，也不是新的构图。木纹、纸张堆叠、B 空腔和接触阴影均保留。

## 文件

- `Babel2AppIcon-Light.png` — 1024×1024 RGB
- `Babel2AppIcon-Dark.png` — 1024×1024 RGB
- `Babel2AppIcon-Mono.png` — 1024×1024 8-bit grayscale
- `babel2-appicon-contact-sheet.png` — Light / Dark / Mono 在 128 / 64 / 32 px 的 QA contact sheet
- `QA/` — 三态各自的 128 / 64 / 32 px 缩略图

## 视觉核验

- 1024 px：三张均保持物理杂志组成的 B，没有独立印刷字母、玻璃对象、设备框或 baked rounded-corner mask。
- 128 px：三态均能先读到 B，再读到杂志堆叠；Light 没有因浅桌面丢失轮廓，Mono 不是一团黑。
- 64 px：B 轮廓仍连续，内腔可辨，杂志边缘与堆叠阴影仍形成实体感。
- 32 px：三态仍保留 B 的整体识别；杂志细节自然减少，这是小尺寸缩放的预期结果。

## Babel2 专属 asset catalog

已准备 `iOS/Babel2/Assets.xcassets/AppIcon.appiconset/`，Contents.json 使用项目现有的 AppIcon 约定：无 appearance 的基础图作为 Any/Light，另含 `luminosity=dark` 与 `luminosity=tinted` 两个变体。

当前 `iOS/Babel2` 只有源码目录，没有独立的 Babel 2.0 app target；因此本目录是可直接引用的资产准备，尚未声明 target wiring。未修改 `NetNewsWire.xcodeproj/project.pbxproj`、SceneDelegate、Info.plist，也未修改 `iOS/Resources/Assets.xcassets` 中的 Babel/NetNewsWire 1.x 图标。

## Light edit prompt

Precise image edit of Image 1 for the Light appearance of the Babel 2.0 iOS app icon. Image 1 is the only composition reference. Preserve the exact selected composition: same square near-orthographic top-down camera, exact uppercase B silhouette made only by the same physical magazines, same magazine count, positions, overlaps, page thickness, inner B cavity, cover sizes, and natural slight irregularities. Do not redraw, typeset, regularize, add, or remove the B or any magazine. Change the tabletop to a bright natural-daylight warm pale oak surface with subtle visible wood grain. Use individually art-directed dark-colored magazine covers, clean ivory page edges, bright oak table, no global overlay: at least 70 percent of visible front-cover area should have distinct dark cover bases, each magazine different, including deep ink navy, forest green, wine red, charcoal, dark brown, dark teal, deep plum, and muted dark mustard. Keep two or three covers medium-light as accents so it does not become a mechanical uniform black pattern. Print fish, plants, vessels, abstract forms, and small meaningless registration-like marks in warm white, pale cream, blush-gray, or muted light-blue inks on each cover. The cover background must be dark, while paper page sides, page edges, exposed sheets, and spines remain clean ivory or pale cream and clearly distinct from the dark cover fronts. Preserve soft contact shadows and physical magazine thickness. B recognition must come from the original magazine layout, visible light page edges, and natural contact shadows, never from a mask or color block. No global darkening, black overlay, smoke, soot, scorched edges, dirt, sepia wash, heavy vignette, or low exposure. No readable words, real brands, logos, portraits, device mockup, glass, glow, border, watermark, extra letters, baked rounded corners, or standalone B. Full square canvas, faithful Light colorway of Image 1, no iOS mask baked in.

工具：内置 ImageGen（Light edit）；本地图像规范化、Mono 派生、缩略图和 contact sheet 使用 macOS/Pillow 处理。未调用外部图像服务。
