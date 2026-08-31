# Babel 2.0 产品与迁移合同

状态：范围与验收合同草案（2026-08-31）  
适用平台：iOS 前端迁移；macOS、同步服务和内容管线不因本合同自动重写。  
产品名：**Babel 2.0**

本文件把 Babel 2.0 的产品范围、设计证据、迁移顺序和验收边界固定下来。它不是“已经完成”的声明。凡是没有运行证据、真机证据或用户视觉验收的项目，必须继续标为未验收。

## 1. 产品边界与版本谱系

### 1.1 Babel 2.0 的定义

Babel 2.0 是在现有 NetNewsWire/Babel 数据与服务能力上重建 iOS 前端体验的产品版本。目标是让 Feeds、Library、阅读器、订阅管理和设置在同一套导航、状态、几何和交互合同下工作，并达到 Reeder Classic 的克制、连续和跟手感。

Babel 2.0 的工作范围包括：

- 新的 iOS 根壳、Feeds 首页、Library/Starred/Unread/All、源和文件夹层级；
- Timeline/feed hero、列表、列表内搜索、翻译状态和加载/空/错误状态；
- Reader 原文、翻译、阅读模式、内置浏览器、分享、长图和滚动收缩标题；
- 订阅源管理、添加订阅源及发现入口；
- Settings 新信息架构、编辑器、语言、外观、翻译模型和服务状态；
- 既有 Core Data、账户、同步、翻译、图标缓存和阅读内容管线的复用与隔离；
- 在真实 iPhone 上对几何、滚动、翻页、点击反馈、过渡和状态恢复的验收。

不自动包含：

- 重新设计或迁移 macOS UI；
- 更换 Core Data 数据模型、账户协议或翻译供应商，除非某个 Slice 的依赖审计证明确有必要；
- 从静态 Figma 画面臆造未被合同锁定的动画；
- 把 Genesis 的“有代码”当作 Babel 2.0 的“已验收”；
- 仅凭模拟器截图、单元测试或 Figma 预览宣称真机手感完成。

### 1.2 版本谱系

远端只读核对结果（2026-08-31）：

| 版本 | 产品定位 | tag peeled SHA | 远端核对 |
|---|---|---|---|
| v0.5 | Genesis v1 stable baseline | `649f85fd50e5fff21e75818193011250baf08d50` | `origin` 一致 |
| v1.0 | Genesis v2 stable baseline | `d1679c7f253d37eda557970fca0827c096132a05` | `origin` 一致 |
| v1.1 | pre-Babel 2.0 UIKit redesign baseline | `a94c00626edf13bb3e869c35924bfd6ece7e6165` | `origin/codex/reeder-classic-rebuild` 与 tag 一致 |

祖先关系只读验证通过：`v0.5 → v1.0 → v1.1 → origin/codex/reeder-classic-rebuild`。

当前工作树位于分支 `codex/reeder-classic-rebuild`，且存在大量未提交修改和未跟踪设计/比较产物。因此下表描述的是“当前源码和工作树证据”，不是一个干净、已发布的 v1.1 构建。

### 1.3 与旧 UI 的边界

- Genesis v1（v0.5）和 Genesis v2（v1.0）是历史运行基线，用于保留数据、服务和回退能力，不是 Babel 2.0 的视觉合同。
- v1.1 是进入 Babel 2.0 前的 UIKit 基线；它证明了当前迁移起点，不证明新 UI 的完整性。
- 旧 Genesis 路由可以在迁移期间作为回退或功能参考，但必须由明确的 feature gate 隔离，不能与 Babel 2.0 的导航栈、颜色、布局常数、图标解析器或状态机隐式混用。
- Babel 2.0 前端可以复用旧的数据和业务管线；“复用服务”不等于“复用旧视觉组件”。
- 迁移期间 Release 仍可保留 Genesis fallback，但在每个 Slice 的验收记录中必须写清用户进入的是哪一套 UI。

## 2. 设计来源与证据优先级

当来源互相矛盾时，按以下优先级处理：

1. 用户在真实 iPhone 上对目标行为和手感的明确验收；
2. Reeder Classic 的锁定截图、视频、测量台账和本地参考；
3. Figma Interaction Contract 中明确写出的状态转换、几何和运动检查点；
4. Figma Batch/Settings 规格中的屏幕清单和信息架构；
5. 当前 Babel 代码：只作为数据流、服务依赖和可行性证据；
6. Soft Shell：仅作为历史参考，不得当作 Babel 2.0 当前视觉来源。

