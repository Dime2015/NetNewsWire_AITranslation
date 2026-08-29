# Reeder Classic 参考素材索引

参考素材来自 `Resources/Reeder video.MP4` 的抽帧，并按 1206×2622 的 iPhone 画布保存。

## 已确认的画面

- 首页：浅色、深色
- Feeds 层级：浅色、深色、文件夹展开、Feed 问题页、订阅页
- Timeline：浅色、深色、Timeline 滚动状态
- Reader：顶部、正文、滚动状态、底部工具栏
- Settings：General、Appearance、Reading、Bionic Reading、About
- 手势设置菜单

## 当前缺失

录屏抽帧中没有找到 Reader 操作菜单展开状态。OCR 扫描了 238 张 1fps 帧，出现的 `Mark article as read` 等文字均来自 Settings 页面，不是 Reader 菜单。因此 Reader 菜单面板的尺寸、圆角和材质暂不作为可测量参考。

## 使用约定

叠图时使用同尺寸模拟器截图；状态栏时间、电量和录制状态属于外部状态，不作为页面几何差异的依据。

## Action sheet 视觉参考

`light-action-sheet-reference.jpg`（录屏帧 0219）展示了 Reeder 在 Gestures 设置中的真实 Action sheet：浅色半透明圆角面板、顶部阴影、紧凑纵向按钮列表。它不是 Reader 文章菜单本身，但可作为同一套菜单组件的几何和材质参考。
