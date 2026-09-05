# Babel 2.0 需求到验收映射

状态含义：`未开始` 表示尚未有实现/证据；`in-progress` 表示实现或测试正在进行；`structural done; runtime pending` 表示静态结构准备好但运行时未验收；`in-review` 表示合同/方案正在复审；`延后` 表示用户已授权按路线 A 后置，不是遗忘。

| 用户需求 | Slice / 模块 | 自动测试 | 模拟器验收 | 真机验收 | 当前状态 |
|---|---|---|---|---|---|
| 冷启动直接进入 Babel 2.0 Feeds/Library，不再出现无用 landing page | Slice 0 / Phase 1A；Babel2 feature gate/root composition | A0–A6、A9–A11：gate precedence、root count、generation/state restoration、launch trace | A12：0.5/1/2s 启动截图、冷启动、后台恢复、重复进入/退出 | A10–A12：冷热启动和 re-entry 30 次 | 实现进行中/证据待补 |
| Starred 只显示有 starred 文章的源/文件夹，计数按当前过滤语义 | Slice 2；Feeds filter/count adapters | filter query、source visibility、folder/source counts | Starred/Unread/All 原地切换、空结果 | 真实数据源、同步后计数和返回位置 | 未开始 |
| Feed/Timeline 标题、hero 和日期 header 之间不得存在独立透明/空白 spacer；expanded、compact、中间滚动状态均只保留标准 section inset，surface 持续不透明 | Slice 3；Timeline no-spacer/header geometry + hero motion | geometry/snapshot、section-inset、surface-opacity assertions | expanded/compact/中间滚动位置截图和连续滚动 | safe area、透明空带、滚动连续性人工验收 | 未开始 |
| pFilter（Starred/Unread/All）的 selection pill、内容列表和计数使用同一 progress 同步滑动/淡入出；rapid tap 可中断并反向，计数始终按当前 filter 语义 | Slice 2；pFilter motion/count state | motion progress、interrupt/reverse、filter count assertions | 快速连续点击、空结果、返回位置 | 真实数据、跟手性、计数与列表同步 | 未开始 |
| Feed hero 延伸到状态栏/动态岛，展开收缩连续 | Slice 3；hero motion/icon cache | progress clamp、hero state、icon cache contract | Light/Dark、无图/坏图、滚动截图 | safe area、opaque chrome、连续跟手收缩 | 未开始 |
| 同步箭头只在真实 syncing 出现并自动隐藏 | Slice 0/3；loading owner/sync state | sync state machine、visibility transitions | 刷新、完成、失败、取消 | 网络切换、后台/前台、无重复控件 | 未开始 |
| 文章打开快，避免中间空白加载页；必要时预加载 | Slice 4/5；Reader preparation/cache | cancellation、prepared route、cache hit/miss | 冷/热进入、短文/长文、返回 | 首屏时间、峰值内存、滚动帧率、真实源 | 未开始 |
| Reader 初始 title/byline 在正文上方，滚动后连续移入 compact header，icon 渐出 | Slice 4；Reader chrome motion | collapse progress、reverse/interruption、content height | 首屏、滚动、旋转、后台恢复 | 多 safe area/文章高度、用户跟手验收 | 未开始 |
| 翻译标题/正文不重影、不闪退、速度可接受 | Slice 5；translation session/DOM update | generation/cancellation、incremental update、error recovery | 大源、多次切换、翻译失败 | 真实翻译源、峰值内存和性能 | 未开始 |
| 横向正文图贴屏幕两端、直角；文字/caption 保持 inset | Slice 4/5；Reader HTML/media | media classification、viewport style checks | 横向/竖向/无图、caption | 真实图片、safe area、缩放和滚动 | 未开始 |
| 文章正文左滑打开内置浏览器，浏览器右滑回到 Reader | Slice 5；Browser route/motion | direction/edge arbitration、cancel/finish | WebView/Reader 手势冲突 | 跟手性、网页加载、双向返回 | 未开始 |
| 全局右滑返回稳定跟手，非边缘横向内容不误触发 | Slice 1/5；Babel2 navigation + M1 driver | edge 24–32pt、velocity、interruption | 深栈/根路由/旋转 | 目标 iPhone 真实手势矩阵 | contract layer completed；M1 local commit/final QA PASS，页面 consumer 与真机 120Hz 手感 pending |
| 底栏控件尺寸、视觉中心、颜色统一；Reader 操作重绘 | Slice 2/4/5；shared toolbar tokens | geometry/token snapshot、action routing | 各屏幕 Light/Dark/中英文 | 目标设备可达性和视觉接受 | 未开始 |
| 顶部普通分享；底栏点击生成长图，不长按分享 | Slice 5；share/long-image actions | tap-only action、share presentation、failure/retry | 分享菜单和长图状态 | 系统分享菜单、长图生成和返回 | 未开始 |
| Settings 使用新的 IA；开关尺寸合适，主题色只控制开关和进度环 | Slice 6；Settings/Theme tokens | theme mapping、switch geometry、route | 中英文、Light/Dark/Mono | 设备显示、可达性、真实主题切换 | 未开始 |
| 普通 icon/star/selection/read mode/link 不再出现旧绿色；链接加粗+中性下划线 | Slice 2–6；BabelPalette/HTML style gate | source/token scan、HTML style checks | 全屏颜色回归 | 深浅色和主题色人工检查 | 未开始 |
| 订阅源管理页、添加订阅源搜索/发现页 | Slice 6；Feeds management/search | query/debounce/cancel、empty/error | 键盘、空结果、错误、返回 | 真实源搜索和添加流程 | 未开始 |
| 中文/英文全界面 i18n，布局不因翻译跳变 | Slice 6；Babel2 strings/resources | key completeness、locale/overflow checks | 中英文切换和状态恢复 | 系统语言、动态字体、键盘 | 未开始 |
| loading/empty/error/offline/sync/translation 统一且不重复 | Slice 0–7；state surfaces | state transition/owner assertions | 每种状态、retry、恢复 | 网络和后台恢复 | 未开始 |
| Light/Dark/Mono AppIcon；Light 为亮桌面+独立暗色封面，非黑蒙版 | Slice 1/7；asset catalog/runtime appearance | asset catalog/actool/name checks | 外观资源解析 | home screen 外观和用户视觉接受 | structural done; runtime pending；静态资产已在 `9fda5c565` 提交；早期烧焦/全局蒙版 Light 已否决，当前 Final 已重生成并通过静态 QA；Dark master 为 `Design/Babel2/Icon Concepts/Final/Babel2AppIcon-Dark.png` |
| 新代码/资源/测试/文案统一 Babel；历史技术命名和死代码分批清理 | Slice 7；no-new-name、compatibility boundary、cleanup | diff-based name gate、dependency/migration checks | 用户可见零历史名、回滚场景 | 稳定后数据/状态恢复和迁移 | 当前执行 Gate A/B；技术清理延后 |

