# Babel 2.0 产品与迁移合同

状态：当前规范产品与验收合同文本；产品实现仍未完成（2026-08-31）。
适用平台：iOS 前端迁移；macOS、同步服务和内容管线不因本合同自动重写。  
产品名：**Babel 2.0**

本文件把 Babel 2.0 的产品范围、设计证据、迁移顺序和验收边界固定下来。它不是“已经完成”的声明。凡是没有运行证据、真机证据或用户视觉验收的项目，必须继续标为未验收。

## 1. 产品边界与版本谱系

### 1.1 Babel 2.0 的定义

Babel 2.0 是在现有数据与服务能力上重建 iOS 前端体验的产品版本。目标是让 Feeds、Library、阅读器、订阅管理和设置在同一套导航、状态、几何和交互合同下工作，并达到 Reeder Classic 的克制、连续和跟手感。

Babel 2.0 的工作范围包括：

- 新的 iOS 根壳、Feeds 首页、Library/Starred/Unread/All、源和文件夹层级；
- Timeline/feed hero、列表、列表内搜索、翻译状态和加载/空/错误状态；
- Reader 原文、翻译、阅读模式、内置浏览器、分享、长图和滚动收缩标题；
- 订阅源管理、添加订阅源及发现入口；
- Settings 新信息架构、编辑器、语言、外观、翻译模型和服务状态；
- 既有 Core Data、账户、同步、翻译、图标缓存和阅读内容管线的复用与隔离；
- 在真实 iPhone 上对几何、滚动、翻页、点击反馈、过渡和状态恢复的验收。

根入口决策：冷启动直接进入 Babel 2.0 的 Feeds/Library 根壳；旧的账号卡片 landing page 不再作为产品页面。`.home` 与 `.library` 是导航语义而不是两个必须分别呈现的 landing screen；实现可以将它们统一到 Feeds/Library root，但不得在启动时插入旧账号卡片页面。

不自动包含：

- 重新设计或迁移 macOS UI；
- 更换 Core Data 数据模型、账户协议或翻译供应商，除非某个 Slice 的依赖审计证明确有必要；
- 从静态 Figma 画面臆造未被合同锁定的动画；
- 把 Genesis 的“有代码”当作 Babel 2.0 的“已验收”；
- 仅凭模拟器截图、单元测试或 Figma 预览宣称真机手感完成。

### 1.2 版本谱系与实时状态边界（audit-only historical reference）

以下是不可变历史基线和不可变合同/资产提交的证据快照（2026-08-31；不是实时
hosted remote 核验）：

| 版本 | 产品定位 | 本地 annotated tag peeled SHA | evidence snapshot |
|---|---|---|---|
| v0.5 | Genesis v1 stable baseline | `649f85fd50e5fff21e75818193011250baf08d50` | 本地 annotated tag；远端 tag 仅据先前 push agent 报告记录 |
| v1.0 | Genesis v2 stable baseline | `d1679c7f253d37eda557970fca0827c096132a05` | 本地 annotated tag；远端 tag 仅据先前 push agent 报告记录 |
| v1.1 | pre-Babel 2.0 UIKit redesign baseline | `a94c00626edf13bb3e869c35924bfd6ece7e6165` | 本地 annotated tag peeled SHA；远端 tag 仅据先前 push agent 报告记录 |

不可变相关提交（用于追溯，不代表实时工作树状态）：

| 提交 | 内容 | 证据边界 |
|---|---|---|
| `9fda5c5650d06ff5155ead466adbe1b084ccdd44` | Babel 2.0 AppIcon 静态资产 | 仅代表该提交中的 Light/Dark/Mono（Tinted）静态资源及其提交事实 |
| `ce7c0ea38da3cb8bcab9a01dd6bd712b215ae6d9` | Babel 2.0 产品与 Motion 合同的上一不可变版本 | 仅代表该提交中的两份合同文本；本次修订须以新的不可变提交记录，不代表后续工作树或分支状态 |

实时分支、HEAD、工作树、未提交变更和合同之外的实现状态，必须在检查时同时查询
Git 与 `Design/Babel2/Project/STATUS.md`。本合同不是 live-status source；任何
evidence snapshot 都不能替代该实时查询，也不能把历史提交 SHA 推断为当前分支或
工作树状态。

### 1.3 与旧 UI 的边界

本节中涉及历史版本、旧工程路径或旧类型名的句子均标记为 `audit-only historical
reference`：它们用于迁移回退和证据追踪，不参与 no-new-legacy-name gate，也不得被
复制到新的 Babel 2.0 用户界面或新叶子文件。

- Genesis v1（v0.5）和 Genesis v2（v1.0）是历史运行基线，用于保留数据、服务和回退能力，不是 Babel 2.0 的视觉合同。
- v1.1 是进入 Babel 2.0 前的 UIKit 基线；它证明了当前迁移起点，不证明新 UI 的完整性。
- 旧 Genesis 路由可以在迁移期间作为回退或功能参考，但必须由明确的 feature gate 隔离，不能与 Babel 2.0 的导航栈、颜色、布局常数、图标解析器或状态机隐式混用。
- Babel 2.0 前端可以复用旧的数据和业务管线；“复用服务”不等于“复用旧视觉组件”。
- 迁移期间 Release 仍可保留 Genesis fallback，但在每个 Slice 的验收记录中必须写清用户进入的是哪一套 UI。
- Babel 2.0 的最终产品/UI/所有新增代码都采用 Babel/Babel2 命名；当前采用路线 A：旧系统 identity 暂时隐藏在唯一 `LegacyIdentityCompatibility` 兼容边界内，不放弃最终源码和 target 的技术重命名，而是等 Babel 2.0 真机稳定后分阶段迁移，避免数据断裂。可执行的四级 gate 见 1.5。