### 2.1 当前参考的本地路径和节点

| 证据 | 路径或节点 | 用途与限制 |
|---|---|---|
| 设计入口 | `/Users/wenbopan/Downloads/AI Projects/Babel app/Design/README.md` | 说明 `Design/current/` 与归档边界 |
| Reeder 测量台账 | `/Users/wenbopan/Downloads/AI Projects/Babel app/Design/reeder-classic/REFERENCE_LEDGER.md` | 1206×2622、约 3 px/pt、Home/Feeds/Timeline/Reader 几何；未锁定的项不能补猜 |
| Reeder Home 边界 | `/Users/wenbopan/Downloads/AI Projects/Babel app/Design/reeder-classic/home-ui-ledger.md` | Home 静态几何；不包含动画、滚动和转场 |
| Reeder 采集计划 | `/Users/wenbopan/Downloads/AI Projects/Babel app/Design/reeder-classic/REFERENCE-CAPTURE-PLAN.md` | 60fps 视频及已覆盖场景；静态图片不能替代运动证据 |
| Reeder 原始参考 | `/Users/wenbopan/Downloads/AI Projects/Babel app/Design/reeder-classic/references/` | 截图、视频抽帧和接触表；Reader 菜单完整状态并未稳定锁定 |
| 当前交互合同 | `/Users/wenbopan/Downloads/AI Projects/Babel app/Figma Drafts/INTERACTION-CONTRACT.md` | Babel 2.0 的状态、路由保持、滚动、过滤、翻译和运动合同 |
| Figma 文件 | `https://www.figma.com/design/0kFsVs9DLbE7Um96yrlBKg` | 文件 key `0kFsVs9DLbE7Um96yrlBKg` |
| Figma 状态索引 | `/Users/wenbopan/Downloads/AI Projects/Babel app/Figma Drafts/figma-state.json` | 当前节点、状态和已知限制的机器可读索引 |
| Batch 01 | `/Users/wenbopan/Downloads/AI Projects/Babel app/Figma Drafts/BATCH-01-SPEC.md` | Home/Library/Feed/Reader 基础视觉和设备规格 |
| Settings IA | `/Users/wenbopan/Downloads/AI Projects/Babel app/Figma Drafts/SETTINGS-IA-SPEC.md` | Settings 类别、编辑器与保存规则 |
| Soft Shell（历史） | `/Users/wenbopan/Downloads/AI Projects/Babel app/Design/current/` | 仅保留历史决策和对照；不能压过 Reeder/Figma 当前合同 |

### 2.2 静态图与运动的边界

Reeder 截图和 Figma 静态状态可以锁定位置、尺寸、颜色、层级、文本和状态关系；它们不能单独证明“翻页、滑动、点击之后流畅、跟手”。

运动必须至少同时满足：

- Figma Interaction Contract 的状态序列、阈值、方向、时长和几何连续性；
- Reeder 视频/真实设备对照中可观察的运动节奏；
- iPhone 实机上手指跟随、回弹、转场中断与返回后的状态保留；
- 用户最终视觉与手感验收。

任何仅有一张图、一次静态截图或设计预览的条目，最多标为“静态结构通过”，不能标为“运动完成”。

## 3. 屏幕与能力矩阵

状态含义：

- **未迁移**：仅 Genesis 或旧路由有能力，Babel 2.0 没有可验证实现；
- **半实现**：工作树有新 UI 或部分行为，但存在合同缺口，或没有真机/用户验收；
- **有代码未验收**：主要路径已存在，仍不能称完成；
- **结构通过**：静态/结构检查已能对上，但运动或真机边界仍未关闭；
- **完成**：只有在合同条目、自动化检查、实机检查和用户验收全部有记录后使用。