## Phase 1A 验收状态

- A0–A15 的执行矩阵和证据路径已登记在 [PHASE1A-ACCEPTANCE.md](PHASE1A-ACCEPTANCE.md)。Phase 2A correction 已完成单轨 production lifecycle、Babel2 root、external-action no-op、restoration 校验、AppDelegate-owned launch trace 和边界测试；当前仍为 **实现进行中 / 证据待补**，因为完整矩阵还需要逐项 runtime launch trace、截图、模拟器状态、最终 bundle allowlist 和目标 iPhone/视觉证据。
- Phase 1A 的 P0 根因是 generation gate 晚于 `AppDelegate` legacy lifecycle/bootstrap，而不只是 storyboard 配置问题。本批把 gate 固定在 AppDelegate 初始化边界，并让 SceneDelegate 只创建 Babel2 root；必须继续以 launch trace 证明 gate 早于所有旧副作用。
- 单轨合同已覆盖所有 build channel：`Babel2FeatureGate.decision(buildChannel:)` 总是返回 Babel2，launch arguments 和 persisted generation 不再是 production selector；A8/A14 旧的“切 legacy”语义已改为“保持 Babel2、解析后安全 no-op、零 legacy side effect”。`-GenesisV2` 只可作为 audit-only historical reference 的静态回归字面量，不得成为新内部命名。
- 新代码、资源、测试、文案和叶子文件名统一 Babel/Babel2 与 `legacy`；旧字面量只允许出现在精确兼容边界或 Gate A 登记的 build/test harness allowlist，persisted/system identity 只能经过唯一 `LegacyIdentityCompatibility` 边界。该 compatibility boundary 是 PRODUCT-CONTRACT/A15/Phase6 requirement，当前未实现，不创建空 facade。

## 当前合同状态

- 产品/运动合同 amendment 已在 `1269bb9087d896a7a9e29f174461d60b47134575` 完成规范版本 QA、提交并获授权非 force 推送，状态为 `completed/committed`；产品页面实现仍未完成，Phase 2A 只处理启动单轨根因。
- M1 motion 实现和测试已在本地 `5db240499806bc4cae9be0b82194c838a32229de` 提交；第 5 轮独立 QA PASS（30 项 package、8 项真实 iOS UIKit runtime、8 项 Boundary/Shell、Debug build，iPhone 17 / iOS 27 Simulator）。2026-09-05 已获授权推送并经 `git fetch` 核实远端已含此提交，真机 120Hz 手感和 OSLogStore consumer integration 仍未验收。
- AppIcon 设计/静态资源、逐图检查、独立 QA 和 actool 已绑定 `9fda5c565`，状态为 `structural done; runtime pending`；runtime appearance、模拟器解析和 Home Screen 仍未验收，不声称用户逐像素口头确认最终 Light。

## Phase 2A 当前实现证据

- `Babel2FeatureGateTests`、`Babel2BoundaryTests` 已覆盖单轨 gate、旧启动参数/持久化 selector 禁止、scene configuration、restoration、external parser、root re-entry、production lifecycle 静态边界、legacy event-derived counters/invalidity、session/order/uptime/JSON 和 test-fixture isolation；clean fixture 的 counters 为零，但这不是硬编码零或 production runtime 证据。
- `Babel2FeatureGateTests.testSceneConfigurationCannotInstantiateTheLegacyStoryboard` 在 test host 中不假设 `UISceneConfiguration.name` 必须非空；以 `Babel2SceneConfiguration.isBabel2`、`delegateClass === SceneDelegate.self` 和 `storyboard == nil` 验证 API 实际身份。
- 当前 fresh correction Debug iOS tests：XCTest 27 + Swift Testing 18 = 45 项，全部通过；package 30 项通过，Debug/Release build 均通过。详细命令、exit code、result bundle、bundle boundary 和限制见 [VALIDATION.md](VALIDATION.md)。
- 仍未关闭：A0/A1/A6/A8/A12/A13 runtime/manifest/截图证据、A0–A15 完整真机矩阵、0.5/1/2 秒启动截图、真实外部回调/scene 恢复、最终 bundle allowlist、目标 iPhone/性能/视觉验收，以及后续页面 Slice。当前 bundle 仍含 Main.storyboardc、HTML-JS、8 themes 和 3 extensions。
