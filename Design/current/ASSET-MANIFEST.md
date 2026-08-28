# Soft Shell Asset Manifest

## Interactive source

- `index.html`
- `styles.css`
- `app.js`

## Reference images

- `assets/references/IMG_2440.PNG`：内嵌双段切换器。
- `assets/references/IMG_2441.PNG`：底部浮动导航与当前项胶囊。
- `assets/references/IMG_2442.PNG`：大型浮动操作菜单。

## High-fidelity screens

`assets/screens/` 包含主页、文章列表、文章内容、文章操作菜单、设置主页、翻译与语言六个页面，每个页面各有 Light / Dark，共 12 张 PNG。当前导出均为去卡片化版本：普通内容使用连续画布，只有选择胶囊、底部操作区和临时菜单浮起。所有图片尺寸为 1206 × 2622px，对应 402 × 874pt、@3x。

## Source renders

`source/renders-1x/` 包含上述 12 个页面的 402 × 874px JPEG 渲染源，用于快速重新导出、生成联系表或供视觉模型读取。最终交付时应优先使用 `assets/screens/` 中的 PNG。