| 区域 / 能力 | 当前证据与状态 | 用户可观察验收标准 | 数据与服务依赖 |
|---|---|---|---|
| Babel 2.0 根壳 | `/Users/wenbopan/Downloads/AI Projects/Babel app/iOS/BabelUI/BabelShellViewController.swift` 已将根入口接到 Feeds；Release/Debug feature gate 仍存在；**半实现** | 冷启动进入 Babel 2.0 Feeds；导航栈、状态栏和底部栏稳定；离开再返回不重复壳、不跳 Genesis；旧 UI 只能通过明确回退入口出现 | SceneDelegate、`BabelShellConfiguration`、UIKit 导航 |
| Feeds 首页 | `BabelFeedsViewController.swift` 有 unread/folder/feed rows、计数、展开；**有代码未验收** | 首屏显示 Feeds、Starred、Unread、All 及源/文件夹；选中态、计数、缩进、分隔和点击反馈与 Reeder/Figma 一致；文件夹展开原地发生并保持上下文 | Core Data feeds/folders/articles、SmartFeeds、图标缓存 |
| Starred / Unread / All | Feeds 过滤状态已部分存在；Figma Library `22:36`、Unread `22:7`、Starred `29:8`、All `29:23`；**半实现** | 点击过滤器只在固定槽位原地 `CHANGE_TO`；列表回到顶部但路由和其他上下文保留；没有 push/card/sheet；数量与实际结果一致 | `NNWStarredIndex`、文章 read/star 状态、SmartFeeds 查询 |
| 源 / 文件夹计数 | 新 Feeds 代码有 counts；**有代码未验收** | 文件夹计数等于可见子项语义；源计数等于对应过滤下文章数；0、同步中和错误时不显示过期的“成功数字” | Feed/folder 关系、文章状态、同步刷新 |
| Feed 列表 / Timeline | `BabelTimelineViewController.swift` 有分组文章列表、底部栏、行内标题翻译；**半实现** | 日分组、标题、来源、时间、摘要、已读/未读重量、缩略图和底部操作与锁定参考一致；点击文章进入 Reader，返回保留位置 | 文章抓取、正文/摘要、日期、本地化、缩略图 |
| Feed hero | 代码有 hero 与滚动插值；Figma Feed expanded `22:37`、transition `244:541`、compact `244:552`、no image `244:563`；**有代码未验收** | hero 从 y=59 开始；展开 `[0,59,402,169]`、收缩 `[0,59,402,99]`、toolbar `[0,802,402,72]`；标题与图像连续插值，无卡片阴影跳变；无图时有稳定 fallback | `TimelineFeedHeader`、`FeedHeroIconLoader → FeedIconDownloader → FaviconDownloader`、dominant color/cache |
| Feed 搜索 | `BabelArticleSearchViewController.swift` 有当前源文章搜索覆盖层；**半实现** | 搜索留在当前源上下文；键盘、取消、空结果、错误和返回不丢失原滚动位置；搜索结果仍遵守文章行合同 | 本地文章索引/过滤、iOS 搜索输入 |
| Feed More / 反馈 | Feeds/Timeline 有 More/Feed Issues sheet；**有代码未验收** | 菜单/反馈出现和消失不破坏当前 route、filter、scroll；命令作用后有可观察结果或明确错误；菜单材料和返回时序需实机确认 | UIKit sheet/action、订阅源状态、日志 |
| Reader 原文 | `BabelReaderViewController.swift` 有 WKWebView、header、底部 toolbar；Figma Reader Original `22:38`；**有代码未验收** | 标题、日期、byline、正文和底部 read/star/next/translation/BR 槽位稳定；进入、返回、下一篇不跳位；短文和长文均不裁切 | WKWebView、文章 HTML/正文、`ReaderViewExtractor`、文章状态 |
| Reader 长文滚动 / 收缩标题 | 代码有 compact header/progress；Figma `180:370`、`180:424`、`143:444`、`180:520`、`227:675`；**半实现** | status bar opaque；只有文章真正滚动才收缩；progress 使用 `p=clamp((offsetY-collapseStart)/(maxScrollableOffset-collapseStart),0,1)`；42pt 真图标位于 48pt frame；返回/旋转/加载后位置保留 | WKWebView scroll、实际内容高度、安全区、Feed icon |
| Reader pin/unpin | 代码有 Reader controls，但完整 directional contract 未有 UI 测试；**半实现** | 12pt 方向性移动后，顶部/底部控制一起显隐；180ms linear；可中断、反向跟手；不重置 route、文章或滚动位置 | UIScrollView/WKWebView、UIViewPropertyAnimator 或等价状态机 |
| Reader 翻译 | Reader 有翻译控制；Figma Original `22:38`、Translating `117:263`、Translated `117:317`；**半实现** | `Original → Translating → Translation` 原地发生；Reader skeleton 与正文几何稳定，约 3 秒段落级渐进且不跳位；取消/失败可回到原文；不擅自增加 AI 目标语言设置 | `TranslationConfig`、翻译模型/API/key、流式绑定、文章段落解析 |
| Feed 列表翻译 | Timeline 有标题翻译；**半实现** | 列表标题在原位置替换，不改变行高度策略；翻译中有明确但不扰乱滚动的状态；失败显示可重试结果 | 翻译 API、标题缓存、文章列表数据 |
| 阅读模式 | `ReaderViewExtractor` 路径存在，Reader 有入口；**有代码未验收** | 阅读模式从当前文章进入，内容可读、图片/链接规则明确；返回保留位置；无正文时显示错误而不是空白 | HTML 提取、WebView、主题设置 |
| 内置浏览器 | `/Users/wenbopan/Downloads/AI Projects/Babel app/iOS/BabelUI/BabelBrowserViewController.swift`；**有代码未验收** | 原文链接在内置 WKWebView 打开；后退/前进/刷新/分享/外部打开可用；返回 Reader 不丢状态；加载失败可重试 | WKWebView、网络、安全策略、系统分享 |
| 系统分享 | Reader 与 Browser 有 `UIActivityViewController`；**有代码未验收** | More/Browser 分享使用系统分享面板；分享对象、标题和 URL 正确；取消后回到原文章/原滚动位置 | URL、文章 metadata、系统分享服务 |
| 长图 | `ArticleLongImageExporter` 有调用路径；**半实现** | 由 Reader 操作明确触发；生成完整文章长图或给出可理解失败；导出过程中不阻塞错误地覆盖 Reader；保存/分享结果可观察；不能把普通点击误当长按 | HTML/WebView snapshot、图片拼接、照片/分享权限 |
| Reader Actions | Reader 已有 UIAlertController actions；**半实现** | Reader action 顺序为 Reader mode/Translate/Long image/Star/More；More 含 Mark read/Next unread/System share；菜单返回时保持 route/位置；与 Figma/实机材料一致 | 文章状态、翻译、导出、系统分享 |
| 添加订阅源 | `BabelSubscriptionViewControllers.swift` 可输入 URL 并解析 RSS/Atom/JSON alternate link；**半实现** | 添加页有取消/保存或明确完成路径；合法源可添加、重复源可解释、无效源有错误；进度/失败/重试可观察；不声称已有关键词发现 | `URLSession`、RSS/Atom/JSON parser、Account/Feed API、Core Data |
| 添加订阅源搜索/发现 | 当前实现是网站/feed URL 抓取，不是 Feedly/Podcast/YouTube/Reddit 关键词搜索；**未迁移** | 输入关键词后能按合同的来源类别搜索；结果可预览并订阅；服务不可用、空结果、限流和错误有明确状态；若后端未提供，必须显示未支持而不是伪造结果 | Discovery API、第三方服务 key、网络、订阅写入 |
| 订阅源管理 | 有 rename/remove 管理页；**有代码未验收** | 源和文件夹能查看、改名、删除、排序/层级关系可解释；删除有确认并立即更新 Feeds；同步失败不丢本地状态 | Account、Feed/folder persistence、sync |
| Settings 根 | `BabelSettingsViewController.swift` 已有 8 类别；Figma `110:300`；**半实现** | 8 类别入口可到达：Accounts & Sync、Subscriptions & Discovery、Timeline、Reader、Translation、Appearance & Language、Notifications、Support & Diagnostics；关闭/返回不丢状态 | AppDefaults、Account、TranslationConfig、系统设置 |
| Settings 二级页 | Figma `110:320`–`110:460` 及 `110:480`–`110:600`；现有编辑器部分复用旧控制器；**半实现** | 普通详情 push；可逆选择使用 anchored popover；布尔项即时生效；有延迟保存的编辑器有 Cancel/Save；不混用旧 action sheet 与新合同 | Settings 控制器、AppDefaults、账户、主题、翻译配置 |
| Settings 动态 Translation Model | Figma `110:560`，catalog 规则为动态 Top 10 + 每供应商恰好 3 个；当前规格与旧代码 15/5/底部 refresh 有冲突；**未验收** | 专用编辑器顶部刷新；固定 logo/check 槽；加载、空、错误和选择状态稳定；供应商分组数量符合最新合同，若未实现必须标缺口 | 供应商目录 API、模型配置、缓存、网络 |
| i18n / 目标语言 | `AppLanguageController`、TranslationConfig 和本地化资源存在；**有代码未验收** | 界面语言切换可观察且不破坏布局；全局目标语言影响列表/Reader 翻译；原文、翻译中、失败和未配置均可本地化；不把“语言选项存在”当作翻译完成 | Localizable strings、AppLanguageController、TranslationConfig、服务返回语言 |
| 浅色/深色 | 设计 token 和部分代码存在；Figma full dark masters 标为后续 Batch；**半实现** | 浅色/深色均无反白、透明状态栏、图标不可见或文本对比不足；切换后当前 route/scroll/selection 保留；色值遵循 Reeder/Figma 语义变量 | `NNWAccentPalette`、BabelDesignSystem、traitCollection |
| 图标缓存 | 当前链 `FeedHeroIconLoader → FeedIconDownloader → FaviconDownloader` 和 fallback/dominant color 存在；**有代码未验收** | 同一 feed 不重复解析/下载；缓存命中不闪烁；坏图标、有图标、无图标和网络失败均有稳定 fallback；Feed hero 与行图标不建立第二套 resolver | URL cache/disk cache、favicon 下载、图片裁切/主色分析 |
| 同步状态 | 根壳有 sync glyph/Feed Issues 入口，Genesis 有账户同步能力；**半实现** | 初始同步、同步中、成功、失败和离线均有可观察状态；数字、列表和 star/read 操作不会显示已失效成功值；失败可重试并保留本地内容 | Account、iCloud/local sync、Network、Core Data、活动日志 |
| Loading / Empty / Error | Figma 有 Empty State `25:8`、Confused Bear `241:41`；完整 loading/error/empty master 未齐；**未验收** | 每个屏幕定义首次加载、刷新、无内容、无搜索结果、网络错误、解析错误和翻译错误；状态不造成布局跳变；错误有恢复动作；不以永恒 spinner 代替错误 | 网络、解析、同步、翻译、状态模型 |
| 自动化门禁 | 现有测试覆盖 shell flag、pop policy、original-link swipe；没有完整 UI/snapshot/motion/device tests；**未验收** | 每个 Slice 有结构/单元检查、关键 UI 测试和实机检查记录；测试失败阻止“完成”标签；性能/运动由设备而非单元测试单独验收 | XCTest、截图/比较工具、真机、测试数据 |