### 1.4 最新产品决策覆盖层（2026-08-31）

以下条款优先于本文件早先引用的静态 Figma/Batch 描述；Figma Drafts 原文件保持不改，并在文末记录 supersession 对照。

- 启动：Babel 2.0 cold start 直接到 Feeds/Library root，不显示旧 account-card landing page。
- Feed hero：expanded 状态的图像/背景连续延伸到状态栏与动态岛区域，并由 hero 自身提供完全不透明底图和足够对比的 scrim；compact/list 状态切为完全不透明的实色 chrome。日期、文章列表、Reader WebView 以及其他滚动内容不得透过状态栏显示。expanded 到 compact 是同一连续 progress surface，不能拆成离散页面。
- Timeline 几何：hero/source title/compact chrome 与首个 date header 之间不得出现独立 spacer、透明空带或可见的背景裂缝；只能使用标准 section inset token（provenance=`toTune`，待 Figma overlay 量测确认），不得为各状态另造隐式间距。list paper surface 必须连续且完全不透明；expanded、compact 及中间 `pHero` 状态均不得有视图裂缝；date header 与 article rows 必须属于同一个 scroll surface。自动 geometry/snapshot 检查、模拟器结构检查和目标 iPhone 实机检查均必须覆盖该边界。
- Library filter motion：Starred/Unread/All 在同一路由的固定槽位 tap 切换；selection pill、source/article list 的 translate/crossfade、summary 与 per-source counts 共享同一个 `pFilter`（或等价连续进度）。目标 count 必须按目标 filter 语义计算；快速连续 tap 从当前 presentation state 中断并反向/重新跟手，不 reload 整页、不闪烁。`180 ms` 为 Figma linear reference，同时标为 Babel `toTune`，必须有 unit、simulator 和 physical-device gate。
- Reader：顶部原长图位置改为普通系统分享；长图入口只在底栏，tap-only 生成长图，不以 long-press 承载分享。
- Article media：横向正文图片 100vw/full-bleed 贴齐屏幕两侧且为直角；正文文字和 caption 保持 reading inset。portrait/inline 图片不强制 full-bleed；`figure`、链接和 wrapper 不得重新加圆角。
- 颜色：全局禁止 hard-coded legacy mint/green。普通 icon、link、star、selection、reading-mode 状态使用 neutral gray/black；链接使用加粗和中性下划线，不使用绿色。accent 只由用户选择的主题色驱动 Settings switch 和 Reader progress ring；例如 Forest 不得扩散到其他控件。
- Loading：sync arrow 是唯一同步指示器，只在真实 syncing 期间旋转并在完成后隐藏。文章、翻译和普通加载使用 skeleton/passive state；不得将系统菊花与 sync arrow 叠加，失败必须变成可读 error + retry。
- Reader 首屏：进入文章时 title/byline 必须位于正文上方并立即可见；下滑由同一连续 motion surface 将它们移到 compact header，icon/progress 以连续渐出进入顶栏，不得因异步加载先隐藏标题。
- 正式 AppIcon 资产事实：commit `9fda5c5650d06ff5155ead466adbe1b084ccdd44` 已提交最终 Light/Dark/Mono（Tinted）三套静态资源；root 已逐图检查，独立静态 QA 与 actool QA 均通过。用户授权达标后，这三套资源直接作为 Babel 2.0 AppIcon。这里不宣称用户对最终 Light 做过逐像素再次口头确认。Light 使用明亮木桌与逐本独立的暗色调杂志封面，不使用整张黑色蒙版，也不得用统一压黑、烧焦感的降级版本替代；Dark 使用已选定的深色木桌版本；Mono/Tinted 从获选明暗版本派生。runtime appearance wiring、模拟器外观选择和真机 Home Screen 检查仍待完成；未跟踪的 Round 4 草稿只记录设计过程，不推翻该 commit 的正式资产事实。

### 1.5 路线 A：命名与系统身份迁移 gate

路线 A 是当前唯一有效决策：最终产品、UI、用户可见文案和所有新代码都使用 Babel
命名；旧系统 identity 只暂时通过唯一 `LegacyIdentityCompatibility` 隐藏兼容层存在。当前阶段只执行 Gate A、Gate B
和 compatibility isolation；阶段化不等于放弃最终源码/target 改名，而是把内部
路径、符号、工程、target、scheme、CI 和外部仓库身份迁移放到 Babel 2.0 稳定可用
且真机验收完成之后，并以数据迁移证据和单独授权为前提。

