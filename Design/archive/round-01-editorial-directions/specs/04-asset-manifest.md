# 资源清单与生成说明

## App 图标

每个方向均提供：

- `Light.svg`
- `Dark.svg`
- `Mono.svg`
- 对应 1024 × 1024 PNG

目录：

- `assets/app-icons/direction-a/`
- `assets/app-icons/direction-b/`
- `assets/app-icons/direction-c/`

图标为第一轮概念稿，进入 App Store 资产前应完成：

- 29pt、40pt、60pt 小尺寸光学修正
- iOS 实机桌面与设置页测试
- Mono 模式在系统着色下的可辨认性检查
- 字体轮廓化，避免不同系统字体造成差异

## 界面导出

`exports/png/` 包含 51 张界面稿：

- A / B / C 三方向
- 402 × 874pt 主画布
- 1206 × 2622px，@3x
- Light / Dark
- 主页、列表、文章、设置、长图、图标、压力测试

文件名格式：

`方向-页面-状态-外观@3x.png`

例如：

`C-article-translated-dark@3x.png`

`exports/long-image/` 另含 6 张完整长图：

- A / B / C 三方向
- Light / Dark
- 1206 × 3000px

## 对照资源

`source/current-app-icon/` 保存本轮分析时的现有 App 图标副本，仅作为对照。用户提供的界面与长图截图保留在 `screenshots/`。

## 生成说明

- 界面与长图均由本地 HTML/CSS 排版生成。
- App 图标源文件为 SVG，可继续编辑。
- 本轮未调用生成式位图插画；方向 B 的入口图像使用几何构图表达，避免把尚未确定的插画风格固化为品牌资产。
- 所有新生成文件均位于 `Design/` 内。