## 4. 屏幕注册表与节点合同

以下是 Figma 状态文件中当前可定位的主屏幕和状态。节点编号用于回查，不代表已经有生产实现。

| 屏幕/状态 | Figma 节点 |
|---|---|
| Home | `86:204` |
| Library | `22:36` |
| Feed expanded / transition / compact / no-image | `22:37` / `244:541` / `244:552` / `244:563` |
| Reader Original / Translating / Translated | `22:38` / `117:263` / `117:317` |
| Reader short no-sticky / long transition / pinned down / pinned up / pinned down again | `180:370` / `180:424` / `143:444` / `180:520` / `227:675` |
| Settings Home | `110:300` |
| Accounts / Subscriptions / Timeline / Reader | `110:320` / `110:340` / `110:360` / `110:380` |
| Translation / Appearance & Language / Notifications / Support | `110:400` / `110:420` / `110:440` / `110:460` |
| Account Detail / Add Account / Discovery API Keys | `110:480` / `110:500` / `110:520` |
| Article Theme / Translation Model / Translation API / Color Palette | `110:540` / `110:560` / `110:580` / `110:600` |
| Timeline Sort / Group popover | `223:590` / `224:632` |
| Reader Open Links / Appearance Mode / Accent / Interface Language popover | `224:1369` / `224:1482` / `224:1538` / `224:1609` |