- **Gate A — no-new-legacy-name（立即生效）**：对相对当前 Babel 2.0 基线新增或修改的文件，逐个扫描 code、resource、test、用户可见文案、新叶子文件名、类型、方法、accessibility identifier、log category 和 route；任何新增旧品牌/旧缩写 token 即失败。新文件放在既有旧 target 或 directory 下，不因继承 parent path 而失败；但新文件 basename、新增声明和新增内容仍必须使用 Babel/Babel2 命名。
- **Gate A 检查方法**：检查器只比较当前变更集与已登记基线，扫描叶子 basename 及新增/修改内容；它不因父目录、父 target 或 inherited module 名称命中而失败。旧 token 集合必须来自显式登记的 legacy-name allowlist，并逐项记录命中文件、命中位置、例外理由和 owner；未登记的命中直接失败。`audit-only historical reference` 合同/审计区段从扫描输入排除，但不能把代码、资源或用户可见文案伪装成审计区段。
- **Gate A 例外边界**：若当前编译必须引用旧 build target/module import，只能列入 build/test harness 的显式 allowlist；旧 persisted/system identity（包括 bundle identity 相关字符串、App Group、Keychain/access-group、CloudKit、UserDefaults 旧 key/data path/state URL 等）只能集中通过唯一 `LegacyIdentityCompatibility` 边界。allowlist 绝不能成为第二个 persisted/system identity 出口。不得把这些例外暴露给 UI、accessibility、日志分类或 route。
- **Gate A 例外标记**：合同、历史审计和 supersession 对照中可以引用旧名，但所在段落必须明确写出 `audit-only historical reference`；这些引用不参加 no-new-name 扫描，也不构成新代码命名许可。
- **Compatibility isolation（当前阶段必须完成）**：所有仍需保留的旧 build/module 引用只能从上述 build/test harness allowlist 进出；旧 persisted/system identity 只能从唯一 `LegacyIdentityCompatibility` 边界进出，不能从 allowlist 进入。新 Babel2 UI、route、日志、accessibility 和资源不得直接依赖或显示它们。该隔离不等于现在执行全量技术重命名。
- **Gate B — user-visible zero legacy（当前产品发布前）**：用户可见 UI、Accessibility、分享文案、通知、错误信息、日志展示和 deep-link/route 表面不得出现任何旧品牌/旧缩写，即使底层兼容层仍存在。
- **Gate C — internal technical rename（真机稳定后）**：待 Babel 2.0 完成目标 iPhone 的冷/热启动、数据、同步、Reader、浏览器、翻译和状态恢复验收后，再单独迁移源码类型、module、target、包产品、工程路径和内部持久化映射；迁移必须有备份、schema/version、回滚和断裂检测证据。
- **Gate D — bundle/app/external identity change（单独授权）**：bundle identifier、App Group、Keychain/access-group、Core Data store identity、App Store/app identity、GitHub repository/remote identity 或对外项目名只能通过明确的迁移项目和用户授权变更；不能作为 UI 重建或自动全局替换的副作用。

## 2. 设计来源与证据优先级

当来源互相矛盾时，按以下优先级处理：

1. 用户在真实 iPhone 上对目标行为和手感的明确验收；
2. Reeder Classic 的锁定截图、视频、测量台账和本地参考；
3. Figma Interaction Contract 中明确写出的状态转换、几何和运动检查点；
4. Figma Batch/Settings 规格中的屏幕清单和信息架构；
5. 当前 Babel 代码：只作为数据流、服务依赖和可行性证据；
6. Soft Shell：仅作为历史参考，不得当作 Babel 2.0 当前视觉来源。

### 2.1 当前参考的本地路径和节点（audit-only historical reference）

本节中的旧工程路径、旧模块名和旧类型名均为 `audit-only historical reference`，仅
用于定位证据；它们不参与 Gate A，也不得作为新 Babel2 文件的命名模板。

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

下表的“当前证据与状态”可能引用旧工程文件或旧类型名；这些引用均属于
`audit-only historical reference`，不构成新 Babel2 命名或 UI 复用许可。