关键组件节点包括：Status Bar `16:2`、Home Mark `82:18`、Home Account Card `83:18`、Folder Row `19:12`、Feed Row `19:23`、Article Row `20:32`、Translation Toggle `43:19`、Reading Mode `92:22`、Reader Toolbar `21:5`、Filter Pill `28:44`、Feed Toolbar `22:35`、Compact Header `143:73`、Empty State `25:8`。

### 4.1 固定几何与交互约束

- 设计画布为 402×874；Reeder 锁定参考为 1206×2622，约 3 px/pt。
- 顶部控制中心约 y=81，槽位 x=`[32, 201, 290, 330, 370]`；未使用槽位必须保持空，不得自行塞入新按钮。
- 底部 toolbar 为 `[0,802,402,72]`，中心 y=826，槽位约 `[32,104,201,290.5,362]`；可点击命中区域 44pt。
- Feed status bar 不透明，hero 从 y=59 开始；标题可读性用无边界 feather，不用卡片阴影制造分界。
- Reader status bar 使用不透明 `BabelPalette.background`，不使用 underlap、glass 或 blur 伪造稳定性。
- Reader progress 是从 12 点钟方向开始的一条连续顺时针 arc；不能按离散页面硬切。
- Feed filter、folder expansion、搜索均优先使用原地 `CHANGE_TO`；不得因复用方便而推成 push/card/sheet。
- 短选项使用 anchored popover；Settings 的延迟保存编辑器使用 Cancel/Save；开关即时生效。

## 5. 数据与服务依赖合同

| 能力层 | 应复用/依赖的现有能力 | Babel 2.0 约束 |
|---|---|---|
| 本地模型 | Core Data 的账户、feed、folder、article、read/star 状态 | 先稳定查询语义，再换显示层；过滤数字必须来自同一语义源 |
| Smart Feeds | SmartFeeds unread/starred/all 查询与 `NNWStarredIndex` | 新 UI 不复制一套状态索引；必要时提供只读适配层 |
| 抓取与解析 | Account/ArticleFetcher、RSS/Atom/JSON parser、正文与摘要 | 错误、超时、空正文必须向 UI 提供可区分状态 |
| 同步 | iCloud/local account、同步活动与日志 | 同步中不覆盖本地有效内容；UI 不能把旧计数当成功状态 |
| 翻译 | `Shared/Translation/TranslationConfig.swift`、模型/API key、流式翻译路径 | 原文/翻译中/译文/取消/失败是明确状态；UI 不隐藏服务限制 |
| 图标 | `FeedHeroIconLoader`、`FeedIconDownloader`、`FaviconDownloader`、缓存与主色分析 | 只保留一条 resolver/cache pipeline；行与 hero 共用缓存合同 |
| Reader | WKWebView、`ReaderViewExtractor`、HTML override、文章高度测量 | 真实内容高度决定 progress；不能用固定示例高度冒充长文验证 |
| 导出与分享 | `ArticleLongImageExporter`、`UIActivityViewController` | 导出失败有恢复路径；分享取消后不丢 route/位置 |
| 浏览器 | BabelBrowser WKWebView、系统外部打开 | Reader 与 Browser 返回边界必须明确；导航历史不泄漏到 Reader |
| 发现/订阅 | URLSession、源链接发现、Account 写入、订阅管理 | 当前 URL 解析能力不等同于关键词发现；第三方 API/key 缺失必须显式显示 |
| 设置 | AppDefaults、主题、语言、通知、诊断/日志 | 旧控制器可作为业务适配，但 UI 交互必须服从新 popover/editor 合同 |

## 6. 垂直切片迁移顺序（Slice 0–7）

每个 Slice 都必须是可独立验收的垂直闭环：屏幕、数据、状态、失败路径、自动检查和真机步骤一起迁移。未通过的 Slice 不得把依赖能力宣称为 Babel 2.0 完成。

### Slice 0 — 合同、测量和隔离基线

- 固定产品命名、Genesis 边界、Reeder/Figma 证据优先级、402×874 与真实 iPhone 验收边界。
- 记录当前 dirty worktree、现有 route、数据/服务依赖和回退入口。
- 建立 feature gate、单一导航壳、状态矩阵和可重复测试数据；不新增第二套图标解析或翻译状态机。
- 验收：能明确判定某条路径属于 Genesis 还是 Babel 2.0，并可在设备上重复进入/退出。

### Slice 1 — 根壳、tokens、导航和全局状态

- 迁移状态栏、顶部/底部栏、Light/Dark、字体、命中区域、导航返回和可中断转场。
- 先实现 loading/empty/error 基础容器，不让每个屏幕自造一套。
- 验收：冷启动、深浅色切换、后台回前台、push/pop 和边缘滑回均不产生跳壳或旧 UI 串入。

### Slice 2 — Feeds 首页、Library 和过滤

- Home/Feeds、Library、Starred/Unread/All、文件夹展开、源/文件夹计数。
- 统一 SmartFeeds/文章状态查询；固定槽位、原地 `CHANGE_TO`、首屏/空态/错误态。
- 验收：同一数据集下四种过滤数字和文章集合一致，切换无 push/card/sheet，返回保留 route/context。

### Slice 3 — Feed Timeline、hero、搜索和列表翻译

- Feed hero 与既有 icon pipeline；展开到 compact 的连续滚动；文章行、日分组、摘要、缩略图。
- 当前源搜索、Feed More、列表标题翻译及失败/取消。
- 验收：真实 feed 图标、无图标、坏图标、无网络均有稳定结果；滚动跟手，标题/图像不跳；搜索/翻译不破坏位置。