| 区域 / 能力 | 当前证据与状态 | 用户可观察验收标准 | 数据与服务依赖 |
|---|---|---|---|
| Babel 2.0 根壳 | `/Users/wenbopan/Downloads/AI Projects/Babel app/iOS/BabelUI/BabelShellViewController.swift` 已将根入口接到 Feeds；Release/Debug feature gate 仍存在；**半实现** | 冷启动直接进入 Feeds/Library root，不经过旧 account-card landing page；导航栈、状态栏和底部栏稳定；离开再返回不重复壳、不跳旧世代 UI；旧 UI 只能通过明确回退入口出现 | SceneDelegate、feature gate、UIKit 导航 |
| Feeds 首页 | `BabelFeedsViewController.swift` 有 unread/folder/feed rows、计数、展开；**有代码未验收** | 首屏显示 Feeds、Starred、Unread、All 及源/文件夹；选中态、计数、缩进、分隔和点击反馈与 Reeder/Figma 一致；文件夹展开原地发生并保持上下文 | Core Data feeds/folders/articles、SmartFeeds、图标缓存 |
| Starred / Unread / All | Feeds 过滤状态已部分存在；Figma Library `22:36`、Unread `22:7`、Starred `29:8`、All `29:23`；**半实现** | 点击过滤器只在固定槽位原地 `CHANGE_TO`；selection pill、summary、source/article list 使用共享 `pFilter` 做 translate/crossfade，且可从当前 presentation state 中断/反向；不 reload 整页、不闪烁；列表回到顶部但路由和其他上下文保留；没有 push/card/sheet；目标数量与实际结果一致。Starred 只显示至少有 starred 文章的源/文件夹，且每个源/文件夹的计数只统计当前过滤语义下的 starred 文章。`180 ms` linear 为 reference/toTune；unit、simulator、physical gate 均须通过 | 文章 read/star 状态、SmartFeeds 查询 |
| 源 / 文件夹计数 | 新 Feeds 代码有 counts；**有代码未验收** | 文件夹计数等于可见子项语义；源计数等于对应过滤下文章数；0、同步中和错误时不显示过期的“成功数字” | Feed/folder 关系、文章状态、同步刷新 |
| Feed 列表 / Timeline | `BabelTimelineViewController.swift` 有分组文章列表、底部栏、行内标题翻译；**半实现** | 日分组、标题、来源、时间、摘要、已读/未读重量、缩略图和底部操作与锁定参考一致；点击文章进入 Reader，返回保留位置 | 文章抓取、正文/摘要、日期、本地化、缩略图 |
| Feed hero | 代码有 hero 与滚动插值；Figma Feed expanded `22:37`、transition `244:541`、compact `244:552`、no image `244:563`；**有代码未验收** | expanded hero 的图像/背景延伸到状态栏与动态岛区域，并由自身提供完全不透明底图和对比 scrim；compact/list 切为完全不透明实色 chrome；日期、文章列表不透过状态栏；hero/source title/compact chrome 到首个 date header 之间没有独立 spacer、透明空带或裂缝，只使用标准 section inset token（`toTune`，待 Figma overlay）；date header+article rows 是同一 scroll surface；展开到收缩是连续 progress surface，无卡片阴影跳变；无图时有稳定 fallback；自动 geometry/snapshot、模拟器和目标 iPhone 检查均通过 | `TimelineFeedHeader`、`FeedHeroIconLoader → FeedIconDownloader → FaviconDownloader`、dominant color/cache |
| Feed 搜索 | `BabelArticleSearchViewController.swift` 有当前源文章搜索覆盖层；**半实现** | 搜索留在当前源上下文；键盘、取消、空结果、错误和返回不丢失原滚动位置；搜索结果仍遵守文章行合同 | 本地文章索引/过滤、iOS 搜索输入 |
| Feed More / 反馈 | Feeds/Timeline 有 More/Feed Issues sheet；**有代码未验收** | 菜单/反馈出现和消失不破坏当前 route、filter、scroll；命令作用后有可观察结果或明确错误；菜单材料和返回时序需实机确认 | UIKit sheet/action、订阅源状态、日志 |
| Reader 原文 | `BabelReaderViewController.swift` 有 WKWebView、header、底部 toolbar；Figma Reader Original `22:38`；**有代码未验收** | 进入时标题、日期、byline 立即位于正文上方且可见；下滑由同一连续 motion surface 移到 compact header，feed icon/progress 渐出并保持稳定；底部 read/star/next/translation/long-image 槽位稳定；进入、返回、下一篇不跳位；短文和长文均不裁切 | WKWebView、文章 HTML/正文、`ReaderViewExtractor`、文章状态 |
| Reader 长文滚动 / 收缩标题 | 代码有 compact header/progress；Figma `180:370`、`180:424`、`143:444`、`180:520`、`227:675`；**半实现** | status bar 与 top chrome 完全不透明；只有文章真正滚动才收缩；初始 title/byline 在正文上方；progress 使用 `p=clamp((offsetY-collapseStart)/(maxScrollableOffset-collapseStart),0,1)`；42pt 真图标位于 48pt frame，icon/progress 连续渐出；返回/旋转/加载后位置保留 | WKWebView scroll、实际内容高度、安全区、Feed icon |
| Reader pin/unpin | 代码有 Reader controls，但完整 directional contract 未有 UI 测试；**半实现** | 12pt 方向性移动后，顶部/底部控制一起显隐；180ms linear；可中断、反向跟手；不重置 route、文章或滚动位置 | UIScrollView/WKWebView、UIViewPropertyAnimator 或等价状态机 |
| Reader 翻译 | Reader 有翻译控制；Figma Original `22:38`、Translating `117:263`、Translated `117:317`；**半实现** | `Original → Translating → Translation` 原地发生；Reader skeleton 与正文几何稳定，段落级渐进且不跳位；取消/失败可回到原文；不得用系统菊花或 sync arrow 叠加；不擅自增加 AI 目标语言设置 | `TranslationConfig`、翻译模型/API/key、流式绑定、文章段落解析 |
| Feed 列表翻译 | Timeline 有标题翻译；**半实现** | 列表标题在原位置替换，不改变行高度策略；翻译中有明确但不扰乱滚动的状态；失败显示可重试结果 | 翻译 API、标题缓存、文章列表数据 |
| 阅读模式 | `ReaderViewExtractor` 路径存在，Reader 有入口；**有代码未验收** | 阅读模式从当前文章进入，内容可读、图片/链接规则明确；返回保留位置；无正文时显示错误而不是空白 | HTML 提取、WebView、主题设置 |
| 内置浏览器 | `/Users/wenbopan/Downloads/AI Projects/Babel app/iOS/BabelUI/BabelBrowserViewController.swift`；**有代码未验收** | 原文链接在内置 WKWebView 打开；文章正文右向左滑进入浏览器并可在浏览器左/右边缘返回 Reader；后退/前进/刷新/分享/外部打开可用；返回 Reader 不丢状态；加载失败可重试 | WKWebView、网络、安全策略、系统分享 |
| 系统分享 | Reader 与 Browser 有 `UIActivityViewController`；**有代码未验收** | More/Browser 分享使用系统分享面板；分享对象、标题和 URL 正确；取消后回到原文章/原滚动位置 | URL、文章 metadata、系统分享服务 |
| 长图 | `ArticleLongImageExporter` 有调用路径；**半实现** | 只由 Reader 底栏的普通 tap 明确触发；生成完整文章长图或给出可理解失败；导出过程中不阻塞错误地覆盖 Reader；保存结果可观察；长图按钮不承担 long-press 分享，普通系统分享由顶部原长图位置的 Share action 触发 | HTML/WebView snapshot、图片拼接、照片权限 |
| Reader Actions | Reader 已有 UIAlertController actions；**半实现** | 顶部原长图位置固定为普通 System Share；长图只在底栏且 tap-only；Reader action/底栏顺序、菜单返回、route/位置与 Figma/实机材料一致；不得把长按定义为分享入口 | 文章状态、翻译、导出、系统分享 |
| 添加订阅源 | `BabelSubscriptionViewControllers.swift` 可输入 URL 并解析 RSS/Atom/JSON alternate link；**半实现** | 添加页有取消/保存或明确完成路径；合法源可添加、重复源可解释、无效源有错误；进度/失败/重试可观察；不声称已有关键词发现 | `URLSession`、RSS/Atom/JSON parser、Account/Feed API、Core Data |
| 添加订阅源搜索/发现 | 当前实现是网站/feed URL 抓取，不是 Feedly/Podcast/YouTube/Reddit 关键词搜索；**未迁移** | 输入关键词后能按合同的来源类别搜索；结果可预览并订阅；服务不可用、空结果、限流和错误有明确状态；若后端未提供，必须显示未支持而不是伪造结果 | Discovery API、第三方服务 key、网络、订阅写入 |
| 订阅源管理 | 有 rename/remove 管理页；**有代码未验收** | 源和文件夹能查看、改名、删除、排序/层级关系可解释；删除有确认并立即更新 Feeds；同步失败不丢本地状态 | Account、Feed/folder persistence、sync |
| Settings 根 | `BabelSettingsViewController.swift` 已有 8 类别；Figma `110:300`；**半实现** | 8 类别入口可到达：Accounts & Sync、Subscriptions & Discovery、Timeline、Reader、Translation、Appearance & Language、Notifications、Support & Diagnostics；关闭/返回不丢状态 | AppDefaults、Account、TranslationConfig、系统设置 |
| Settings 二级页 | Figma `110:320`–`110:460` 及 `110:480`–`110:600`；现有编辑器部分复用旧控制器；**半实现** | 普通详情 push；可逆选择使用 anchored popover；布尔项即时生效；有延迟保存的编辑器有 Cancel/Save；不混用旧 action sheet 与新合同 | Settings 控制器、AppDefaults、账户、主题、翻译配置 |
| Settings 动态 Translation Model | Figma `110:560`，catalog 规则为动态 Top 10 + 每供应商恰好 3 个；当前规格与旧代码 15/5/底部 refresh 有冲突；**未验收** | 专用编辑器顶部刷新；固定 logo/check 槽；加载、空、错误和选择状态稳定；供应商分组数量符合最新合同，若未实现必须标缺口 | 供应商目录 API、模型配置、缓存、网络 |
| i18n / 目标语言 | `AppLanguageController`、TranslationConfig 和本地化资源存在；**有代码未验收** | 界面语言切换可观察且不破坏布局；全局目标语言影响列表/Reader 翻译；原文、翻译中、失败和未配置均可本地化；不把“语言选项存在”当作翻译完成 | Localizable strings、AppLanguageController、TranslationConfig、服务返回语言 |
| 浅色/深色/主题色 | 设计 token 和部分代码存在；Figma full dark masters 标为后续 Batch；**半实现** | 浅色/深色均无反白、透明状态栏、图标不可见或文本对比不足；切换后当前 route/scroll/selection 保留；普通 icon/link/star/selection/read-mode 使用 neutral gray/black；主题 accent 只驱动 Settings switch 与 Reader progress ring；禁止任何 hard-coded legacy mint/green | BabelDesignSystem、traitCollection、用户主题设置 |
| 图标缓存 | 当前链 `FeedHeroIconLoader → FeedIconDownloader → FaviconDownloader` 和 fallback/dominant color 存在；**有代码未验收** | 同一 feed 不重复解析/下载；缓存命中不闪烁；坏图标、有图标、无图标和网络失败均有稳定 fallback；Feed hero 与行图标不建立第二套 resolver | URL cache/disk cache、favicon 下载、图片裁切/主色分析 |
| 同步状态 | 根壳有 sync glyph/Feed Issues 入口，历史同步能力可适配；**半实现** | 初始同步、同步中、成功、失败和离线均有可观察状态；sync arrow 只在真实 syncing 期间出现并旋转，成功/停止后自动隐藏；数字、列表和 star/read 操作不会显示已失效成功值；失败可重试并保留本地内容 | 账户、同步、网络、本地模型、活动日志 |
| Loading / Empty / Error | Figma 有 Empty State `25:8`、Confused Bear `241:41`；完整 loading/error/empty master 未齐；**未验收** | 每个屏幕定义首次加载、刷新、无内容、无搜索结果、网络错误、解析错误和翻译错误；状态不造成布局跳变；文章/翻译加载使用 skeleton/passive state；不得同时显示系统菊花和 sync arrow；错误有恢复动作；不以永恒 spinner 代替错误 | 网络、解析、同步、翻译、状态模型 |
| Babel 2.0 AppIcon | commit `9fda5c5650d06ff5155ead466adbe1b084ccdd44` 中 `iOS/Babel2/Assets.xcassets` 的最终 Light/Dark/Mono（Tinted）静态资源已提交；root 逐图检查、独立静态 QA 与 actool QA 已通过；**素材与静态 QA 通过，runtime appearance 待验收** | 用户授权达标后直接作为 Babel 2.0 AppIcon。Light 为明亮木桌、逐本独立暗色调杂志封面构成的俯拍 B，不使用统一黑色蒙版或统一压黑/烧焦感的降级版本；Dark 使用深色木桌版本；Tinted/Mono 与主题外观一致；runtime appearance wiring、模拟器外观选择和真机 Home Screen 检查仍待完成 | asset catalog、AppIcon 配置、runtime appearance wiring、模拟器与真机 Home Screen |
| 自动化门禁 | 现有测试覆盖 shell flag、pop policy、original-link swipe；没有完整 UI/snapshot/motion/device tests；**未验收** | 每个 Slice 有结构/单元检查、关键 UI 测试和实机检查记录；测试失败阻止“完成”标签；性能/运动由设备而非单元测试单独验收 | XCTest、截图/比较工具、真机、测试数据 |