### Slice 4 — Reader 原文、滚动收缩和进度

- Reader header、WebView 内容、底部 toolbar、短文/长文、compact header、连续 progress、pin/unpin。
- 先锁定原文稳定几何，再接高阶操作。
- 验收：多种真实文章高度、不同 safe area、Light/Dark、进出后台和返回均保留位置；progress 只随真实可滚动内容变化。

### Slice 5 — Reader actions、翻译、阅读模式、浏览器、分享、长图

- Reader action menu、原地翻译流、阅读模式、内置浏览器、系统分享、长图导出、下一篇/标记已读。
- 明确取消、失败、网络断开和导出权限路径；不把暂时 UIAlertController 作为最终交互合同。
- 验收：动作顺序、菜单返回、三秒段落级翻译过渡、导出/分享结果和 Reader 位置均在实机可观察且可中断。

### Slice 6 — 订阅管理、发现、Settings 和 i18n

- 添加订阅源、关键词发现（若服务实际存在）、管理源/文件夹、Settings 8 类别及二级编辑器/popover。
- 接入全局语言、目标语言、主题、通知、诊断、翻译模型目录和 API key 状态。
- 验收：每个编辑器有正确的保存/取消语义；服务缺失时显示真实限制；语言切换不破坏当前 route/layout。

### Slice 7 — 全面状态、可靠性、真机验收和清理

- 补齐 loading/empty/error/offline/sync/translation/discovery 全状态；跑自动化、性能和对照截图；在目标 iPhone 完成运动验收。
- 根据验收结果删除重复 UI、旧视觉常数和未使用回退，不提前清理数据/服务。
- 验收：所有矩阵行有证据链接和负责人；用户接受关键屏幕的几何与手感；未完成项仍留在缺口清单。

## 7. 保留、隔离与最终删除清单

### 7.1 应保留

- Core Data 模型、账户、同步、SmartFeeds、文章抓取/解析、翻译配置与服务适配；
- `ReaderViewExtractor`、WKWebView 内容管线、长图导出、系统分享等已证明有业务价值的能力；
- `FeedHeroIconLoader → FeedIconDownloader → FaviconDownloader` 单一图标下载/缓存链；
- 日志、诊断、网络错误和可复现测试数据；
- Reeder/Figma 本地合同、节点索引和验收记录。

保留不等于原样暴露给新 UI。业务层需要稳定的窄适配接口，避免新屏幕直接依赖旧控制器内部状态。

### 7.2 应隔离

- Genesis v1/v2 的根壳、Home、Reader、Settings 路由和旧视觉常数；
- `BabelShellConfiguration` 的 Debug/Release/环境开关；迁移期间允许回退，验收时必须能识别当前 UI 世代；
- 当前 BabelUI UIKit 屏幕：`BabelFeedsViewController`、`BabelTimelineViewController`、`BabelReaderViewController`、`BabelBrowserViewController`、`BabelSettingsViewController`、订阅相关控制器；它们是迁移候选实现，不是自动获得合同豁免；
- 旧 `UIAlertController` action sheet、重复过滤逻辑、重复图标 resolver、重复翻译状态机和临时 debug route；
- 第三方 discovery/key 缺失时的实验性入口，不能伪装成产品能力。

### 7.3 最终可删除，但只能在 Slice 7 之后

- 已被 Babel 2.0 通过实机验收完全替代的 Genesis UI 路由和资源；
- 已被单一 pipeline 替代的旧图标解析器、重复状态索引和视觉常数；
- 仅用于迁移探针且无 Release 依赖的 debug 入口、临时 mock 数据和一次性截图比较产物；
- 已明确迁移且有回滚/版本记录的旧设置 UI。

本合同生效时不执行上述删除。任何删除都必须先有依赖搜索、回退方案、Slice 7 验收记录和用户批准。

## 8. 不能假装完成的项目

下列事项在当前证据下不能标记为“完成”：