## 4. 屏幕注册表与节点合同

以下是 Figma 状态文件中当前可定位的主屏幕和状态。节点编号用于回查，不代表已经有生产实现。

| 屏幕/状态 | Figma 节点 |
|---|---|
| Feeds/Library root（语义 Home；旧 account-card landing page 已移除） | `86:204`（仅作历史节点回查，不作为启动页面合同） |
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

关键组件节点包括：Status Bar `16:2`、Home Mark `82:18`、Home Account Card `83:18`（`audit-only historical reference`，仅用于 supersession 回查，不得实现为启动 landing page）、Folder Row `19:12`、Feed Row `19:23`、Article Row `20:32`、Translation Toggle `43:19`、Reading Mode `92:22`、Reader Toolbar `21:5`、Filter Pill `28:44`、Feed Toolbar `22:35`、Compact Header `143:73`、Empty State `25:8`。

### 4.1 固定几何与交互约束

- 设计画布为 402×874；Reeder 锁定参考为 1206×2622，约 3 px/pt。
- 顶部控制中心约 y=81，槽位 x=`[32, 201, 290, 330, 370]`；未使用槽位必须保持空，不得自行塞入新按钮。
- 底部 toolbar 为 `[0,802,402,72]`，中心 y=826，槽位约 `[32,104,201,290.5,362]`；可点击命中区域 44pt。
- Feed expanded hero 的图像/背景延伸到物理顶部、状态栏和动态岛区域；hero 自身底图和 scrim 必须完全不透明且保证系统文字对比。compact/list 状态使用完全不透明实色 chrome；日期、文章列表和其他滚动内容不得透过状态栏。
- Reader status bar 与所有 compact/list chrome 使用不透明 `BabelPalette.background`；文章正文 WebView 不得 underlap 状态栏，也不得由透明、glass、blur 或 scroll-edge effect 暴露到状态栏。
- Reader progress 是从 12 点钟方向开始的一条连续顺时针 arc；不能按离散页面硬切。
- 正文横向图片使用 100vw/full-bleed 直角显示，贴齐屏幕两边；正文文字与 caption 保持 reading inset。portrait/inline 图片可保留 reading inset；任何 `figure`、链接或 wrapper 不得重新加圆角。
- 全局颜色遵循语义 token：禁止 hard-coded legacy mint/green；普通 icon/link/star/selection/read-mode 用 neutral gray/black，链接用加粗与中性下划线。用户选定的 accent 仅驱动 Settings switch 与 Reader progress ring。
- sync arrow 是唯一同步旋转指示器，只在真实 syncing 时显示并自动隐藏；文章/翻译/普通加载使用 skeleton/passive state，禁止系统菊花与 sync arrow 同时出现。
- Reader 初始 title/byline 在正文上方立即可见；下滑时通过一个连续 motion surface 移入 compact header，icon/progress 连续渐出。
- Reader 顶部原长图槽位为普通系统分享；长图移到底栏且只能 tap 触发，不使用 long-press 分享。
- Feed filter、folder expansion、搜索均优先使用原地 `CHANGE_TO`；不得因复用方便而推成 push/card/sheet。
- 短选项使用 anchored popover；Settings 的延迟保存编辑器使用 Cancel/Save；开关即时生效。

## 5. 数据与服务依赖合同

本节对既有业务能力的引用属于 `audit-only historical reference` 或迁移依赖说明；
它们不参加 Gate A 的新增命名扫描。新 Babel2 adapter 必须遵守 1.5 的例外边界。

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

- 迁移状态栏、顶部/底部栏、Light/Dark、字体、命中区域、导航返回和可中断转场；建立 no-new-legacy-name gate，新增 Babel 2.0 文件和用户可见标识不得出现旧产品命名。
- 先实现 loading/empty/error 基础容器，不让每个屏幕自造一套。
- 验收：冷启动直接到 Feeds/Library root；冷/热启动、深浅色切换、后台回前台、push/pop 和边缘滑回均不产生跳壳或旧 UI 串入；sync arrow 只在真实同步时出现；AppIcon runtime wiring 已接通。

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
- 验收：进入文章时 title/byline 在正文上方；多种真实文章高度、不同 safe area、Light/Dark、进出后台和返回均保留位置；title/byline/icon/progress 连续收缩且不闪失；横向正文图片 full-bleed 直角；progress 只随真实可滚动内容变化并使用主题 accent。

### Slice 5 — Reader actions、翻译、阅读模式、浏览器、分享、长图

- Reader action menu、原地翻译流、阅读模式、内置浏览器、系统分享、长图导出、下一篇/标记已读。
- 明确取消、失败、网络断开和导出权限路径；不把暂时 UIAlertController 作为最终交互合同。
- 验收：顶部原长图位是普通系统分享；底栏长图为 tap-only；文章正文左滑进入内置浏览器且可边缘返回；动作顺序、菜单返回、段落级翻译过渡、导出/分享结果和 Reader 位置均在实机可观察且可中断；加载不叠加系统菊花和 sync arrow。