1. 仅凭 Figma 静态图证明翻页、滑动、点击动画跟手；
2. 仅凭模拟器截图证明 iPhone safe area、滚动阈值、进度弧、回弹和真实触摸延迟；
3. 仅凭 `BabelReaderViewController` 有 toolbar 就证明 Reader 全部动作、长图、分享和阅读模式完成；
4. 仅凭已有 URL 解析就证明“添加订阅源搜索”已经支持关键词、Feedly、Podcast、YouTube 或 Reddit；
5. 仅凭 Settings 类别存在就证明 popover、保存/取消、动态模型目录和服务错误完成；
6. 仅凭本地化资源或语言选项存在就证明翻译流、目标语言和 i18n 布局完成；
7. 仅凭图标缓存类名存在就证明真实 favicon、坏图标、缓存命中和 hero 复用通过；
8. 仅凭 spinner、空数组或一个错误 alert 就证明 loading/empty/error 全状态完成；
9. 仅凭现有 XCTest（shell flag、pop policy、original-link swipe）证明 UI、截图、运动或设备验收完成；
10. 当前 dirty worktree 上未经重新构建、安装和设备验证的任何历史测试数字；
11. 临时几何 B、Inter fallback、neutral thumbnail、compact T mark 等设计占位物已经是最终品牌或最终素材；
12. 把 Settings IA 文档中“7 个二级编辑器”和 Figma 状态文件的完整节点列表视为无冲突事实；精确屏幕注册以 `figma-state.json` 和用户当前决策为准，差异必须单独解决。

## 9. 当前证据缺口与待补证据

- Reeder 中同一文章、相同滚动位置的完整像素/运动对照尚未锁定；Reader 菜单动画和返回时序在本地参考中不稳定。
- Figma 设计批次明确存在 API 循环预览、SF Pro 渲染 fallback、Feed thumbnail 占位和完整 dark masters 待补等限制。
- 真实 feed favicon、连续 progress 在真实文章高度上的行为、safe area、阈值/迟滞/时长尚未完成 iPhone 实机验收。
- Reader 翻译的生产 Swift/SwiftUI 流式绑定和段落 skeleton 过渡尚未由设计文件证明已接通。
- Feed filter/folder 原地状态、Feed hero 既有 pipeline 的代码同步需要逐 Slice 核对；不能只看节点或静态 preview。
- 添加订阅源的关键词发现后端、供应商范围、认证和配额尚未由当前源码证明。
- Loading/empty/error 的完整主视觉和每种服务错误的恢复动作尚未齐全。
- 当前工作树未清洁，且本合同创建前的修改涉及多处 Swift、工程、测试和未跟踪设计产物；本文件不把它们重新解释成稳定发布物。

## 10. 真机验收边界

### 10.1 必须在设备上检查

- 目标参考设备为 iPhone 17 级别、402×874 逻辑画布；Light/Dark 各一轮；
- 冷启动、后台回前台、网络正常、离线、慢网、同步中、同步失败；
- Feeds filter/folder expansion、Timeline hero 连续收缩、Reader 长文滚动、progress arc、pin/unpin、翻译渐进、返回和边缘滑回；
- 系统字体、safe area、键盘、状态栏、真实 favicon、真实文章图片/正文高度；
- 点击、拖动、快速反向拖动、转场中断、重复点击和快速返回后的状态恢复；
- 内置浏览器、系统分享、长图导出、权限拒绝和错误重试。

### 10.2 不能替代真机验收的证据

- Figma prototype、静态 PNG、单个录屏帧、模拟器 screenshot；
- 单元测试、编译成功、代码路径存在、节点名称匹配；
- 旧 Genesis 版本曾经通过的测试；
- 仅看“不卡顿”的主观描述而没有实际手指操作和对照记录。

### 10.3 完成标签的最低门槛

一个能力只有在以下四类证据都存在时才能标记为“完成”：

1. 代码和数据依赖在当前目标构建中可到达；
2. 正常、加载、空、错误、取消/返回等用户可观察状态有验收记录；
3. 关键几何和交互在目标 iPhone 上与 Reeder/Figma 合同对照通过；
4. 对应的自动化/回归检查已通过，且记录的是当前构建而非旧工作树。

若只有前两项，标“有代码未验收”；有静态对照但没有运动，标“结构通过”；任何缺少真实服务、设备或用户视觉结论的项目必须保留在缺口清单。

## 11. 迁移交接规则

- 每次只推进一个垂直 Slice；先更新范围/依赖/验收证据，再让实现代理工作。
- 同一个共享文件、状态机、图标 pipeline 或导航壳不得由多个代理并行重写；先指定唯一 owner。
- 实现代理不得从 Soft Shell 重新推导当前视觉；必须引用本合同、Reeder 本地证据和 Figma 节点。
- 设计静态图与实际运动冲突时，暂停“像素微调”，补齐视频/实机行为证据后再决策。
- 每个 Slice 结束时交付：改动范围、未改动范围、测试结果、设备结果、剩余缺口、回滚方式；未完成不能用“基本完成”替代状态标签。