### Slice 6 — 订阅管理、发现、Settings 和 i18n

- 添加订阅源、关键词发现（若服务实际存在）、管理源/文件夹、Settings 8 类别及二级编辑器/popover。
- 接入全局语言、目标语言、主题、通知、诊断、翻译模型目录和 API key 状态。
- 验收：订阅管理、添加订阅源、发现搜索均有真实成功/空/限流/失败状态；Settings 使用新 IA 而非旧页面；每个编辑器有正确的保存/取消语义；主题 accent 仅作用于 switch 与 Reader ring；服务缺失时显示真实限制；中文/英文全界面切换不破坏当前 route/layout；无新增旧产品命名。

### Slice 7 — 全面状态、可靠性、真机验收和清理

- 补齐 loading/empty/error/offline/sync/translation/discovery 全状态；跑自动化、性能和对照截图；在目标 iPhone 完成运动验收。
- 根据验收结果删除重复 UI、旧视觉常数和未使用回退，不提前清理数据/服务。
- 验收：所有矩阵行有证据链接和负责人；用户接受关键屏幕的几何与手感；性能/预加载、翻译稳定性、右滑/左滑浏览器手势、横向图片、AppIcon 三外观和中英文 i18n 均有当前构建证据；未完成项仍留在缺口清单。

## 7. 保留、隔离与最终删除清单

本节中列出的旧路由、旧控制器和旧资源是 `audit-only historical reference`，用于
定义隔离/删除范围；它们不参加 Gate A，也不得出现在用户可见表面。

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

本节中为解释历史实现而保留的旧类型名和测试名均为 `audit-only historical
reference`；它们不参加 Gate A 命名扫描。

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
11. 临时几何 B、Inter fallback、neutral thumbnail、compact T mark 等设计占位物已经是最终品牌或最终素材；正式 Babel 2.0 AppIcon 以 Light/Dark/Tinted（Mono）资源合同为准，Light 不得使用统一黑色蒙版或统一压黑/烧焦感的降级版本；
12. 把 Settings IA 文档中“7 个二级编辑器”和 Figma 状态文件的完整节点列表视为无冲突事实；精确屏幕注册以 `figma-state.json` 和用户当前决策为准，差异必须单独解决。
13. 新增 Babel 2.0 代码、资源、测试或文档出现旧产品命名就视为 gate 失败；历史路径和旧 build/module/test-harness 引用仅在显式 allowlist 中保留且不可显示给用户；旧 persisted/system identity 只能在唯一 `LegacyIdentityCompatibility` 边界中保留，allowlist 不得成为第二出口。

## 9. 当前证据缺口与待补证据

- Reeder 中同一文章、相同滚动位置的完整像素/运动对照尚未锁定；Reader 菜单动画和返回时序在本地参考中不稳定。
- Figma 设计批次明确存在 API 循环预览、SF Pro 渲染 fallback、Feed thumbnail 占位和完整 dark masters 待补等限制。
- 真实 feed favicon、连续 progress 在真实文章高度上的行为、safe area、阈值/迟滞/时长尚未完成 iPhone 实机验收。
- Reader 翻译的生产 Swift/SwiftUI 流式绑定和段落 skeleton 过渡尚未由设计文件证明已接通。
- Feed filter/folder 原地状态、Feed hero 既有 pipeline 的代码同步需要逐 Slice 核对；不能只看节点或静态 preview。
- 添加订阅源的关键词发现后端、供应商范围、认证和配额尚未由当前源码证明。
- Loading/empty/error 的完整主视觉和每种服务错误的恢复动作尚未齐全。
- 本合同版本的证据快照记录了创建时工作树未清洁，且此前修改涉及多处 Swift、工程、测试和未跟踪设计产物；本文件不把那一时点的状态重新解释成稳定发布物。实时状态仍须按 1.2 查询 Git 与 `Design/Babel2/Project/STATUS.md`。

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

## 12. Supersession note：2026-08-31 用户决策覆盖的旧 Draft 条款

本节只记录覆盖关系，不修改 `Figma Drafts/` 原文件。本节全部属于 `audit-only
historical reference`；实现与验收以本合同最新条款为准，旧节点不能继续作为相反
行为的依据，也不参与 Gate A。

| 被覆盖的旧条款 | 覆盖后的 Babel 2.0 决策 |
|---|---|
| `Figma Drafts/BATCH-01-SPEC.md` §01 Home（约第 35–41 行）要求以 centered brand mark、separator 和 account card 组成 root Home；组件清单及后续变更记录仍保留 `Home Account Card` | cold start 直接进入 Feeds/Library root；旧 account-card landing page 移除。`Home` 节点只保留为历史回查/语义别名，不得作为启动页面实现。 |
| `Figma Drafts/INTERACTION-CONTRACT.md` Feed hero 条款（约第 70–74 行）及 `BATCH-01-SPEC.md` Feed 条款（约第 57–61、287–290 行）要求 hero 从不透明 status region 下方开始、永不 underlap system status items | expanded hero 的图像/背景延伸到状态栏与动态岛区域；hero 自身提供完全不透明图像/背景和对比 scrim。compact/list 仍为完全不透明实色 chrome，日期/文章/list/WebView 不得透过状态栏；expanded→compact 仍是连续 motion surface。 |
| `Figma Drafts/INTERACTION-CONTRACT.md` Reader action 条款（约第 152 行）及 `BATCH-01-SPEC.md` Reader header action/变更记录（约第 73、234–237 行）将顶部 action 定义为 `Share Long Image`，普通 tap 生成/分享长图、long press 打开普通分享 | 顶部原长图槽位改为普通系统 Share；长图放入 Reader 底栏且仅 tap 触发；long press 不承担分享。 |
| 旧 Draft 的泛化 accent 规则（`Figma Drafts/BATCH-01-SPEC.md` 约第 120–121 行仅记录 accent 不进入三张 master，除 authentic favicon/subtle state 外不扩散） | 用户最新决定进一步收紧颜色语义：全局禁止 hard-coded legacy mint/green；普通 icon/link/star/selection/read-mode 用 neutral gray/black，链接用加粗+中性下划线；主题 accent 只驱动 Settings switch 与 Reader progress ring。 |
| `Figma Drafts/BATCH-01-SPEC.md` 旧 loading/refresh 组件记录（约第 145、169–173 行）只记录组件几何与复用，并未定义常驻/重复 spinner 的 ownership/visibility | 用户最新决定补充此前未定义的 visibility/ownership：sync arrow 只在真实 syncing 时显示/旋转并自动隐藏；文章/翻译加载用 skeleton/passive state；系统菊花不得与 sync arrow 叠加，失败转为 error+retry。 |
| 旧 Reader 静态 checkpoint 只在滚动后展示 compact identity，未锁定首屏 title/byline 与 icon 渐出连续性 | 进入 Reader 时 title/byline 必须已在正文上方可见；下滑由同一 motion surface 移至 compact header，icon/progress 连续渐出并可反向跟手。 |
| `Figma Drafts/BATCH-01-SPEC.md` 对文章缩略图的圆角描述（约第 67 行）被误用于正文媒体 | 正文横向图片 100vw/full-bleed、贴齐屏幕两侧、直角；文字/caption 保持 reading inset；portrait/inline 不强制 full-bleed，`figure`/link/wrapper 不得加圆角。该覆盖不改变列表 thumbnail 的独立规格。 |
| 旧 Draft 对命名、旧工程品牌或历史组件的直接引用可能被复制进新 Babel2 文件 | 新 Babel2 code/resource/test/docs 统一使用 Babel/Babel2；旧 build/module/test-harness 引用只在显式 allowlist 中出现且不可进入 UI；旧 persisted/system identity 只能经唯一 `LegacyIdentityCompatibility` 边界出现，allowlist 不得成为第二出口。完整旧技术命名迁移另立任务。 |

### 12.1 AppIcon 静态提交状态（audit-only historical reference）

commit `9fda5c5650d06ff5155ead466adbe1b084ccdd44` 中正式 Babel 2.0 AppIcon 的最终 Light、Dark、Mono（Tinted）静态资源已提交；root 逐图检查、独立静态 QA 与 actool QA 已通过。用户授权达标后，三套资源直接作为 Babel 2.0 AppIcon。这不是本轮重新运行的声明，也不宣称用户对最终 Light 做过逐像素再次口头确认。Light 采用明亮木桌与逐本独立暗色调杂志封面构成的俯拍 B，不使用统一黑色蒙版或统一压黑/烧焦感的降级版本；Dark 使用已选定的深色木桌版本；Mono/Tinted 从获选版本派生。runtime appearance wiring、模拟器外观选择和真机 Home Screen 检查仍属于待验收项。未跟踪的 Round 4 草稿只记录设计过程，不改变该 commit 的正式资产事实。

### 12.2 Release gate 汇总

以下项目在发布 Babel 2.0 前必须逐项有当前构建、自动检查和目标 iPhone 证据：Feeds/Library 直达根壳；Starred 源过滤及计数；Feed hero 状态栏 full-bleed 与连续收缩；Reader 首屏标题/作者、compact header、连续 progress 和主题色；横向正文图片 full-bleed 直角；单一 loading owner；无绿色语义泄漏；Reader↔内置浏览器边缘手势；文章预加载、首屏性能和翻译稳定性；订阅管理、添加订阅源、发现搜索；新 Settings IA；中文/英文全界面 i18n；Light/Dark/Tinted AppIcon runtime wiring；以及旧 UI/死代码清理和 no-new-legacy-name gate。当前阶段只执行 Gate A、Gate B 与 compatibility isolation；Gate C 的内部技术重命名必须等 Babel 2.0 稳定可用并完成真机验收后，Gate D 的 bundle/data/GitHub 外部身份变更必须另立迁移项目并取得明确授权。未有对应证据的项目必须保持未验收，不得以静态 Figma 或模拟器截图替代。
