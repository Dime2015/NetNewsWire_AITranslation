# Babel 2.0 当前状态

更新时间：2026-09-24（Asia/Tokyo）。2026-09-24 用户在目标物理 iPhone 冷启动完成 Feeds/Library 首页整页视觉验收，回复“首页验收通过了”；本批首页 Figma 对齐随后提交（见下方 Git 基线）。Dark、不同语言、旋转和其他设备仍不在已验证范围。

## 当前 Git 基线

- 分支：`codex/reeder-classic-rebuild`。
- 实现基线 `HEAD`：`ca1fa1ae46932f04569ffdd0e0bda318de467e0d`；该提交记录了旧筛选按钮修复未生效。
- root 已执行 `git fetch origin codex/reeder-classic-rebuild`；fetch 后 `origin` 与 `FETCH_HEAD` 均为 `7567f685cd85012c7774c658959f3a66386940d6`，本地 `HEAD` 为 `ca1fa1ae46932f04569ffdd0e0bda318de467e0d`，ahead 2 / behind 0。
- 本任务开始时已有用户 Xcode 真机签名留下的 `NetNewsWire.xcodeproj/project.pbxproj` dirty diff；已保留且未修改，diff hash 前后均为 `c5f5a8cfbf73750210af0fdd15cea22fcedb7cb09fd5c5a786353f646028dc35`。`Shared/Localizable.xcstrings` 仍有独立 dirty，未纳入本批；Babel2 string catalog 在本批前已有格式化/stale dirty，本批仅在其上增加 `Folders`/`Syncing…` 键。
- 2026-09-24：同一工作树在 Xcode 27.0 重新 Debug build（iPhone 17 Simulator）`BUILD SUCCEEDED`；pbxproj dirty diff hash 复核仍为 `c5f5a8cf…`。首页批次（Babel2 root/localization/string catalog、FeatureGateTests 与本目录五份文档）作为 `ca1fa1ae4` 之后的一个本地提交落地；pbxproj 签名 diff 与 `Shared/Localizable.xcstrings` 的 stale 行仍留在工作树、不纳入提交。未推送（本地 ahead 3）。build pre-action 重新生成了被 gitignore 的 `SecretKey.swift`（hash 变为 `d6337cc0…`），不影响 git。

## 当前实现与缺口

| 范围 | 源码核实结果 | 尚未关闭 |
|---|---|---|
| 启动 | 单一 Babel2 root；外部动作解析后安全 no-op | Phase 1A 完整恢复/回调、资源与 target allowlist、设备验收 |
| Feeds | 真实源/文件夹、计数、展开、三档筛选及转场已部分实现；筛选按钮已改为一次性 Auto Layout 约束定位，用户明确回复“好的，成功了” | 数据库错误传播、同步后刷新及快速切换的一致性；首页 Figma 整页视觉已于 2026-09-24 用户真机验收通过，不外推到 Dark、其他语言、旋转或其他设备 |
| Timeline | 真实缓存文章、缩略图、已有标题译文缓存展示 | 完整 hero/日期分组/搜索与翻译流程 |
| Reader | 缓存正文转纯文本展示；原文链接交给系统打开 | 正式图文阅读器、标题收缩、阅读进度、正文翻译、内置浏览器、分享/长图 |
| 导航 | M1 已接入左边缘返回；2026-09-08 用户真机确认跟手+可取消 | 深栈/根路由/旋转/非边缘误触发/120Hz 帧率数据、OSLogStore consumer integration |
| Settings/添加订阅 | 仍为占位路由 | 真实编辑、保存、搜索与管理功能 |
| 图标 | 三态静态资产已提交 | runtime appearance 与设备外观验收 |

整体状态：**基础阅读链路已实现，完整产品未完成**。需求逐行状态以 [REQUIREMENTS](REQUIREMENTS.md) 为准；设计以产品/运动合同为准，旧 `Design/current/` 不再是当前设计来源。

## 第十轮：列表行左右滑、新文章提示自动消失、重发文章去重（2026-09-29，ADR-069；用户真机验收通过，已提交推送，未另加测试）

- 行左右滑：往右 = 标为已读 / 未读（灰蓝），往左 = 加星标 / 取消星标（暗金）；轻滑露按钮、滑到底直接执行。文章列表页改为只认左边缘返回（`Babel2EdgeOnlyBackGesture`，与内置浏览器同）。
- 「↑ N 篇新文章」出现 5 秒后自动淡出。
- 重复文章：查了用户手机数据——只有一个账户，BBC 中文只订了一次；数据库里那篇是 BBC 改稿重推，同一链接、同一时间、编号 `…#0` / `…#2` 两条。改为列表里「同账户 + 同源 + 同链接（去掉 # 后）」只留一篇（`removingRepublishedDuplicates`，单源与跨源列表都用）。
- 已知：被藏起来的那一篇在数据库里仍是未读，首页未读数可能多 1；跨源列表「全部标为已读」不会标它（单个源的「全部标为已读」会）。用户订阅里「人物」用两个不同地址订了两次（kindle4rss / anyfeeder），需用户自己删一个。
- 取证用的手机数据库副本已删除。

## 第九轮追加：往上滑后的顶栏「天幕」+ 标题 22pt 缩放归位（2026-09-28，ADR-068；2026-09-29 用户真机验收通过，已提交推送）

- 没有大图时：纹路常驻（淡到 55%）、窄栏透明无下沿、列表顶部消融、日期段标题化开并入顶栏右侧；有大图时：纸色窄栏 + 纸色渐隐（取代黑色阴影），日期段标题照旧吸顶。两种页面的标题都从 27pt 缩放归位到 22pt。
- 改动：`Babel2FeedHeroView.swift`（大图区透明、纹路移出、占位标题、排版回调；窄栏标题缩放归位、天幕模式、右侧日期）、`Babel2LibraryViewControllers.swift`（纹路垫底层、消融带、段标题化开、按有无大图切换）、`Babel2FeedHeroMotion.swift`（天幕曲线）、`Babel2Type.swift`（compactTitle 22）、`Babel2HeroPattern.swift`（下沿改纸色渐隐）；测试改 3 项、新增 1 项。
- 自动化：全量 221/221；UI Driver 1/1；真机 Debug 编译并 devicectl 安装。
- 只能真机确认：消融带的位置与软硬、55% 的纹路是否合适、缩放归位的手感、22pt 在长名字下的截断、顶栏右侧日期的位置。
- 真机反馈（同日）：收起后顶栏下有一条半透明带——是 iOS 26 列表自带的顶部模糊（滚动边缘效果，盖到吸顶段标题下沿、带硬边），以前被实色窄栏和段标题挡住。天幕时关掉（`tableView.topEdgeEffect.isHidden = sky`），直接装机，未另加测试。
- 真机反馈（2026-09-29）：浅色下纹路太淡、收起后太淡 → 浅色点阵 ×1.7、色晕 ×1.6（原浅色 ×0.85）；收起后纹路保留 85%（原 55%）。直接装机。
- 真机第二次（同日，「再浓一点」「浅色还不够」「化开不明显」）：整体浓度 strength 1 → 1.3；浅色点阵 ×2.4、色晕 ×2.2；收起后纹路不再变淡（100%）；消融带改为 82 / 120 / 160 / 192pt（0 / 20% / 55% / 100%）。直接装机。
- 真机第三次（同日，截图「分界线太明显」）：大图区自带的「渐隐成纸色」层原本藏在实色底里，天幕把大图区改透明后它盖在纹路上、在大图区下沿切出硬边——改为只有铺了大图时才显示。直接装机。

## 第九轮：头部「微光点阵」（2026-09-28，ADR-067；2026-09-29 用户真机验收通过，已提交推送）

- 用户选定「四 D · 微光点阵」，六个页面各自颜色与纹路：今日晨光 / 全部方阵 / 外文经纬 / 星标星野 / 订阅源讯号（取图标主色，只在没有高清图时）/ 首页蜂巢。收起窄栏去首字母圆圈、细线换柔和阴影；展开时加眉题；标题 24 → 27pt。
- 改动：新文件 `iOS/Babel2/Babel2HeroPattern.swift`（纹路、图标主色、眉题文字、柔和阴影）；改 `Babel2FeedHeroView.swift`（大图区纹路层与眉题、窄栏）、`Babel2LibraryViewControllers.swift`（接上纹路 / 眉题、段标题吸顶挂阴影、吸顶判断改用内容坐标）、`Babel2RootViewController.swift`（首页蜂巢 + 日期、删短线）、`Babel2Type.swift`、`Babel2Localization.swift` + `Resources/Babel2Localizable.xcstrings`（「智能列表」）；测试 `Babel2FeedReaderTests.swift` 新增 6 项、扩 1 项。
- 自动化：全量 220 项中 219 过、1 项为已知偶发的阅读页栏显隐测试（单独重跑 3/3 过）；UI Driver（Release、真实数据）1/1。已编译安装到用户 iPhone 17（devicectl）。
- 只能真机确认：六种纹路在真机上的浓淡（深 / 浅色）；订阅源取色是否好看；收起后阴影的轻重；27pt 标题在有大图的源上是否太大。
- 提交注意：本轮叠在未提交的第七 / 八轮（图标集）之上，且改了同几个文件。第八轮本轮开工前的改动已存补丁 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/614eccdf-b8f9-4550-ab52-810466f9fd3a/scratchpad/round8-tracked.patch`（scratchpad 不在仓库；换会话后以各轮 STATUS「改动」清单为准）。按惯例不含 pbxproj 签名 diff、`Shared/Localizable.xcstrings` stale 行、`icon new/`。

## 第八轮：图标集换成「Reeder 式」（2026-09-27，ADR-066；2026-09-29 随第九、十轮一起验收通过，与第七轮合成一个提交推送）

- 用户看完对比页 `Design/Babel2/IconSet/review-reeder.html` 后「选这套」。设计源 `icons_reeder.py`，`make.py --export` 已重新导出 47 个素材（资源名不变）。
- 代码：只改 `iOS/Babel2/Babel2Icons.swift` 的说明注释。测试：`testUnifiedIconSetAcrossBars` 里「全部标为已读」的取样改为实心圆 + 挖空的勾。
- 第七轮（下一节）的接入代码全部保留、没有单独提交，本轮与它合成一个提交。
- 只能真机确认：新图标在 18–22pt 下的大小与轻重，尤其实心件（全部已读、账户、首页开关）是否显重。
- 用户第一次真机看后追加：首页顶栏设置 / 添加 22 → 28pt（`Babel2Icon.Size.homeTop`，改 `Babel2RootViewController.swift` 两行）；已直接编译装到用户 iPhone 17（xcodebuild + devicectl）。

## 第七轮：全 App 统一图标集（2026-09-27，ADR-065；实现与自动化完成，待真机验收，未提交）

- 设计：`Design/Babel2/IconSet/`（`icons.py` 设计源与规则、`make.py` 生成审阅页 / 导出资源、`review.html` 全套审阅页、`directions.html` 被否的四种构造方法、`BRIEF.md` 设计要求、`svg/`）。
- 接入：新资源 `iOS/Babel2/Assets.xcassets/Babel2Icons/`（47 个矢量模板图）；新文件 `Babel2Icons.swift`；改 `Babel2GlassMenu`、`Babel2LibraryEditing`、`Babel2LibraryViewControllers`、`Babel2ScopeFilterControl`、`Babel2StatusIcons`、`Babel2Type`（删旧画法）、`Babel2RootViewController`、`Babel2SmartFeedEntries`、`Babel2FeedHeroView`、`Babel2FeedSearch`、`Babel2AddSubscriptionViewController`、`Babel2PositionStore`、`Babel2SyncSpinner`、`Reader/Babel2ReaderToolbarView`、`Reader/Babel2ArticleViewController`、`Reader/Babel2ImageViewerViewController`、`Reader/WebKit/Babel2BrowserViewController`、`Settings/Babel2SettingsComponents`、`Settings/Babel2SettingsPages`、`Settings/Babel2SettingsEditors`。
- 测试：新增 `testUnifiedIconSetAcrossBars`（取代 ADR-052 的底栏视觉修正测试），改 3 项（星标图标名、阅读模式末道线比例下限、刷新圆底取样点）。用临时测试让 App 自己画出全部 47 个图标、阅读页底栏、长按菜单（浅 / 深）核对后删除。反向验证：图标色改回旧灰、角标挪位 → 测试失败，恢复后 `cmp` 一致。全量 216/216、UI Driver 1/1（VALIDATION）。
- 只能真机确认：各处图标的大小和轻重（尤其菜单 20pt、首页入口 18pt、顶栏 22pt）、深一档的颜色在真机上的感觉。

## 第六轮：跨源列表长按文章 + 菜单高亮圆角（2026-09-27，ADR-063 / 064；用户同日真机验收通过，已提交推送）

- **长按文章的来源菜单（ADR-063）**：`Babel2LibraryViewControllers.swift`（`Babel2ArticleSourceActions`、跨源列表长按、菜单、改名同步、取消订阅后原地拿掉）；`Babel2SceneComposition.swift`（跨源入口接线）；`Babel2Localization.swift` + xcstrings（+2；取消订阅确认文字换成「包括加过星标的」）。
- **菜单高亮圆角（ADR-064）**：`Babel2GlassMenu.swift`（`Babel2GlassCard` 圆角常量、菜单行高亮圆角 16）；`Settings/Babel2SettingsComponents.swift`（设置页弹出选单行同样）。
- 测试：新增 3 项（来源菜单行为、来源菜单接线、菜单高亮圆角）。反向验证 5 处改坏 → 对应测试均失败，恢复后 `cmp` 一致。全量与 UI Driver 见 VALIDATION。
- 2026-09-27 用户真机验收：「编译好了，验收没问题，提交并推送」（口头确认，未逐条说明）。验收前用户 Xcode 报「Missing package product Zip / Tidemark」：其 DerivedData 当天重建、没有 SourcePackages，与代码无关；按 File → Packages → Resolve Package Versions 解决。一个提交，不含 pbxproj 签名 diff、`Shared/Localizable.xcstrings` stale 行、`icon new/`。

## 第五轮：长按手感 + 编辑订阅源（2026-09-27，ADR-060～062；用户同日真机验收通过，已提交推送）

- **长按手感（ADR-060）**：新文件 `Babel2LongPress.swift`；`Babel2RootViewController.swift`（首页各档列表换用新手感）、`Reader/Babel2ImageViewerViewController.swift`（长按分享）、`Babel2GlassMenu.swift`（`pops` 弹性展开）。
- **编辑订阅源（ADR-061）**：新文件 `Babel2FeedEditViewController.swift`；`Babel2LibraryEditing.swift`（接口换成 `setFeedFolders` + `feedURL`，长按菜单改为编辑 / 图标 / 取消订阅，删掉移动 / 移出 / 重命名三段）；`Babel2LibraryViewControllers.swift`（列表页「更多」的「编辑」）；`Babel2SceneComposition.swift`（接线）；接入层 `Babel2LiveDataAdapters.swift`（`setFolders`，删掉 `moveFeed` / `removeFeed(fromFolder:)`）；文案 +5 / −4（`Babel2Localization.swift`、`Babel2Localizable.xcstrings`）。
- 测试：新增 6 项（长按手感、图片长按、编辑页流程、编辑规则、列表页编辑入口；首页长按订阅源改写），改 1 项（真实账户文件夹生命周期改测放进 / 两个 / 回到最外层）。反向验证 6 处改坏 → 对应 6 项失败，恢复后 `cmp` 一致。全量 212/212；UI Driver 见 VALIDATION。
- **追加（ADR-062）**：文章列表顶部刷新按钮去掉箭头自带的灰色圆底（`iOS/BabelUI/BabelFeedsViewController.swift` 的 `BabelSyncGlyphView` 加开关、默认不变；`Babel2SyncSpinner.swift`、`Babel2FeedHeroView.swift`）；清掉 10 个并发检查警告（`Settings/Babel2SettingsComponents.swift`、`Babel2Type.swift` 各加 `@MainActor`）。新增测试 1 项（画出来核对圆底有无），反向验证 2 种改坏均失败。
- 2026-09-27 用户真机验收：「验收没问题，提交并推送」（口头确认，未逐条说明）。一个提交，不含 pbxproj 签名 diff、`Shared/Localizable.xcstrings` stale 行、`icon new/`。未单独确认：真实同步账户（非本机）上的多文件夹。

## 第四轮 6 条反馈（2026-09-27，ADR-054～059；用户同日真机验收通过，与第三轮分两个提交推送）

- 与上一轮（ADR-052 / 053，同样未提交）改在同一批文件里；动手前把上一轮的工作区拍了本地快照 `refs/babel2/round3-pending`（= `a445bbb85`，含未跟踪的 `Babel2PositionStore.swift`；不是提交、不推送），以后两轮可分开提交。
- **1 摘要（ADR-054）**：标题 + 摘要合计 3 行。改 `Babel2Type.swift`（`rowTextLines` / `rowTitleMaxLines`）、`Babel2LibraryViewControllers.swift`（`Babel2ArticleCell` 算标题行数定摘要行数）。
- **2 启动与回到上次（ADR-055）**：启动画面改空白纸色（`iOS/Base.lproj/LaunchScreen{Phone,Pad}.storyboard`，新颜色资源 `iOS/Babel2/Assets.xcassets/Babel2LaunchBackground.colorset`）；新文件 `Babel2LastPlace.swift`（位置规则、存储、纸色底板）；`Babel2SceneComposition.swift`（退后台记、冷启动搭回、不带动画推入）；`iOS/SceneDelegate.swift` 一行（传 `lastPlace: .shared`）；列表页 / 阅读页各加只读编号与「恢复时打开文章」回调。
- **3 图标（ADR-056）**：两套 appiconset 各换 3 张 PNG（文件名不变）；着色版为 Mono 反色。
- **4 正文色（ADR-057）**：`Reader/WebKit/Babel2ReaderContentView.swift` 正文 / 引用 `--body`（浅 #626262 / 深 #B4B4B4）、图注 `--caption`。
- **5 档位叠字（ADR-058）**：`Babel2ScopeFilterControl.swift` 新增 `Babel2ScopeButton`，图文位置自己算。根因未在模拟器复现（LESSONS 59）。
- **6 全文缓存（ADR-059）**：新文件 `Reader/Babel2FullTextCache.swift`；`Reader/Babel2ArticleViewController.swift`（打开即用存的全文、手动开阅读模式先查缓存、抽成功就存）；`Babel2SceneComposition.swift` 传 `.shared`。
- 测试：新增 6 项（摘要三行、正文对比度、档位图文不重叠、全文缓存、位置读取、冷启动回到上次），改 3 项（摘要行数、正文色取值、档位图标取法）。反向验证 6 处改坏 → 对应 6 项全部失败，恢复后 `cmp` 一致。全量与 UI Driver 见 VALIDATION。
- 2026-09-27 用户真机验收：「验收没问题，分两个提交并推送」（口头确认，未逐条说明）。第三轮、第四轮各一个提交（第三轮内容取自快照 `refs/babel2/round3-pending`），不含 pbxproj 签名 diff、`Shared/Localizable.xcstrings` stale 行、`icon new/`。

## 位置记忆与底栏统一（2026-09-27 用户第三轮反馈，ADR-052 / 053；用户同日真机验收通过，已提交推送）

- **底栏图标统一（ADR-052，第 4、5 条）**：首页 / 文章列表 / 阅读页三条底栏同一比例（21pt 画布）+ 视觉修正（圆 0.86、向下箭头 0.85、翻译符号 11.5pt）；首页 / 列表的星与横线从 24pt 缩到与阅读页一样；「全部已读」的勾改为镂空（以前被同色吞掉）。改 `Babel2Type.swift`、`Reader/Babel2ReaderToolbarView.swift`、`Babel2ScopeFilterControl.swift`、`Babel2StatusIcons.swift`（翻译符号按新字号画）、`Babel2LibraryViewControllers.swift`。改前 / 改后对比图已发给用户。
- **位置记忆（ADR-053，第 1～3 条）**：新文件 `Babel2PositionStore.swift`（本机存储 + 「↑ N 篇新文章」胶囊）；文章列表按「最上面那一篇」记与恢复、三档共用、今日未读 / 全部未读共用、新文章提示；文章里按段落记与恢复（全文晚到、译文放回、图片加载后都再对一次，用户一滑就停）。改 `Babel2LibraryViewControllers.swift`、`Reader/Babel2ArticleViewController.swift`、`Reader/WebKit/Babel2ReaderContentView.swift`（两段查位置的脚本）、`Babel2SceneComposition.swift`（注入）、文案 +3。翻译按用户选择不自动接着翻。
- 真实数据 UI Driver 两次失败，各抓到一个真问题，均已修并补测试：①换成第一篇时大图被误收起（LESSONS 57）；②没往下滑就离开也被记成「最上面那一篇」，换一档再开时列表被滚到中间；顺带查出「新文章」跨档比会误报（LESSONS 58）。规则随之补充（ADR-053 补充）：没滑动过下次从顶部开始；「新文章」每档各记各的、只跟同一档比，没记过不提示。UI 测试启动时带 `BABEL2_RESET_READING_POSITIONS=1` 清空记住的位置。
- 测试：新增 9 项（底栏图标统一、文章里记与恢复、全文晚到后恢复、列表记与恢复 + 新文章提示、找回规则与共用键、今日未读 → 全部未读接着看、换成第一篇时回到展开的顶部、没滑动过下次从顶部开始、新文章只跟同一档比）。反向验证：关掉文章恢复 / 列表恢复 / 新文章提示后对应 4 项失败；关掉「停在顶部」「分档记新文章」后对应 3 项失败；恢复后通过。全量与 UI Driver 见 VALIDATION。

## 用户 11 条反馈：调查结论与分批（2026-09-27，ADR-036；五批 + 验收追加已分 6 个提交推送 `f194862bd`…`ff95ddab3`）

### 验收中追加（2026-09-27 第二轮，ADR-048～051；已提交推送 `ff95ddab3`）

- **图片查看器（ADR-051）**：直角、无描边；横图贴满屏幕两边（小横图也放大到整宽），竖图 / 方图照旧留白居中。改 `Reader/Babel2ImageViewerViewController.swift`；测试更新 2 项（规则：横图整宽 / 竖图留白 / 横屏按高度缩；实际弹出：直角、4:3 图整宽），反向验证：横图改回旧规则后两项均失败。
- **问答：不管选什么模型都不输出思考过程？（ADR-050）** 用 OpenRouter 时是：要求不思考、关不掉的也别回传，思考内容本来就在单独字段、从不当译文。补上一个缺口：别的服务商若把思考写在回复开头（`<think>…</think>`），以前会进译文 / 流式先闪出来、标题翻译会抠错数组——现在回复开头的思考段一律去掉。改 `Shared/Translation/OpenAICompatibleTranslator.swift`、`NNWTitleTranslationController.swift`（macOS 干净副本 build 通过）。
- **点标题进原文 + 整页往左划进原文（ADR-048）**：大标题（和收起后的小标题栏）点一下 = 与划过去同一段整页滑入；往左划从右边缘扩大到整页任意位置（与整页右滑返回对称，竖滑、横向滚动区不受影响；正文滚动不再等它）。MOTION-CONTRACT §4 / §7 按用户要求修订。改 `Reader/Babel2ReaderBrowserMotion.swift`、`Reader/Babel2ArticleViewController.swift`。
- **图标（ADR-049）**：阅读模式去掉纸页外框、只留四道横线（最后一道略短）；翻译改回系统翻译符号（原样复用 1.x `NNWTranslateIcon`），右下角实心 / 空心小圆点表示完整 / 翻到一半的译文缓存。改 `Babel2StatusIcons.swift`。
- 测试：新增 5 项（整页左滑开始条件、点标题进原文、思考段去除规则、真实流程里思考不上页面、标题翻译不被思考里的方括号干扰），更新 1 项（图标：角标与横线）。反向验证：关掉思考过滤 / 点标题后对应 4 项失败，恢复后通过。全量 `scratchpad/r2-full.xcresult` 190/190；UI Driver（Release、真实数据）`scratchpad/r2-ui.xcresult` 1/1；macOS 干净副本 build 通过（第 1 次为已知 SecretKey）。

调查只读、未改产品代码；第 7 条用临时探针测试（假翻译服务，不联网）取证，测试已删除。
- **7 长文翻译**：① 已复现——Babel 2.0 切阅读模式 / 重试是在**同一网页里重排**，翻译脚本（translation.js 的 `window.nnwTranslation`）不重置，仍记着上一版正文与「在显示译文」：重排后点「原文」回到摘要，点「翻译」可能直接还原成英文。② 已复现——「总是阅读模式」的源，全文未到时点翻译，全文一到 `startRendering` 调 `resetForNewArticle` 取消翻译，页面显示英文全文、按钮回「原 翻译」。③ 机制已证实、设备上未证实——模型少还段落或超时，整组被拒收保持英文；重试发同一大组（≤4000 字 / 6 段），易再失败；非流式请求 60 秒超时。④ 模型返回「标签在、文字空」（如 `<p></p>`）时 `applyGroup` 照收、自检也不报——会得到「状态已译 + 正文空白」，且标题译文为空时原生标题保持英文，与截图 7 症状一致（推测，未在设备上证实）。空白未在模拟器复现。长文正常路径（约 3 万字符）通过。
- **9 模型列表**：`OpenRouterCatalog.canonicalMap` 后写覆盖，89 个带日期 id 映射到被过滤的 `:batch`/`:free` 变体，正主热度为 0（DeepSeek V4.1 Flash 实为 OpenRouter 用量第 1）；厂商只取 10 家、无热度按字母排，xiaomi 被截；缓存仅在为空时自动刷新。已用 2026-09-27 实时数据核对。
- **8 图标**：`Babel2LiveIconCache` 只在内存，冷启动为空；上游下载器硬盘缓存异步回来逐个发通知，首页每次都取消重建（与同步通知叠加）——「慢几秒」原因为推测、未实测。已打开的文章列表 / 阅读页不更新图标（`Babel2LibraryViewControllers.swift` 懒加载一次）。
- **其余**（1 播客/YouTube、2 整页右滑、3 图片查看、4 文件夹与重复源、5 未读入口、6/11 图标、10 浏览器）：原因与方案见 ADR-036 与 HANDOFF；工作底稿不在仓库。

### 第 1 批：长文翻译 / 模型列表 / 冷启动图标（ADR-037～039；实现与自动化完成，待用户真机验收，未提交）

- **翻译（ADR-037）**：重排前后清空翻译脚本状态；全文未到时点翻译先排队（「生成中」），全文排好自动翻；正在看译文时切阅读模式自动接着翻；失败组拆单段重翻；组上限 2500、超时 120 秒；空白译文拒收 + 翻完 / 缓存恢复后空白兜底。改动：`Shared/Translation/`（TranslationController、translation.js、NNWArticlePageHost、TranslationCache、OpenAICompatibleTranslator）、`Reader/WebKit/Babel2ReaderContentView.swift`、`Reader/Babel2ArticleViewController.swift`。
- **模型列表（ADR-038）**：修变体吃热度；热度改用量榜；12 家 × (最热 3 + 最便宜 2)；行尾价格；超过 3 天自动刷新；目录缓存 v4。改动：`OpenRouterCatalog.swift`、`Settings/Babel2SettingsService.swift`、`Babel2SettingsEditors.swift`、`Babel2SettingsComponents.swift`（选择行可带行尾小字）、`Babel2LiveSettingsService.swift`、Babel2 字符串 +1（≈%@ per article）。
- **冷启动图标（ADR-039）**：图标备份落盘（缩到 96px）；首页后台重载合并不打断；文章列表 / 阅读页补上晚到的图标。改动：`Babel2LiveDataAdapters.swift`（Babel2LiveIconCache）、`Babel2RootViewController.swift`、`Babel2LibraryViewControllers.swift`、`Babel2FeedHeroView.swift`（窄栏 setIcon）、`Babel2SceneComposition.swift`。
- 测试：新增 10 项（翻译 6：重排清状态、排队翻全文、切阅读模式接着翻、失败组拆单段、空白拒收、脚本两道闸；模型 1：变体不吃热度 + 用量榜；图标 3：重载不被打断、备份落盘缩图、列表补图标），改 1 项（模型排行新规则 + 行尾价格 + 过期判断）。反向验证：关掉「清状态 / 拆组 / 排队 / 空白两道防线 / 合并重载」后对应测试均失败，恢复后通过。全量 `scratchpad/b1-full.xcresult` 163/163（上一轮 153 + 10）；UI Driver（Release、真实数据）`scratchpad/b1-ui.xcresult` 1/1；pbxproj diff hash 仍 `c5f5a8cf…`。另用临时探针以当天真实 OpenRouter 数据跑新排行（已删除）。
- 未能自动验证：真机真实模型下的长文翻译（是否还会空白 / 部分英文）、价格显示、冷启动图标实际快慢——真机验收。

### 第 2 批：图片查看 / 播客与 YouTube / 整页右滑（ADR-040～042；实现与自动化完成，待真机验收，未提交）

- **图片（ADR-040，第 3 条）**：点正文里的图（大于 24pt）不再跟着外层链接进浏览器，改为居中弹出的卡片查看器：双指缩放（最大 4 倍）、双击放大 2.5 倍、单击 / 下拉 / ✕ 关闭、长按分享、背景随深浅色；图外层原本有链接的，右下角「打开链接」。新文件 `Reader/Babel2ImageViewerViewController.swift`；`Reader/WebKit/Babel2ReaderContentView.swift`（捕获点击、快照起点）。
- **播放器（ADR-041，第 1 条）**：YouTube 文章正文上方 16:9 贴满两边的播放器（原地播放），简介填进正文可翻译；播客正文上方居中音频条（最宽 520pt）。正文自带的视频贴满两边。新文件 `Reader/Babel2ArticleMedia.swift`；接入层复用 1.x `YouTubeDescriptionLoader` / `PodcastEpisodeLocator`；边界测试加精确例外（只允许阅读页网页文件出现系统配置类型名，用户批准）。
- **整页右滑（ADR-042，第 2 条）**：二级页任意位置往右横滑即返回（竖滑不受影响、横向滚动区先滚自身）；内置浏览器仍只认左边缘。MOTION-CONTRACT 三处按用户批准修订。改动 `Babel2NavigationPopMotion.swift`。
- 测试：新增 6 项；全量 `scratchpad/b2-full.xcresult` 169/169。

### 第 3 批：阅读模式与翻译图标（ADR-043；实现与自动化完成，待真机验收，未提交）

- 阅读模式「纸页」、翻译「文/A」（第 6、11 条，方案 B / A）：平时线条；进行中图标本身在动；成功是墨色方块底 + 反白；失败轻晃 + 小胶囊。标题下「正在获取全文…」去掉。文章列表底栏标题翻译开关同步换新图标。新文件 `Babel2StatusIcons.swift`；删除 `Reader/Babel2TranslationToggle.swift`；改 `Babel2ReaderToolbarView.swift`、`Babel2ArticleViewController.swift`、`Babel2LibraryViewControllers.swift`。
- 测试：三态映射替换原 Figma 文字状态测试；工具栏几何改为 44×44；全量 `scratchpad/b3-full.xcresult` 168/169（唯一失败是几何断言仍是旧的 58×44，更新后 `t3b.xcresult` 通过，已并入第 5 批后的最终全量）。

### 第 4 批：首页跨源入口 / 文件夹整理 / 自定义图标（ADR-044～046；实现与自动化完成，待真机验收，未提交）

- **跨源入口（ADR-044，第 5 条）**：首页顶部「今日未读 / 全部未读 / 外文源」（全部档「今天 / 全部文章 / 外文源」，星标档「全部星标」），可点开跨源文章列表；外文源自动识别 + 「更多」里手动改。新文件 `Babel2SmartFeedEntries.swift`；Babel2Core 契约 / 快照扩展；接入层计数与取文章；`Babel2RootViewController.swift`、`Babel2LibraryViewControllers.swift`、`Babel2SceneComposition.swift`、`Babel2AppAssembly.swift`。
- **文件夹整理（ADR-045，第 4 条）**：首页长按文件夹 / 订阅源弹整理菜单；「+」改为「添加订阅 / 新建文件夹」；删除文件夹二选一；「移到文件夹」「从这个文件夹移出」；菜单顶部写明在哪个账户 / 文件夹、也在哪里（解释「重复」）；空文件夹也列出；回到首页 / 切档时补上错过的数据变化；毛玻璃菜单过长时可滚。新文件 `Babel2LibraryEditing.swift`；接入层 `Babel2LiveLibraryEditing`（在 `Babel2LiveDataAdapters.swift` 内，账户单例只准出现在这个文件）。
- **自定义图标（ADR-046，第 8 条后半）**：「更换图标…」「恢复默认图标」（首页长按、文章列表「更多」）；裁正方形最多 512px 存在手机上；首页 / 列表 / 阅读页 / 大图都优先用它。新文件 `Babel2Integration/Babel2LiveCustomFeedIcons.swift`；`Babel2FeedHeroView.swift`（大图淡出）。
- 测试：新增 12 项（入口跟档位与计数、跨源列表来源 / 批量已读 / 状态刷新、长按文件夹、长按订阅源、「+」菜单、回首页补刷新、切档补刷新、菜单可滚、裁图、图标存取、列表页换图标、真实账户文件夹生命周期），改 2 项（「+」先弹菜单）。反向验证：关掉「回首页补刷新 / 切档补刷新 / 空文件夹显示 / 自定义图标优先 / 菜单封顶」后对应测试均失败。第一次全量 `scratchpad/b4-full.xcresult` 180/181：边界测试抓到新文件用了账户单例，已并回指定文件（LESSONS 50）。

### 第 5 批：内置浏览器去广告与翻译此页（ADR-047；实现与自动化完成，待真机验收，未提交）

- 浏览器右上角「•••」：翻译此页 / 去广告（默认开，可对当前页临时关）。去广告用系统内容拦截（只拦第三方广告 / 跟踪域名 + 隐藏广告空位）；翻译此页在当前网页里用 Readability 抽正文，开独立阅读页自动翻译（没有已读 / 星标 / 下一篇 / 阅读模式）。新文件 `Reader/WebKit/Babel2AdBlocker.swift`；改 `Reader/WebKit/Babel2BrowserViewController.swift`、`Reader/Babel2ArticleViewController.swift`（独立网页模式、打开即翻）、`Babel2SceneComposition.swift`（浏览器工厂、网页阅读页）、接入层 `Babel2LiveWebPageArticle`（临时文章对象，不进数据库）。
- 测试：新增 4 项（规则编译与匹配、「•••」菜单与开关、抽正文 → 独立阅读页自动翻译、没有正文时说明原因）。反向验证：关掉「自动翻译 / 独立网页模式」后测试失败。
- **五批 + ADR-035 最终验证**：全量 `scratchpad/final-full.xcresult` 185/185（本会话开始时 153）；UI Driver（Release、真实数据）`scratchpad/final-ui.xcresult` 1/1；Babel2UI package 32/32；pbxproj diff hash 仍 `c5f5a8cf…`。

## 阅读页上拉翻到下一篇（2026-09-26，ADR-035；实现与自动化完成，待用户真机验收，未提交）

- 用户设计：读到底继续上拉，底部出现一个浅色、很扁的向下 ∨；越拉越扁、越深，拉过 80pt 正好成一条横线（墨色）并轻震一下，松手进入下一篇。
- 细节（用户同意）：只在往上越过临界点时震一次；越过后往回拉 ∨ 弯回变浅、松手不翻；∨ 水平居中（与底栏 ∨ 同一竖线），位于正文末尾与底部之间的空白正中；最后一篇不显示 ∨，只普通回弹；不显示下一篇标题；不做顶部下拉回上一篇；短文章直接上拉也能翻；翻篇走与底栏 ∨ 相同的路径与过渡。
- 实现：新文件 `iOS/Babel2/Reader/Babel2ReaderNextPull.swift`（纯规则 + 画 ∨ 的视图）；`Babel2ArticleViewController.swift` 只监听滚动与松手（不新增手势识别器，不与右滑返回 / 右缘进浏览器抢手势）；惯性甩到底的回弹不显示 ∨；没过线松手时 ∨ 随回弹慢慢收回。
- 测试：新增 2 项（形状 / 颜色 / 临界点 / 松手判定 / 长短文章的「底」；阅读页过线且有下一篇才翻、最后一篇不显示）。全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/pull-full.xcresult` 153/153；UI Driver `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/pull-ui.xcresult` 1/1；pbxproj diff hash 仍 `c5f5a8cf…`。
- 未能自动验证：真实手指拖动的手感、震动、∨ 的位置与颜色变化——真机验收。

## 全 App 动效第二、三批（2026-09-26，ADR-034；2026-09-26 用户真机集中验收通过，已提交并推送）

- 用户要求两批连做、与第一批（字号，ADR-033）一起集中验收。
- 新文件：`Babel2Motion.swift`（三种时长 0.15 / 0.22 / 0.32、统一 ease-out、减弱动态效果、按压反馈、依次浮现）、`Babel2SkeletonView.swift`（呼吸占位条）、`Babel2SyncSpinner.swift`（同步箭头缓起缓停，只借用 1.x 的图形、不改 1.x 文件）。
- 第二批：按压反馈（全部图标按钮按下缩到 94%，减弱动态效果时改为变淡）；已读 / 星标 / 阅读模式图标交叉淡入、星标点亮轻放大；「原 / 译」开关文字交叉淡入；文章列表切档改为旧列表截图 → 新列表交叉淡入并错开 12pt（不再闪「加载中」）；首次进入列表首屏依次浮现；缩略图下载完淡入；首页切档与选中胶囊统一到 0.22 秒 ease-out；「下一篇」改为旧页上移 24pt 淡出、新页从下方 40pt 升起。
- 第三批：刷新后原有文章平滑下移、新文章从上方滑入；读过后标题变细交叉淡入；首页文件夹展开 / 收起（箭头旋转 90°、子行依次浮现、收起时淡出）；首页与文章列表加载中改为呼吸占位条（0.2 秒内加载完不出现）；进入 / 退出搜索交叉淡入、底栏滑出滑回；阅读页切换阅读模式时旧画面淡出、译文标题到达交叉淡入；提示胶囊上浮 8pt 淡入；同步箭头开始加速、停止时减速转到正位，首页的箭头与「正在同步…」淡入淡出；毛玻璃菜单从按钮一侧展开、选项按下底色淡入。
- 自查修掉 2 个问题：① 系统拍不到截图时，切档会把列表藏起来却不再恢复（改为拍不到就不做过渡）；② 按下档位按钮时选中胶囊跟着缩小一圈（改按按钮原大小定位；已反向验证测试能抓到旧写法）。
- 测试：新增 6 项（时长与减弱动态效果、切档过渡不藏列表、文件夹展开收起与箭头、菜单展开中心、同步箭头、按下时胶囊不缩）。全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/motion-full.xcresult` 151/151；UI Driver `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/motion-ui.xcresult` 1/1；pbxproj diff hash 仍 `c5f5a8cf…`。
- 未能自动验证：所有动画的观感与节奏、真机帧率、减弱动态效果打开后的实际表现——真机验收。

## 全 App 字号收小一档 + 底栏等距（2026-09-25，ADR-033，第一批；2026-09-26 用户真机集中验收通过，已提交并推送）

- 用户要「高级感 / 克制」，先看了对比预览（https://claude.ai/artifact/6h7JtWBfVcfjqKtqsPrQzi）后确认。**设置页不在范围内**（仍按它的 Figma 规格）。
- 新文件 `iOS/Babel2/Babel2Type.swift`：全 App 字号、图标尺寸、底栏位置的唯一出处（`Babel2Type` / `Babel2BarLayout`）。
- 首页：大标题 36→28；「全部未读 / 文件夹」20→16；文件夹行 18 半粗→16 中等；订阅源行 17→16 常规；未读数 17/18→14；源图标 24→20（中心不动）；右上 + 与齿轮略小。
- 文章列表：大图标题 28 粗→24 半粗；窄栏标题 17→16；日期分段 14→12 半粗；来源 12→11、时间 13→12；标题 17→15.5（行高 22→20）；摘要 17→14.5；源图标 24→20；缩略图 70→64；行上下留白 14→16；搜索框 16→15。
- 阅读页：标题 34 粗→27 半粗（行高 33、字距 -0.4）；正文 19/30→17/28；段距 20→18；小标题 23/21/20/19→20/18/17/17；图注、表格、代码各小 1pt；顶栏图标 24→19；底栏图标 24→21；收起小标题栏 13/16→12/15；快照（长图）标题同步。
- 网页浏览页：标题 15→14，底栏符号 19→17。添加订阅页：页标题 24→20（仅此页，设置页不变）、结果 16/13→15/12、搜索框 16→15。毛玻璃菜单：选项 16→15、行高 48→44、顶部说明 13→12。
- **底栏等距**：首页 / 文章列表 / 阅读页 / 网页四条底栏统一为 x = 32 / 116.5 / 201 / 285.5 / 370（原 Figma 32 / 104 / 201 / 290.5 / 362，间距 72/97/89.5/71.5 不均）；首页三档 116.5 / 201 / 285.5；全部同一条中线 y=24。「原 / 译」开关文字下移 1pt 与图标视觉对齐。
- 测试：更新 4 处旧数字（图标 20、缩略图 64、行高公式、阅读页底栏位置），新增 1 项（文章列表底栏五个控件等距同中线）并在阅读页底栏测试里加对称 / 等距 / 同中线断言。Feed/Reader 类 77/77；全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/rall.xcresult` 145/145；UI Driver `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/rui.xcresult` 1/1；pbxproj diff hash 仍 `c5f5a8cf…`。
- 未能自动验证：整体观感（字是否太小、层级是否清楚）、深色模式、底栏视觉是否真的均匀——真机验收。
- 未改：首页同步转圈图标（1.x 文件里按 24pt 写死坐标，不在本批范围）。

## 用户反馈四项修正（2026-09-25，ADR-032；2026-09-26 用户真机集中验收通过，已提交并推送）

1. **大图按钮看不清**：返回 / 刷新 / 搜索 / 更多下加 36pt 毛玻璃圆底（systemUltraThinMaterial），随收缩进度淡出；大图顶端状态栏高度加淡纸色渐变（0.72→0.4→0），保证时间与信号可读。
2. **界面语言「跟随系统」**不再带括号里的系统语言名（原「跟随系统（简体中文（日本））」）。
3. **全 app 弹出菜单统一为毛玻璃**：新文件 `Babel2GlassMenu.swift`（`Babel2GlassCard` 共用外观 + 通用菜单：图标、开关勾、红色危险项、分组细线、顶部说明、不可用变灰、按钮下方放不下改上方）。替换阅读页「•••」、大图「•••」、「全部标为已读」确认（原系统动作单）。屏幕中间的确认 / 输入对话框保留系统样式（用户同意）。
4. **切回前台图标重新加载**：原因是上游图标 / 图片下载器在 app 进后台时清空**内存**缓存（刻意省内存，硬盘缓存仍在），首页刷新那一刻拿不到图标先空白。接入层新增 `Babel2LiveIconCache` 记住每个源最后一次的小图标，进后台不清、仅内存警告时清；上游零改动。已查其它缓存：文章缩略图（自有缓存）与大图高清图标（自带硬盘 + 内存缓存）不受影响。
- 测试：更新 3 项（菜单改为自有数据结构后的断言、确认改为毛玻璃菜单、圆底随进度淡出），新增 2 项（图标备份进后台不清、「跟随系统」无后缀）。全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/fb-full.xcresult` 144/144；UI Driver `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/fb-ui.xcresult` 1/1。
- 未能自动验证：真实订阅源切后台再回来图标是否不再闪（测试环境无法构造真实订阅源对象）、毛玻璃圆底与菜单观感、深色图上的状态栏可读性——真机验收。

## 文章列表大图的刷新与更多（Slice 3，ADR-031；2026-09-25，用户真机验收通过，已提交并推送 `44c5beb75`）

- 位置照 Figma：窄栏层顶行 刷新 x=201（复用首页同步图标，平时静止可见、同步时旋转）、放大镜 x=330、更多 x=370（复用 Babel2ReaderMore）。没有注入操作时两个按钮不显示。
- 刷新：刷新所有账户（同步按账户进行，无法只刷新一个源）；同步中副标题「正在同步…」（辅助功能值仍为纯数字，UI Driver 依赖）；**用户亲手点刷新**时，同步结束（最多等 2 分钟）后重新加载列表并保持滚动位置，新文章出现在顶部；后台自动同步只转箭头、不重载。
- 更多菜单（每次打开按当前状态生成）：打开网站主页（无主页不显示；按「打开链接」设置用内置或系统浏览器）、拷贝订阅地址、此订阅源总是用阅读模式（勾）、新文章通知（勾，打开时请求系统通知权限）、重命名（输入框；成功后大图/窄栏/行来源名同步）、取消订阅（红色，先确认，只移除这个账户里的这个源，成功后返回首页）。
- 接入层：`Babel2LiveDataAdapters.swift` 新增 `Babel2LiveFeedActions`（refreshAllWithoutWaiting、refreshInProgress、homePageURL、feed URL、newArticleNotificationsEnabled、renameFeed、removeFeed）。
- 顺带修复：英文「1 articles」→ 单数「1 article」。
- 验证：测试 +2（按钮位置与无注入时隐藏、菜单 6 项与勾选状态、无主页不显示打开网站、重命名同步显示；刷新调用、同步中显示与纯数字辅助值、同步结束后重载出新文章并停止）。反向验证：去掉重载后测试失败。全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/more-full.xcresult` 142/142；UI Driver `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/more-ui.xcresult` 1/1。
- 未能自动验证：真实同步与新文章、通知权限弹窗、重命名 / 取消订阅对真实账户的写入、菜单观感——真机验收。

## 添加订阅页（Slice 6，ADR-030；2026-09-25，用户真机验收通过，已提交并推送 `06d2dd41c`）

- 首页「+」打开新页面 `Babel2AddSubscriptionViewController`（替换占位页，沿用恢复标识 babel2.add-subscription）。Figma 无设计稿，样式按列表搜索框与设置行近似。
- 沿用 1.x 发现页用户决定：一个搜索框（网址直连对应类型；关键词并行搜网站 / 播客 / YouTube / Reddit，按此顺序分组，网站默认展开、其余收起，组标题可点收起/展开）；一类失败不影响其它，每组显示自己的说明（无结果 / 未配置 Key〔指向 设置 → 订阅与发现〕/ 限流 / 网络错误）；顶部「订阅到」（设置页同款弹出选单，默认第一个位置、不记住）；点行试读（复用 1.x 试读页，底部卡片）；行尾 ⊕ 订阅、灰色实心勾 = 已订阅（再点先确认后取消）；订阅后留在本页。按键盘「搜索」才搜（多类联网、第三方额度有限）。
- 接入层：新文件 `Babel2LiveSubscriptionService.swift`（发现引擎、常见错误中英文化、试读桥接、保留原始结果供试读）；`Babel2LiveDataAdapters.swift` 新增 `Babel2LiveSubscriptions`（订阅位置、是否已订阅、createFeed、跨账户 removeFeed）。
- 顺带修复：首页数据层未监听「订阅源增删」（ChildrenDidChange），订阅 / 导入 OPML / 删除账户后首页不刷新——已加监听，订阅与取消订阅后也主动通知刷新。
- 文案 +26 条中英文（1.x 发现引擎中未映射的少数错误说明仍为中文原文）。
- 验证：测试 +3（「+」进入与路由恢复；分组与组内说明、收起展开、默认位置与改位置、订到所选位置并留在本页、已订阅状态、取消订阅调用；真实实现粘贴 Reddit 版块网址不联网给出 Reddit 组）。全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/add-full.xcresult` 140/140；UI Driver `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/add-ui.xcresult` 1/1。
- 未能自动验证：真实联网搜索四类、真实订阅写入与首页刷新、试读卡片、取消订阅、未配置 Key 提示、观感——真机验收。

## 文章列表搜索（Slice 3，ADR-029；2026-09-25，用户真机验收通过，已提交并推送 `ce0a42c6b`）

- 入口：窄栏层右上角放大镜（Figma 搜索位 x=330，全程不动）。点按原地进入搜索：大图收成窄栏、第二行换成搜索框 +「取消」（新文件 `Babel2FeedSearch.swift`；Figma 无搜索界面稿，样式按设置页输入框近似，用户同意）、列表顶 70pt 垫片暂时去掉、底栏隐藏、键盘弹出。
- 搜索：停止输入 0.25 秒后搜；空搜索框显示原列表；旧搜索取消只显示最新结果；结果沿用文章行与按天分组；无结果显示「没有找到与「xxx」相关的文章」，出错显示「搜索失败」；拖动结果收起键盘。下一篇按结果顺序；点结果进阅读页返回仍在结果里。
- 取消：恢复原列表、底栏、滚动位置与大图进度，并补一次状态原地刷新。
- 数据：`DataProviding.searchFeedArticles`（Core 默认实现：标题/译文标题/摘要包含匹配）；接入层正式实现在该源**全部文章**（不分档）里合并两路：数据库全文搜索（标题 + 正文）+ 标题/译文标题/摘要包含匹配（全文搜索按空格分词，中文整句常搜不到）。
- 验证：测试 +1（进入搜索窄栏与底栏状态、结果不分档、无结果说明、取消恢复列表/底栏/滚动位置）。全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/srch-full.xcresult` 137/137；UI Driver `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/srch-ui.xcresult` 1/1。
- 未能自动验证：真实数据库全文搜索（需要真实账户数据）、中文搜索、键盘交互与观感——真机验收。
- 追加修复（用户真机反馈三点）：① 放大镜被输入框横向拉长变形——未定尺寸，改为固定 16×16、按比例显示；② 搜索结果列表「下滑失灵」——排查（模拟器探针：触摸确实落在列表、内容足够长、代码设滚动正常）后确认是大图的「松手补完」在搜索时仍生效，拖一小段松手即被拉回顶部，搜索时关闭补完；并在键盘弹出时列表底部让出键盘高度；③ 搜索框 × 改为有字即常驻（.always）。测试补断言（搜索时拖 20pt 松手目标不变、放大镜 16×16 且宽高比≈1、× 常驻）；反向验证：去掉搜索判断后断言失败（被拉回 -153）。全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/srch-full2.xcresult` 137/137。

## 设置页（Slice 6，ADR-028；2026-09-25，用户真机验收通过，已提交并推送 `1908f1f02`）

- 入口：首页左上角齿轮（x=32，与右上「+」对称）→ 设置首页（沿用恢复标识 babel2.settings）。
- 新目录 `iOS/Babel2/Settings/`：Style（Figma 数值与颜色）、Components（导航栏 Root/Back/Editor、分组标题、Disclosure/Value/Select/Toggle/Action/Choice 行、文本框、38×22 开关〔开=强调色，ADR-008〕、Thick Glass 弹出单选菜单〔宽 272、圆角 22、顶边=触发行下沿+39〕）、Service（页面唯一依赖的接口 + 模型排行纯计算）、Pages（首页 8 类 + 文章列表/阅读器/翻译/外观与语言/通知/支持与诊断）、AccountPages（账户与同步/账户详情/新增账户/订阅与发现）、Editors（订阅发现 API、翻译 API Key、翻译模型：取消/保存）。
- 接入层：新文件 `Babel2LiveSettingsService.swift`（翻译、发现服务、强调色、语言、诊断/关于以底部卡片弹出〔保留旧页面右上角按钮〕、新增账户与 OPML 导入用不可见子页面作宿主）；`Babel2LiveDataAdapters.swift` 新增 `Babel2LiveAppDefaults`（排序/已读确认/打开链接/配色模式/开发版判断）与 `Babel2LiveAccounts`（账户列表/删除/同步内容/可添加类型/OPML）。边界测试对该文件增加 `AppDefaults.shared` 精确例外（用户同意）。
- 功能接通：文章排序（接入层排序比较）、全部已读前确认（列表页注入）、打开链接（系统浏览器时不建内置浏览器）、配色模式（导航控制器把窗口 overrideUserInterfaceStyle，改了立即重应用）——配色模式此前整个 app 都不生效。
- 按用户同意不放：分组方式、刷新时清除已读、启用 JavaScript、全屏文章、文章主题、添加 Babel 新闻源、配色模式子页（61）、账户详情的「新文章通知」。
- 图标：Figma 下载 7 个矢量图标（返回/关闭〔取消同图〕/保存/箭头/下箭头/勾/「译」）；首页其余 7 类用系统图标（用户选 A）。文案 +120 条中英文（xcstrings 按原有大小写不敏感顺序排列，原有行全部保留）。
- 验证（独立 DerivedData）：测试 +7（齿轮进入与路由恢复、8 类别各自进入、弹出菜单位置/立即生效/关闭、开关立即生效与 44pt 点击区、编辑页取消不存/保存写入、模型排行 Top10 + 每家 3 个 + 编辑页保存才生效、默认账户不可删/删除调用、无 iCloud 不显示 iCloud 统计、关闭确认后直接标记、设置文案全部中英文）。全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/set-full.xcresult` 135/135；UI Driver `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/set-ui.xcresult` 1/1。
- 过程记录：类别路由测试最初失败——测试窗口不挂屏幕场景时带动画的推入永不结束，其后推入被忽略（与内置浏览器一节同一限制），改为每个类别用新导航栈验证；非产品问题。
- 未能自动验证：全部视觉观感、弹出菜单毛玻璃与阴影、真实新增账户流程、OPML 导入导出、日志/关于卡片、界面语言重启提示、配色模式切换整个 app、强调色影响开关与进度环、翻译模型真实刷新——列入真机清单。
- 已知限制：排序改了之后，已打开的文章列表不会立刻重排（原地刷新只更新状态），返回首页再进入即按新顺序。
- 追加修复（用户报告）：右滑返回时当前页整页变暗、屏幕闪一下。原因：`Babel2NavigationPopMotion` 把合同的 shadowOpacity 实现成了盖在**当前页**上的整页黑色遮罩（手势一开始即 0.18，所有页面的返回都受影响，设置页纯色背景最明显）。修正：当前页只加左边缘投影（0.18 × (1 − p)），暗色遮罩改盖在上一页上、随滑开变淡；取消时清除投影。测试 +1（假转场上下文验证布置；反向验证：旧代码下该测试失败）。全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/pop-full.xcresult` 136/136。

## 文章列表顶部大图滚动收缩（Slice 3 第 3 步，ADR-027 / MOTION-CONTRACT §11；2026-09-25，用户真机验收通过，已提交并推送 `f02d83329`）

- 新增 `iOS/Babel2/Babel2FeedHeroMotion.swift`（纯计算）：pHero = clamp((offsetY − rest) / 70)；松手预计停在半路时改停最近一端（< 35 回展开、≥ 35 收到窄栏）；各层透明度映射（大图与图 1−p、大标题 1−1.6p、窄栏底 p、窄栏图标与名字 (p−0.4)/0.6）。
- 结构：列表铺满全屏、压在最下层，`contentInset.top` 固定 99（系统再加安全区）+ 70pt 透明 tableHeaderView 垫片，只设一次；大图叠其上、不接收触摸，滚动时整体平移 −70p 并淡出；最上层 `Babel2FeedCompactBar`（安全区 + 99pt，Figma 03C：26pt 圆形小图标 x=20 / 名字 17pt 半粗 x=56 / 底部细线；无图标时首字母圆），纸色底随 p 变不透明，返回按钮在这一层全程不动，除返回外触摸穿透给列表。大标题与窄栏标题为交叉淡入淡出（不做位置形变，用户要求少纠结细节）。未加性能打点。
- 验证（独立 DerivedData，核对 Ld）：测试 +2（进度与补完规则；展开/中间/收缩三态大图或窄栏下沿与列表内容紧贴、收缩后窄栏完全不透明、日期段标题吸在窄栏下沿、切档回顶后重新展开），原大图测试随结构更新。反向验证：大图不平移时无缝断言失败（差 35pt）。全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/col-full.xcresult` 127/127；UI Driver（Release、真实数据）`/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/col-ui.xcresult` 1/1。
- 未能自动验证：跟手顺滑度、补完手感、120Hz 帧率——真机验收。
- 2026-09-25 用户真机验收收缩通过；同时报告文章行偶发「标题与图标不对齐」（一行标题的行）。复现量得：每行都是 120pt、一行标题的标签被撑到 49pt（文字只需 22pt）、字上下居中下沉约 13pt。原因（第 1 步改版时引入）：「行高至少容纳缩略图」约束在缩略图隐藏时仍生效，多余高度分给了最软的标题标签。修复：该约束只在有缩略图时生效；来源名/标题/摘要竖直方向 hugging 设为 required（富余空白留在摘要下方）。测试 +1（一行标题不被拉伸、图标对齐、行高随内容变化、缩略图行仍放得下缩略图）。全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/align-full.xcresult` 128/128。

## 文章列表顶部大图（Slice 3 第 2 步，ADR-027；2026-09-25，样式 E 用户真机验收通过，已提交并推送）

- 新增 `iOS/Babel2/Babel2FeedHeroView.swift`：从屏幕最顶端铺到安全区下方 169pt；订阅源高清图标后台一次性缩到 240px 并高斯模糊（σ 12，边缘夹紧）、不透明度 0.55 作氛围底，CAGradientLayer 渐隐为纸色（0/0.25/0.92/1 @ 0/45/80/100%，随深浅色更新）；标题 28pt 粗体墨色（单行，过长缩到 0.75）、下接「N 篇」13pt；只放返回（沿用 babel2.feed.back / title / count 标识）；无高清图标时同版式纯纸色；图晚到时淡入。这一步不随滚动收缩。
- 接入：`Babel2FeedHeroImageSource`（列表页注入，cached/fetch）；接入层 `Babel2LiveFeedHeroImage` 调 1.x `FeedHeroIconLoader`（只用 isUsableAsHero 的图，1.x 文件零改动；`Babel2LiveFeedReaderSetting.feed` 由 private 改 fileprivate 以复用查找）；`Babel2SceneComposition` 注入；文案 +1 键（%d articles / %d 篇），辅助功能值仍为纯数字（UI Driver 依赖）。
- 验证（独立 DerivedData，核对 Ld）：测试 +1（大图从 y=0 到安全区+169、列表紧接无缝、无图为纯纸色、抓到图后铺上底图、标题/返回在大图内、「N 篇」与纯数字辅助功能值）；全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/hero-full.xcresult` 125/125；UI Driver（Release、真实数据）`/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/hero-ui.xcresult` 1/1。
- 未能自动验证：真实图标虚化后的观感、深色、状态栏文字在各种底图上的对比——列入真机清单。
- **改为样式 E（用户 2026-09-25）**：用户反馈 A 的「虚化 + 0.55 不透明 + 大面积渐隐」遮得太重、几乎看不出图（“买椟还珠”）。改为：图不虚化、完全不透明、铺满，只在下部渐隐（纸色 0/0/0.85/1 @ 0/55/80/100%），标题落在渐隐区；去掉 CoreImage 模糊，改为后台 `byPreparingForDisplay` 解码后淡入。已告知用户 E 的已知风险：多数源的图是 180–512px 方形 logo，铺满会放大发虚并裁掉上下；深色图在渐隐中段标题对比可能下降；状态栏与返回箭头在深色图上可能看不清。全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/heroE-full.xcresult` 125/125。

## 文章列表缩略图 + Reeder 式文章行与按天分组（Slice 3 第 1 步；2026-09-25，用户真机验收通过，已提交并推送）

- 起因：Babel 2.0 数据接入层只传文章自带图片地址（`article.imageURL`），普通 RSS/Atom 永远为空，列表几乎不显示缩略图。
- 改动：`Babel2LiveDataAdapters.swift` 新增 `thumbnailURL(for:)`——自带地址优先，否则复用 1.x `ArticleThumbnail.firstImageURL`（只读扫描正文开头、上游 HTMLScanner、跳过追踪像素、相对地址补全、按文章缓存；1.x 文件零改动）；列表行缩略图按 Figma 改为圆角 5、上边距 15、占位色 hairline；解码改为按缩略图尺寸缩小（ImageIO，最长边 70pt×屏幕倍率），后台解码 + 内存缓存（NSCache 300 张），失败保持占位。
- 测试：+4（正文取首图/跳过 1×1 像素/相对地址补全、JSON Feed 自带地址优先、无图与 data: 图为空、缩略图尺寸与缩小解码与失败占位）。测试目标不链接 Articles 且新测试文件需改工程文件登记，故测试放进已登记的 Babel2FeedReaderTests，并在接入层加 `thumbnailURLForTesting`。另把两个按 Task.yield 次数等待的测试辅助函数改为按真实时间（最多 3 秒）——首轮全量中 `testErrorIsDistinctFromEmptyAndRetryReloads` 偶发超时（单独连跑 3 次均通过，LESSONS 32 同类）。
- 验证：反向验证——关掉缩小解码后测试失败（2400px > 210px）。取图耗时（模拟器）：约 3 KB 正文 0.2 ms/篇，约 100 KB 正文 10 ms/篇，每篇只扫一次。全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/thumb-full2.xcresult`、`/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/thumb-full3.xcresult` 均 121/121。
- 追加（用户反馈）：有缩略图时日期被挤到缩略图左边；改为日期始终贴第一行最右边，缩略图移到日期下方、顶部与标题第一行对齐（偏离 Figma：设计稿时间在缩略图左侧）。测试补断言（日期右边缘 = 屏宽 − 20、缩略图在日期下方）。全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/date-full.xcresult` 121/121。
- 追加（用户给 Reeder 参考截图，“先按你的建议做”）：文章行重排——左列 24pt 来源图标（与标题第一行居中，无图标时首字母方块）；文字列 49pt 起：第一行大写来源名（12pt 浅灰）+ 时刻（13pt 等宽数字，贴右边缘）；标题 17pt 最多 2 行（未读半粗/已读常规）；摘要 17pt 浅灰 1 行；缩略图 70pt 在时间下方与标题齐平；行间无分隔线。去掉「英文 → 简体中文」提示行。列表按天分段（相邻同日文章为一段、不改顺序），段标题 14pt 中等墨色、跟随手机语言（今天/昨天/完整日期，拉丁文字全大写），吸顶时下方显示细线。点开、原地刷新、翻译可见标题、滚到某篇均改为按分段换算；下一篇逻辑不变（按原列表顺序跨段）。测试 +2（分段规则、行布局与跨段点开）；等列表行数的辅助函数改为数全部段。
- **验证事故（已纠正）**：从「日期贴右边」那次起，本机 xcodebuild 在共享 DerivedData 下只编译不链接，测试跑的是 15:20 的旧程序——那次报告的「121/121 通过」与本轮首次的「54 项 / 121 项通过」均未覆盖新代码（LESSONS 41）。改用独立 `-derivedDataPath /private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/dd` 从头编译后：文章列表测试组 56 项中 55 过、1 项为阅读页栏显隐测试偶发失败（单独 5 次 4 过；在未含本次改动的已提交版本上 5 次全过；该测试只用阅读页、不经过列表，记 NOTES 待办）；全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/rows-full2.xcresult` 123/123，并核对 app 产物时间与新代码字符串。
- 追加（用户验收后两处修正）：① 来源图标改为对准标题第一行字的视觉中线（第一行基线往上半个大写字母高度），原先按行框中心显得偏高；② 列表摘要改用上游 `ArticleStringFormatter.truncatedSummary`（正文去标签、约 300 字、缓存），原先只读 summary 字段，很多源标题下为空。测试 +1（摘要退回正文开头）、行布局测试补图标对齐断言。全量（独立 DerivedData）`/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/sum-full.xcresult` 124/124，已核对 `Ld`。
- 下一步：第 2 步顶部大图静态样子、第 3 步滚动收缩（设计决定见 ADR-027）。

## 长图三项改善 + 超长文章修复（2026-09-25，用户真机验收通过，已提交并推送）

- 按 ADR-026：①「分享自 Babel」签名（图标 + 文字）从长图末尾移到**顶部**（签名条 → 细线 → 日期/标题/署名 → 正文）；② 签名图标换成 Babel 2.0 新图标（新资源 `Babel2ShareSignatureIcon`，由 AppIcon 的浅/深两张缩到 240px，按长图深浅色自动取）；③ 分享面板「存储图像」成功后，底栏上方浮出小胶囊「已存储到相册」约 2 秒（取消、分享给别的 app、保存失败都不提示）。
- 文件：修改 `iOS/Article/ArticleLongImageExporter.swift`（经用户同意：`export` 加可选参数「签名样式」，默认值即旧行为，1.x 两处调用不变）、`Reader/Babel2ArticleViewController.swift`、`Babel2Localization.swift` + xcstrings（+1 键）、测试（+1 项，长图测试追加签名位置检查）；新增资源 `Assets.xcassets/Babel2ShareSignatureIcon.imageset`。
- 验证：相关 2 项 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/li-t1.xcresult` 通过；反向验证——临时改回「底部签名」时长图测试失败（顶部行 34 像素 / 底部行 101 像素），改回后通过（顶部行 101 像素），阈值定为 70；全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/li-full.xcresult` 116/116。pbxproj 签名 diff hash 仍为 `c5f5a8cf…`，`Shared/Localizable.xcstrings` 的 stale 行未动。
- 未能自动验证：图标在长图上的观感、真实存入相册与系统权限弹窗、提示的观感——列入真机验收清单。
- **追加：超长文章长图空白（2026-09-25 用户真机报告，已修复，用户真机验收通过）**。现象：volts.wtf「Do small residential batteries make…」（约 1.2 万词，阅读页约 64,500 点高）存进相册是一整张底色。查证：网页导出 PDF 单页最高 14,400 点、被切成 5 页，PDF 本身完整；导出器拼图时每页 PDF 自带的背景远大于本页，后画的页把前面整片盖掉，只剩最后一页。1.x 起就有，短文章（单页）不受影响。修复（用户同意）：每页先限定在自己的格子里再画。另按用户选择 A：超长时拆成多张、每张保持 2 倍清晰度（最高 2.5 万像素/张，最多 10 张，再长才整体降分辨率），尽量切在两行字之间，签名只在第 1 张顶部；每张画完立即压成 PNG 以免多张位图同时占内存（6 张约 400 MB）。新增 `exportImages`，旧 `export` 仅加了限定格子（1.x 同步修好）。
- 追加验证：新测试（900 段长文，多页 PDF）——旧单张画法中间有内容、新拆图每张 804 宽/每段有内容/接缝在行间/签名在第 1 张；反向验证：放开限定后该测试失败（第 4–6 张及旧画法大段空白），恢复后连跑 3 次通过。真实文章实测（临时测试，已删）：6 张、每张 804 宽、每张 10/10 段有内容、接缝均在行间、每张 2.4–3 MB、模拟器生成约 1.8 秒。全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/9aae9465-6455-4fea-bb8a-7eb613336df1/scratchpad/split-full.xcresult` 117/117。

## Reader Slice 5 第 5 步：生成长图（2026-09-25，用户真机验收通过，已提交并推送）

- 按 ADR-025 实现：••• 菜单「生成长图」可点；临时标题区 + 滚动补偿；复用旧导出器；完成弹系统分享面板。
- 文件：`Reader/Babel2ArticleViewController.swift`（菜单、生成流程、分享）、`Reader/WebKit/Babel2ReaderContentView.swift`（临时标题区样式与插入/移除）、`Babel2Localization.swift` + xcstrings（+2 键）、测试（+1）。旧导出器与截图脚本零改动。
- 过程中的错误：第一版用定格截图盖住正文区，全量测试在长图测试上卡死 8 分钟以上；逐步探针定位——准备/等图/单独导出均正常，卡在被遮住的网页不再绘制——改为滚动补偿后该测试 2.8 秒通过。
- 验证：全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/longimage-r2.xcresult` 115/115（含真实导出：长图高大于宽、临时标题区已移除、无残留视图、状态字已隐藏）。
- 2026-09-25 用户真机验收通过。**Slice 5 全部完成**（翻译、阅读模式、内置浏览器、下一篇、生成长图）。
- 用户已提出下一会话的长图改善（见 HANDOFF 顶部）：页脚「分享自」签名移到长图顶部；签名里的 app 图标换成 Babel 2.0 新图标；保存到相册成功时给提示。

## 标题翻译请求关闭思考（2026-09-25，用户真机确认明显变快，已提交并推送）

- 起因：用户反馈标题翻译慢。查证：`NNWTitleBatchTranslator` 请求未带正文翻译已有的 `reasoning: {effort: "none", exclude: true}`（2026-08-08 只加在正文那边）。
- 改动（用户同意改共享翻译引擎一处）：`Shared/Translation/NNWTitleTranslationController.swift` 的标题请求补上同一字段，仅对 OpenRouter 发送。
- 验证：新增测试用本地拦截检查真实请求体——OpenRouter 请求含 effort=none、exclude=true，其他服务商不带该字段；全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/reasoning-r1.xcresult` 114/114。macOS：工作区直接编译被 `DEVELOPMENT_TEAM` 不应写在 pbxproj 的检查拦下（来自用户未提交的真机签名改动，与本改动无关）；在仅含本改动的临时副本中 macOS Debug build 成功。
- 2026-09-25 用户真机对比：标题翻译「明显变快了」——说明所选模型默认会思考，之前慢主要因思考过程。

## 文章列表标题翻译开关（2026-09-25，用户真机验收通过，已提交并推送）

- 按 ADR-024 实现：列表底栏「原 翻译」开关接通；打开后请求屏幕上未翻标题，译文到达原地刷新；滚动停下继续请求；关闭原地恢复原文；启动唤醒引擎恢复新文章提前翻译。
- 文件：`Babel2LibraryViewControllers.swift`（列表页开关与请求）、`Babel2SceneComposition.swift`（注入）、`Babel2AppAssembly.swift`（启动唤醒引擎）、`Babel2Integration/Babel2LiveDataAdapters.swift`（`Babel2LiveTitleTranslation`、通知转发）、测试（+2，1 项旧占位断言更新）。`Shared/Translation/` 零改动。
- 验证：全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/titletr-r1.xcresult` 113/113；UI Driver `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/titletr-ui-r1.xcresult` 1/1（启动与主路径不受引擎唤醒影响）。真实联网标题翻译未在模拟器验证（无 API key）。
- 2026-09-25 用户真机验收通过，但反馈标题翻译「很慢」。查证：标题批量翻译请求（`NNWTitleBatchTranslator`）没有带正文翻译 8 月 8 日加上的 `reasoning: {effort: none, exclude: true}`，若所选模型默认思考会显著变慢；另标题 12 条一批非流式、整批返回。手机上所选模型未知（设置页未做）。用户同意补上该字段（下一小步）。

## 首页底栏改用共享档位组件（2026-09-25，用户真机回归验收通过，已提交并推送）

- 起因：用户报告首页选别的档再选回「未读」时胶囊变窄、圆点压在 UNREAD 上；列表页（`Babel2ScopeFilterControl`）无此问题。模拟器测试不播放动画，复现不了（LESSONS 36）。用户选方案 A：首页改用同一组件。
- 改动：`Babel2RootViewController` 删除手写的三按钮 + 胶囊（配置、图标、胶囊动画与打断采样中与胶囊相关的部分），改用 `Babel2ScopeFilterControl`（沿用 babel2.scope.* 标识与本地化 bundle）；列表内容的滑动淡入、计数、pFilter 打点、打断处理不变。按钮「选中」样式现在一点即变（原先等动画结束才变）。组件新增标识前缀/本地化 bundle 参数。测试：两项打点测试改为等待新增的 `isScopeTransitionSettledForTesting`（原来用按钮选中作为“切换结束”信号，语义已变）。
- 验证：r1 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/homefilter-r1.xcresult` 109/111（两项打点测试的等待信号问题，见上）；r2 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/homefilter-r2.xcresult` 111/111；UI Driver `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/homefilter-ui-r1.xcresult` 1/1（真实数据依次切三档并检查选中）。
- 技术待办「首页与列表页档位重复实现」随之消除。
- 2026-09-25 用户按 5 项清单真机回归验收通过：切回「未读」不再错位、快速连点、冷启动按钮位置未回归、列表切档返回首页同步、深色。口头确认。

## 文章列表底栏（2026-09-25，用户真机验收通过，已提交并推送）

- 按 ADR-023 实现：文章列表页 72pt 底栏（全部标为已读 / 三档 / 标题译占位）；原地切档回顶并同步首页；全部标为已读先确认再批量标记。
- 文件：新增 `iOS/Babel2/Babel2ScopeFilterControl.swift`、资源 `Babel2FeedReadAll`（Figma 22:20）；修改 `Babel2LibraryViewControllers.swift`（列表页）、`Babel2RootViewController.swift`（仅新增 `applyScope`）、`Babel2SceneComposition.swift`、`Babel2Core/Contracts.swift`（`markFeedRead`）、`Babel2Integration/Babel2LiveDataAdapters.swift`、`Babel2Localization.swift` + xcstrings（+3 键）、测试（+2）。
- 技术待办：首页底栏改用 `Babel2ScopeFilterControl`，去掉重复实现（需要首页回归验收）。
- 验证：全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/feedbar-r1.xcresult` 111/111；Babel2UI package 32/32；UI Driver `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/feedbar-ui-r1.xcresult` 1/1。
- 2026-09-25 用户真机验收：文章列表底栏全部通过；另报告**首页**底栏既有问题——选别的档再选回「未读」，胶囊变窄、圆点压在 UNREAD 上（列表页底栏无此问题）。首页代码本步仅新增 `applyScope`，非本步引入。
- 排查记录：模拟器测试不播放动画，复现不了；一度误把按钮的 `imageView`/`titleLabel`（配置式按钮的隐藏内部副本）当成屏幕内容去量，得出“排版过期”的错误结论并做了无效修复——已撤回，相关测试已删除（LESSONS 36）。用户选 A：首页改用 `Babel2ScopeFilterControl`（下一小步）。

## Reader Slice 5 第 4 步：下一篇（2026-09-25，用户真机验收通过，已提交并推送）

- 按 ADR-022 实现：`Babel2FeedViewController.nextArticle(after:)` / `revealArticle(_:)`；`Babel2NavigationController.replaceTopBabel2`（竖向滑动过渡）；装配层统一 `makeReader` 同时服务点进与下一篇；底栏 ∨ 接通，全部底栏控件已无占位。
- 文件：`Babel2LibraryViewControllers.swift`（列表页 2 个方法）、`Babel2NavigationController.swift`（1 个方法）、`Babel2SceneComposition.swift`、`Reader/Babel2ArticleViewController.swift`、`Reader/Babel2ReaderToolbarView.swift`、测试（+2，1 项旧占位断言更新）。
- 验证：r1 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/next-r1.xcresult` 108/109——暴露真实小问题：∨ 可用状态要等页面出现才刷新，滑入动画期间是灰的；改为页面建好即刷新。r2 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/next-r2.xcresult` 109/109。滑动过渡观感只能真机验证（测试窗口不挂屏幕场景，动画不播）。
- 2026-09-25 用户按 6 项清单真机验收通过。用户随即指出文章列表页缺少 Figma「Feed Toolbar」底栏（全部已读 / 星标 / 未读 / 全部 / 标题译开关）——属 Slice 3 未做部分，经同意提前单独做。

## Reader Slice 5 第 3 步：内置浏览器（2026-09-25，用户真机验收通过，已提交并推送）

- 按 ADR-021 实现：右缘左滑跟手进入（`Reader/Babel2ReaderBrowserMotion.swift`）；浏览器页 `Reader/WebKit/Babel2BrowserViewController.swift`；••• 打开原文、正文网页链接、紧凑栏「↗」均进内置浏览器；UI Driver 相应改为验证内置浏览器出现并 ✕ 返回。
- 文件：新增上述 2 个；修改 `Reader/Babel2ArticleViewController.swift`、`Reader/Babel2ReaderCompactHeaderView.swift`、`Babel2SceneComposition.swift`、`Babel2Localization.swift` + xcstrings（+5 键）、单元测试（+4，1 项旧预期改为验证内置浏览器）、UI Driver 测试。
- 验证：全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/browser-r3.xcresult` 107/107；UI Driver（Release、真实数据）`/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/browser-ui-r1.xcresult` 1/1。中间轮次：r1/r2 各 1 项失败均为测试写法（阅读页未显示就推页面；测试窗口不挂屏幕场景导致推入动画不结束），已改测试。
- 2026-09-25 用户按 10 项清单真机验收通过（右缘跟手、半途弹回、过半补完、中间划不误触、左边缘返回与 ✕、浏览器五按钮、链接与 ↗ 入口、深色）；投影 0.15 s / 阈值 0.5 未提出调整。口头确认，非 Instruments 证据。

## 阅读模式入口调整（2026-09-25，用户真机验收通过，已提交并推送）

- 按 ADR-020：底栏第 4 格恢复「阅读模式」按钮（一点即开/关，开时加粗图标主墨色，无原文地址时不可点）；••• 菜单改为「此订阅源总是用阅读模式」（勾选）/ 打开原文 / 生成长图（灰色占位）。按订阅源开关读写既有 `Feed.readerViewAlwaysEnabled`（集成层 `Babel2LiveFeedReaderSetting`），开着的源打开即全文、不写单篇记忆；1.x 设过的直接生效。
- 文件：`Reader/Babel2ArticleViewController.swift`、`Reader/Babel2ReaderToolbarView.swift`、`Babel2SceneComposition.swift`、`Babel2Integration/Babel2LiveDataAdapters.swift`、`Babel2Localization.swift` + xcstrings（+1 键）、测试（+2）。
- 验证：r2 102/103——一条旧预期“无原文地址时 ••• 为空并禁用”不再成立（菜单恒有长图占位），改预期后 r3 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/readermode-r3.xcresult` 103/103。
- 2026-09-25 用户按 7 项清单真机验收通过（底栏一点开关、菜单三项、设源开关后同源文章自动全文、取消后不再自动）。口头确认。

## Reader Slice 5 第 2 步：阅读模式（2026-09-25，用户真机验收通过，已提交并推送）

- 按 ADR-019 实现：••• 菜单「阅读模式」开关（勾选态）→ `Babel2FullTextFetcher`（包装未改动的 ReaderViewExtractor）取全文 → 以全文重新排版并回到顶部；关闭则回到原正文。署名下方状态字「正在获取全文… / 无法获取全文」。按单篇记忆，再次打开自动取全文。切换时翻译回到原文并在新正文排好后重新就绪。底栏第 4 格改为「长图」占位（既有 `BabelReaderShareLongImage`，与 Figma 105:45 导出 SVG 逐字节一致）。Figma 无阅读模式状态画面，仅图标。
- 文件：新增 `Reader/Babel2FullTextFetcher.swift`；修改 `Reader/Babel2ArticleViewController.swift`、`Reader/Babel2ReaderToolbarView.swift`、`Babel2Localization.swift` + xcstrings（+3 键）、测试（+3，另在 setUp/tearDown 清理测试文章的单篇记忆）。未改 Shared/ReaderView、翻译引擎、数据层、禁区。
- 验证：全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/readermode-r1.xcresult` 101/101。临时探针：真实提取器经包装抓取 gnu.org 长文成功（29,206 字符，4.3 秒），探针已删除。
- 2026-09-25 用户按 8 项清单真机验收通过。用户随即提出：阅读模式对某些源很常用，放在 ••• 菜单操作成本高——入口位置待重新决定（见 HANDOFF）。

## 阅读页对齐 Figma（2026-09-25，用户真机验收通过，已提交并推送）

- 起因：用户指出阅读页控件、图标、尺寸与 Figma 差距大；接上 Figma 连接后逐项对照 04A(22:38)/04B(117:263)/04D3(143:444)/Translation Toggle(43:19)/Reader Toolbar(21:5)/Compact Header(143:73)。决定见 ADR-018（用户“都按建议来”）。
- 已改：① 图标换设计稿矢量（Close/More/ReadState/Star/Next 新导出进 `iOS/Babel2/Assets.xcassets`；阅读模式复用逐字节一致的既有 `BabelReaderReadingMode`；已读/星标实心态由同一轮廓填充派生，来源见 `FIGMA-READER-ICONS.md`），图标色改次要灰 #787878。② 顶栏：✕(x=32)/•••更多菜单(x=201，内含「打开原文」，无原文地址时禁用)/系统分享(x=370)，中心 y=22；不放「标签」。③ 标题区：日期 11pt 半粗字距 0.3；标题 34pt 粗体行高 38 字距 −1；署名两行「作者 / 订阅源」11pt 字距 0.25 行高 15；上 26、间距 13/9、下 60。④ 正文次要灰、段距 20、引用块竖线 2pt(左移 8)+文字距 18、引用内段距 8；小标题/链接主墨色。⑤ 底栏：0.5pt 分隔线、24pt 图标、翻译改 Figma 文字开关「原 翻译 / 译 生成中 / 译 原文 / 原 重试」（取消缓存角标）。⑥ 紧凑栏：副标题「订阅源 · 作者」、行间 2、圆环半径 22 / 底圈 2 / 弧 2.5、占位底色为分隔线灰 + 24pt 首字母、0.5pt 分隔线、内容垂直居中 42.75。⑦ **栏隐藏改为 Figma 04D3**：顶部按钮行整行收进状态栏底色后面，紧凑栏上移 44pt 贴状态栏（推翻 Slice 4 第 3 步方案 A；MOTION-CONTRACT §10 相应句已修订）。⑧ Babel2Core `ArticleSnapshot` 增可选 `author`，集成层取第一个有名字的作者。
- 未照稿（有意）：紧凑栏副标题末尾「↗」暂不显示（点击来源在内置浏览器步接通）；顶栏右上用系统分享符号（合同规定为普通分享，设计稿只有“分享长图”图标）；底栏第 4 格暂仍为阅读模式（ADR-016 后续改长图）。
- 验证：全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/figma-r2.xcresult` 98/98（新增：Figma 文字开关六态、顶栏三按钮位置与图标资源/署名两行/紧凑栏副标题/正文次要灰；栏隐藏时紧凑栏上移 44）；Babel2UI package 32/32。r1 97/98 为测试自身假设浅色模式（模拟器为深色，108 即深色次要灰），已改为按当前外观比较。
- 2026-09-25 用户按 6 项清单对照 Figma 04A/04B/04D3 真机验收通过（含深色、••• 菜单打开原文、栏隐藏时紧凑栏上移）。口头确认。

## Reader Slice 5 第 1 步：翻译（2026-09-25，用户真机验收通过，已提交并推送）

- 方案（用户确认“按建议来”）：整套既有翻译引擎（`Shared/Translation/` 的 TranslationController、OpenAICompatibleTranslator、缓存、断点续翻、`translation.js` 的分块/流式/骨架色条）**一行不改**原样复用；Babel2 阅读页实现 `NNWArticlePageHost` 接口搭桥。设置页仍在 Slice 6，暂沿用手机里旧版已存的 API key/模型。
- 实现：`Reader/WebKit/Babel2ArticlePageHost.swift` 让阅读页成为宿主（文章对象 + 网页控件 + 标题回调）；外壳页加隐藏 `h1.articleTitle`（渲染时写入原标题）供引擎读写，避免误改正文里的 h1，正文容器 `<article>` 命中 translation.js 既有兜底选择器；标题译文同步到原生大标题与紧凑栏；底栏第 5 格翻译按钮启用（原文/完整缓存实心点/未完成缓存空心圈/翻译中变淡且可点=取消/已译小勾/失败感叹号，均中性色，无系统转圈）；错误弹窗；离开页面或重新排版时取消在飞请求；再次打开曾以译文离开的文章自动恢复译文（引擎既有逻辑）。
- 风险验证：外壳页 CSP（禁止页面脚本）**不拦截** app 原生注入的 translation.js——探针测试注入后 `window.nnwTranslation` 可用且 readBody 返回正文，已改为正式测试。
- 文件：新增 `Reader/WebKit/Babel2ArticlePageHost.swift`；修改 `Reader/Babel2ArticleViewController.swift`、`Reader/Babel2ReaderToolbarView.swift`、`Reader/Babel2ReaderCompactHeaderView.swift`、`Reader/WebKit/Babel2ReaderContentView.swift`、`Babel2SceneComposition.swift`、`Babel2Localization.swift` + xcstrings（+3 键）、`Babel2Integration/Babel2LiveDataAdapters.swift`（新增 `Babel2LiveArticleLookup`，见 ADR-017）、测试。`Shared/Translation/` 零改动。
- 验证：全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/translate-r2.xcresult` 97/97（+3：桥接读正文/隐藏标题/标题与正文替换与还原；按钮就绪条件；六态中性且翻译中可点）。r1 1 项失败为边界测试——中文注释里写了含「WebKit」的目录名被字面匹配判违规，已改措辞（LESSONS 30 追记）。未在模拟器发起真实翻译（模拟器无 API key）。
- 首轮真机（2026-09-25）：基本通过；反馈“已译完的文章点按钮回到原文后，按钮始终是实心点”。原因：我把「已翻译」角标画成 `checkmark.circle.fill`，9pt 下看起来就是实心点，与「有完整缓存」的实心点无法区分（引擎状态本身正确：已译=勾 → 切回原文=有缓存实心点）。修复：改为旧版定稿的单独小勾（`checkmark` 10pt heavy），圆点 7pt，角标垫背景色晕圈；测试补“勾/实心点/空心圈/无角标”四者可分。r3 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/translate-r3.xcresult` 97/97。
- 2026-09-25 用户真机复验通过（已译=小勾 → 原文=实心点 → 秒开中文=小勾）。
- 用户同时指出：阅读页控件、图标、尺寸与 Figma 差距大。原因：本会话此前无 Figma 连接，只按 BATCH-01-SPEC 文字数值与系统图标实现；另我未查资源库，漏用已从设计稿导出的 `BabelReaderReadingMode` / `BabelReaderShareLongImage` 等图标（疏漏）。用户已接上 Figma 连接，下一步插入「阅读页对齐 Figma」小步骤，再继续 Slice 5。

## 已读图标反转 + 打开文章自动标已读（2026-09-25，用户真机验收通过，已提交并推送）

- 用户决定：①底栏已读图标改为 实心圆 = 已读、空心圈 = 未读（与 Reeder/旧版相反）；②打开文章即标为已读。
- 实现：`Babel2ReaderToolbarView.setRead` 只换两个图标名；`Babel2ArticleViewController` 在 viewDidAppear 时若文章未读则调用现成 `LibraryAction.markRead`，每次打开只自动标一次，之后手动标回未读不会被再次改掉；成功后图标变实心，列表/首页经既有通知刷新。
- 文件：`iOS/Babel2/Reader/Babel2ReaderToolbarView.swift`、`Babel2ArticleViewController.swift`、`Tests/.../Babel2FeedReaderTests.swift`（底栏测试改为先验证自动标已读、再手动切换、且再次出现不重复自动标）。未改数据层/禁区。
- 验证：全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/autoread-r1.xcresult` 94/94。注意：UI Driver 现在进入文章会把模拟器里的一篇真实文章标为已读（仅模拟器数据），本步未重跑。
- 2026-09-25 用户按 6 步清单（打开即实心圆、返回列表原位变细、首页未读数减 1、手动标未读后停留不被自动改回、返回变回粗体）真机验收通过。口头确认。

## 文章列表随状态变化原地刷新（2026-09-25 用户真机验收通过，已提交）

- 更正：第 3 步记录里“列表与首页不即时刷新、原因是 articleCache 不失效”的判断有误。核实后：首页 `Babel2RootViewController` 已监听 `.babel2LibraryDidChange`（由 Account 的 `StatusesDidChange` 转发；本地账户 `markArticles → updateStatusesAsync → noteStatusesForArticleIDsDidChange` 会发出），应当已会刷新；真正不刷新的是 `Babel2FeedViewController`（只在打开时加载一次）。`articleCache` 仅被未使用的 `articleSnapshot(for:)` 读取，与此无关，未改动。
- 修复（用户选定方案 A）：文章列表监听 `.babel2LibraryDidChange`，0.3s 合并后按「全部」档重新读取该源文章最新状态，只原地替换已显示行（仅重载可见且有变化的行）；不增删行、不改顺序、不动滚动位置、不显示加载中；「未读」档里刚读完的文章留在列表只是标题变细，离开再进来才按新状态筛选。同时覆盖后台同步引起的状态变化。
- 文件：仅 `iOS/Babel2/Babel2LibraryViewControllers.swift`（列表页）与 `Tests/.../Babel2FeedReaderTests.swift`（+1 项；测试用假数据源增加可改写数据的方法）。未改数据接入层/Core/禁区/pbxproj。
- 验证：全量 `/private/tmp/claude-501/-Users-wenbopan-Downloads-AI-Projects-Babel-app/04491fb8-8378-43c8-b159-d9cf837e3e85/scratchpad/list-refresh-r1.xcresult` 93/93。
- 首轮真机反馈“第 3 步起全无变化”，排查（模拟器真实数据诊断：写库成功、通知在主线程发出 4 次、未读数 63→62 后已还原；新增“列表被阅读页盖住时变化、返回后重画”测试通过；端到端 UI 测试因模拟器 runner 连续超时未跑成，已删除）后，用户确认原因是**图标含义理解相反**（以为实心=已读）。按正确含义重测，2026-09-25 用户确认 6 步全部正常：列表行原地变细不跳动、首页未读数减 1、重新进入后不在未读列表、反向标未读变回粗体。
- 排查用的临时诊断测试、端到端 UI 测试与行 accessibilityValue 已全部移除，未进入提交。
- 用户同日追加两项决定（下一步实现）：①已读图标反过来——实心圆=已读、空心圈=未读；②打开文章时自动标为已读（Babel 2.0 阅读页此前从未实现，属遗漏，非有意设计）。

## Reader Slice 4 第 3 步：底栏与上下滑显隐（2026-09-24，用户真机验收通过，已提交）

- 用户 2026-09-24 选定（“都按建议来”）：①隐藏方式 A——顶栏只让按钮淡出并上移 8pt、底色保留，紧凑栏完全不动（遵守合同“隐藏栏不得移动固定标识”），底栏整条向下滑出并淡出；②底栏先按 Figma 五项：已读 / 星标 / 下一篇 / 阅读模式 / 翻译，“生成长图”放哪到 Slice 5 再定。
- 底栏：72pt 贴屏幕底（含 Home 指示条区域），顶部细分隔线；按钮中心按 402pt 画布比例 x=32/104/201/290.5/362、距栏顶 24pt。已读（实心点=未读/空心圈=已读）与星标调用现成 `LibraryAction.markRead/markUnread/toggleStar`（Babel2LiveActionHandler，未改数据层），成功后才切换图标、进行中不重复发送、失败不变。下一篇/阅读模式/翻译为 Slice 5 占位：灰色、不可点。正文底部 contentInset 让出 72pt−安全区（只在安全区变化时改）。
- 显隐（MOTION-CONTRACT §10）：仅在紧凑栏固定后生效；同方向累计 12pt 才开始；之后 barP 跟手（hideDistance 60pt，to-tune）；反向重新累计；到底回弹忽略；手指离开且滚动停下 0.12s 后，停在半路则 180ms 线性补完到最近一端（≥0.5→隐藏）；补完中再滑可从当前画面位置接着跟手；未固定/回顶强制显示（有动画）。打点：controlsChanging begin/end 每次交互成对。
- 文件：新增 `iOS/Babel2/Reader/Babel2ReaderBarVisibility.swift`（纯规则）、`Babel2ReaderToolbarView.swift`；修改 `Babel2ArticleViewController.swift`、`Babel2Localization.swift` 与 `Resources/Babel2Localizable.xcstrings`（新增 7 个中英键）、`Tests/.../Babel2FeedReaderTests.swift`（+3 项，1 项旧期望过滤显隐打点）。未改 Core/adapter/禁区/pbxproj。
- 验证：全量 92/92；UI Driver 1/1（未点底栏，不改真实数据）。
- 已知限制（已于同日处理，见上方「文章列表随状态变化原地刷新」；此处原因分析有误，保留原文供追溯）：阅读页改了已读/星标后，返回的文章列表行与首页计数不会立即更新——Babel2LiveDataProvider 的 articleCache 不失效，需改 `iOS/Babel2Integration/Babel2LiveDataAdapters.swift`。
- 2026-09-24 用户按 10 项清单（底栏外观、已读与星标真实写入并在重新进入后可见、固定后下滑隐藏且紧凑栏不动、上滑恢复且小抖动不闪、半路松手补完、回顶显示、短文不隐藏、深色、左边缘返回）真机验收，回复“真机验收通过了”；12pt/60pt 未提出调整。口头确认，非 Instruments 证据。**Slice 4 三步至此全部完成**；整体 Slice 4 合同中的“多种 safe area/旋转/后台恢复保留位置、横图贴边在引用/列表内”等仍未专门验收。

## Reader Slice 4 第 2 步：滑动收缩（2026-09-24，用户真机验收通过，已提交）

- 用户选定方案 A：大标题随正文滚走，顶栏下方 86pt 紧凑标题栏（与顶栏重叠 14pt）的底色/48pt 进度圆环+42pt 圆形订阅源图标/订阅源名+一行标题，按 pCollapse 线性渐显，文字从下方 12pt 滑入；固定后圆环按 pReading 顺时针增长（12 点起，主题色，唯一用主题色处）。全部由滚动位置直接驱动、可倒放，无自动播放动画；紧凑栏是覆盖层，滚动时不改正文区域几何。
- 公式按 MOTION-CONTRACT §9：collapseStart = 大标题上沿在标题区内的位置（布局后测得），collapseDistance = 70pt（to-tune），eligibility = maxScroll > collapseStart。maxScroll 用页内 ResizeObserver 测得的**正文实际高度**计算（网页文档至少一屏高，不能用滚动区 contentSize，见 LESSONS 31）；未测到高度前视为不可收缩。
- 打点：`Babel2.Reader.Chrome` 只在状态切换时记录；进入收缩中=begin、离开收缩中=end、一帧内展开↔固定直接跳跃=event，避免不成对区间；barP 暂恒为 0（第 3 步接）。
- 文件：新增 `iOS/Babel2/Reader/Babel2ReaderChromeProgress.swift`（纯计算）、`Babel2ReaderCompactHeaderView.swift`（紧凑栏+圆环）；修改 `Babel2ArticleViewController.swift`、`Reader/WebKit/Babel2ReaderContentView.swift`（滚动/高度观察、正文高度上报通道）、`Babel2SceneComposition.swift`（传订阅源图标）、`Tests/.../Babel2FeedReaderTests.swift`（+3 项）。未改 Core/adapter/禁区/pbxproj。
- 验证：全量 89 项中 88 通过；唯一失败 `testRapidScopeTapsThroughThirdTargetDuringActiveAnimationSettleOnLastSelection` 在已提交的 `4c58dfcaa`（不含本步改动）单独运行同样失败，属既有时序敏感测试（按 Task.yield 次数而非真实时间等待动画）。用户同意后把 `waitForSelectedScopeButton` 改为按真实时间等待（最多约 3 秒）：3 项筛选测试单独连跑 3 轮全过，全量 89/89 通过。UI Driver 1/1 通过。
- 2026-09-24 用户按 7 项清单（渐显而非弹出、半路停住与倒放、固定与真实图标、圆环顺时针与主题色、快速甩动无闪烁、短文不出现、深色模式）真机验收，回复“真机验收通过了”；70pt 收缩距离未提出调整。口头确认，非 Instruments 证据。第 3 步（顶/底栏随方向显隐、底部工具栏）未开始。

## Reader Slice 4 第 1 步：静态图文页（2026-09-24，用户真机验收通过，已提交）

- 用户 2026-09-24 确认方案（“按建议来”）：Slice 4 拆三步（静态图文页 → 滑动收缩 → 底栏与上下滑隐藏），每步停下等真机验收；「打开原文」按钮保留到 Slice 5 内置浏览器落地；排版数值按 `Figma Drafts/BATCH-01-SPEC.md`（本会话无 Figma 连接）。
- 实现：原生标题区（日期/34pt 标题/订阅源名）挂在正文滚动区顶部、不等网页加载即可见；正文用专用网页显示面（仅在 Boundary 白名单目录 `iOS/Babel2/Reader/WebKit/`），先载固定外壳页再由隔离环境脚本排版，Swift 不拼接文章 HTML；外壳页 CSP 禁止页面脚本，排版时移除 script/表单/on* 属性/javascript: 链接/内联 style 与 class；横图（宽≥320 且宽>高×1.1）100vw 贴边直角，竖图/文字/图注保留 20pt 边距；链接加粗+中性下划线；浅/深两套 BabelPalette 值；正文链接交系统打开；顶栏 58pt 不透明：返回（x=32）/打开原文（x≈326）/系统分享（x=370）；失败显示提示+重试，无正文显示“这篇文章没有正文”。
- 文件：新增 `iOS/Babel2/Reader/Babel2ArticleViewController.swift`、`iOS/Babel2/Reader/WebKit/Babel2ReaderContentView.swift`；修改 `iOS/Babel2/Babel2LibraryViewControllers.swift`（仅删除旧纯文本阅读页 143 行）、`Babel2SceneComposition.swift`（传 feed 标题、链接交系统打开）、`Babel2Localization.swift` 与 `Resources/Babel2Localizable.xcstrings`（新增 Back/Share/Open Original/Unable to load article/This article has no content 五个中英键）、`Tests/NetNewsWire-iOSTests/Babel2FeedReaderTests.swift`、`Babel2FeedReaderUITests.swift`（正文改按 webView 子文本读取）。未改 Core/adapter/DataProviding、上游 template/stylesheet、A/C 级禁区或 pbxproj（签名 diff hash 仍 `c5f5a8cf…`）。
- 验证：全量 Debug iOS test 86/86 passed（原 80 + 新增 6）；UI Driver（Release、真实模拟器数据）1/1 passed，正文 webView 文本可读、Open Original handoff 正常。详见 [VALIDATION](VALIDATION.md)。
- 2026-09-24 用户确认 Xcode 工程路径为本仓库后，在目标 iPhone 按 6 项清单（首屏标题、图文排版/横图贴边、链接样式与外部打开、系统分享、左边缘返回与正文滚动不冲突、深色模式）验收，回复“真机验收通过了”；为口头确认，非截图/Instruments 证据，不外推到其他设备、旋转或英文界面。尚未做：滑动收缩、进度环、底栏、作者名（快照无作者字段，暂以订阅源名作署名）、正文标题译文（Slice 5）。

## 筛选按钮 Auto Layout 改写（物理真机冷启动通过；视觉待确认，2026-09-08，未提交）

- 旧的 `a707e4bae` `viewDidAppear`/`window.layoutIfNeeded()` 修复已被用户真机复测证伪；本轮没有继续叠加窗口布局时序 workaround。
- `iOS/Babel2/Babel2RootViewController.swift` 直接安装一次性 Auto Layout 约束：三个按钮固定 `90×44`，垂直居中，水平中心按 402pt 参考画布的 `104/201/290.5` 比例约束；删除手工 frame 分支、零宽度 fallback 和 `layoutScopeControlsIfNeeded()`。`selectionPill` 仍由现有 controller 以 frame 驱动，活动过渡期间不被布局回调覆盖。
- 不新增文件或第二 layout owner：现有 controller 继续同时拥有按钮、pFilter 和 selection pill。未改视觉常量、默认 scope、pFilter 数据/动画语义或 `NetNewsWire.xcodeproj/project.pbxproj`。
- 用户随后明确回复“好的，成功了”，据此关闭本次目标物理设备的筛选按钮冷启动布局验收；不外推到旋转、其他尺寸、其他设备或整页视觉。
- 全量 Debug iOS test：`/private/tmp/babel2-library-figma-r1.xcresult` 顶层 `total=80`、`passed=80`、`failed=0`、`skipped=0`，结果为 Passed；设备配置为 iPhone 17 / iOS 27 Simulator，动态参数展开后的 `passedTests=82`。精确命令见 [VALIDATION](VALIDATION.md) 当前 Figma 小节。

## 本轮验证与下一步

- 同日接手检查已跑 Babel2UI package：32/32 passed，源码基线同上；不重复运行。该检查在 macOS 上运行，不覆盖 UIKit 条件编译路径。
- 本轮应用级全量测试、用户真机确认与生成文件哈希结果见 [VALIDATION](VALIDATION.md)「筛选按钮 Auto Layout 与 Feeds/Library 首页 Figma 对齐」一节；此前 77/77 应用测试仍是历史证据。
- 2026-09-24 用户在目标物理 iPhone 冷启动完成首页整页视觉验收（标题/同步显示、摘要与 Folders、folder/feed 几何与展开、三档筛选静态/切换、返回后状态），回复“首页验收通过了”；为口头确认，非截图/自动化证据。Dark、不同语言、旋转和其他设备不在已验证范围。 下一步候选（待用户选择）：正式图文 Reader（Slice 4，推荐）或 Timeline hero（Slice 3）。

## Feeds/Library 首页 Figma 对齐（2026-09-24 用户真机验收通过，已提交）

- 当前排期优先对齐 Figma file `0kFsVs9DLbE7Um96yrlBKg`、node `22:36`（02 · Library，402×874）。实现文件为 `iOS/Babel2/Babel2RootViewController.swift`、`iOS/Babel2/Babel2Localization.swift`、`iOS/Babel2/Resources/Babel2Localizable.xcstrings` 和现有 `Tests/NetNewsWire-iOSTests/Babel2FeatureGateTests.swift`。
- 已覆盖 header/title、真实 syncing 时的 subtitle+glyph、Add 路由、150pt tableHeader 摘要与 Folders、44pt folder/feed 行、24pt favicon/initials、inset selection background，以及 bottom filter 的既有 assets、labels 和不同 pill 宽度；删除 Figma 未使用的左上 settings 可见槽位，保留 Add。
- summary count 由当前 `LibrarySnapshot` 的实际 feed `articleCount` 按当前 scope 求和，不硬编码、不新增 collection total 字段。没有改 DataProviding/Core/adapter/旧 controller，没有新文件、依赖或测试体系。
- 2026-09-24 用户在目标真机冷启动检查标题/同步显示、摘要与 Folders、folder/feed 几何与展开、三档筛选静态/切换、返回后状态，回复“首页验收通过了”。验收方式为用户口头确认，非截图/自动化证据。不同语言、Dark、旋转和其他设备不在本轮已验证范围。

## 历史阶段记录（截至 2026-09-05；audit-only historical reference）

以下保留当时的实现和证据记录。各段“当前”“未提交”“未开始”、临时日志及停止条件均仅描述对应批次；实时状态由上方快照覆盖。A12 截图已在 `aa5196536` 提交，M1 页面消费者已在 `d97c6c0db` 提交；这些提交不等于设备或产品验收完成。

## Phase 1A 当前状态

Phase 1A 的 generation gate、启动顺序、Babel2 root composition、外部动作 no-op 和当前 restoration/teardown 接线已完成本批实现与自动化回归；Gate A 仅完成当前 source/runtime trace 子项，production target/resource allowlist 未通过。状态仍为：**修复中 / 证据待补**，因为 A0–A15 仍要求逐项 runtime/截图/真机证据和 root 复审，不能只凭 52 项 iOS 结果、模拟器 startup trace 或 build 关闭 Phase 1A。当前 production lifecycle 没有可运行的 legacy fallback；旧实现仍留在 target/bundle/磁盘供审计，不能把 simulator startup trace 当成 production package/最终 allowlist 通过。矩阵和证据见 [PHASE1A-ACCEPTANCE.md](PHASE1A-ACCEPTANCE.md)。

2026-09-05 补充：在当前已推送 commit `7b8ff453e` 重新编译 Debug/Release 后，A1（gate 与旧 bootstrap 隔离）、A2（Debug/Release 10 组启动参数矩阵）、A3（Release 忽略参数）、A7（未识别 URL no-op，含真实 route/anchor 状态下的前后截图 SHA-256 比对）四行已产出证据并标记"通过（需 root 复审）"，详见 [PHASE1A-ACCEPTANCE.md](PHASE1A-ACCEPTANCE.md) 对应新增小节与 [VALIDATION.md](VALIDATION.md)。这四行仍待 root 复审终审，且不代表 A4–A6 剩余子项、A8–A15 或目标物理 iPhone 的任何一项关闭。

2026-09-05 同日第二批（commit `fb0a43f14`，已推送）：A13（启动路径无 blank.html/WebKit）产出证据并标记"通过（需 root 复审）"。A8（识别外部动作）与 A10（restoration/teardown）各自的部分子场景也已验证——A8 的 4 种已注册 URL（showunread/showtoday/showstarred/addFeed）子集、A10 的真实后台↔前台切换子场景——但 shortcut item/notification response（A8）和真正的 scene disconnect/真机 30-cycle（A10）用 `xcrun simctl` 脚本化不出来，这两行整体状态仍是"实现进行中/证据待补"。详见 [PHASE1A-ACCEPTANCE.md](PHASE1A-ACCEPTANCE.md) 对应新增小节。

2026-09-05 同日第三批（已提交 `733275b72`，未推送）：A4（persisted generation 边界）、A5（stale/corrupt fail-closed）、A9（restoration 校验矩阵）——在 `Babel2FeatureGateTests.swift` 新增两个测试方法，补齐了 A5/A9 点名但原来没测过的输入（真正损坏的字节、空 routes、首 route 非 home、未知 route 值），全量 Debug iOS test suite 重新跑过一遍全绿。这三行的诚实缺口是同一个：全部证据都停在"直接调用生产的校验/root 组装函数"，还没有一条经过真实 `UISceneSession.stateRestorationActivity` 触发的 `SceneDelegate.scene(_:willConnectTo:options:)`——`UISceneSession` 没有公开初始化方法测试代码构造不出来，`simctl` 也没有命令能复现"系统真的回收 scene 又冷启动恢复"这个场景，需要真机或者一次代码改动（加测试 seam），本轮没有做后者。三行均标记"实现进行中/证据待补"。详见 [PHASE1A-ACCEPTANCE.md](PHASE1A-ACCEPTANCE.md) 对应新增小节。

2026-09-05 同日第四批（已提交 `ef28c9244`，已推送）：A11（30-cycle re-entry）产出证据并标记"通过（需 root 复审）"——除了已有的进程内 30 次单元测试，新增一个含真实视图加载与路由校验的进程内 30 次测试，另外做了本轮 Phase 1A 里唯一一次"30 次真实冷启动"（30 个不同 PID/session，全部 valid+complete+零 legacy）。A15（single owner + Gate A 白名单）在做交叉引用时，独立复核了现有 `Babel2BoundaryTests` 的扫描范围，**发现并修复了一个真实缺口**：扫描目录漏了 `iOS/Babel2Integration/` 和 `iOS/Babel2ExternalActionParser.swift`，补扫后发现的一处 `AccountManager.shared` 使用是合理的（唯一集中的真实数据桥接层）但此前无自动化盯防，已加精确白名单纳入监控。A15 的 persisted identity 边界（`LegacyIdentityCompatibility` 仍零实现，如实记录现状）和完整 target/resource allowlist 仍是 open，整行标记"实现进行中/证据待补"。详见 [PHASE1A-ACCEPTANCE.md](PHASE1A-ACCEPTANCE.md) 对应新增小节。

2026-09-05 同日第五批（尚未提交）：A12（0.5/1.0/2.0 秒启动截图）。第一次尝试假设"调用 launch 的那一刻"等于"进程真正开始跑"，结果三张截图全部拍在真实进程启动之前，已如实丢弃不冒充通过（教训见 LESSONS.md 第 26 条）。改正后：冷启动后密集连拍 12 张（不设时间假设，让工具调用开销自然形成采样间隔），事后用同一轮真实 trace 的 processEntry 精确挂钟时间反推每张截图的真实偏移，选出最接近 +0.5s/+1.0s/+2.0s 的三张（实测 +0.307s/+1.108s/+2.272s）。三张都是同一个 Babel2 Feeds 页面，只有数据/图标从无到有的正常渐进加载，没有旧版着陆页、空白跳变或重复壳。标记"结构性证据通过（需 root 复审）"——图标裁切、加载观感这类主观判断仍需用户自己看四张截图确认（已通过 SendUserFile 发送），不由此证据替代。详见 [PHASE1A-ACCEPTANCE.md](PHASE1A-ACCEPTANCE.md) 对应新增小节。

独立审查记录的 P0 根因是：generation gate 晚于 `AppDelegate` 的 legacy lifecycle/bootstrap，导致仅检查 storyboard 是否存在不足以证明隔离成立。本批把决策移到 AppDelegate 初始化边界，并让 SceneDelegate 只创建 Babel2 root；验收仍必须用 launch trace 证明 gate 先于所有旧副作用，不能把“Babel2 scene 的 storyboard 为 nil”单独当作根因修复或完整通过证据。

本批 r8 fresh 验证环境为 iPhone 17 / iOS 27 Simulator，UUID `555E35FA-6BFE-45F0-BCFC-0819FFE48CD2`。package tests 为 30/30；全量 Debug iOS tests 为 XCTest console 34/34 + Swift Testing 18 = 52，xcresult 为 52/52 passed、0 failed；Debug 与 Release build 均 exit 0。Release-r10 二进制 SHA 为 `aff2619cde1051078bbe58a6727b17138b2f114f18945cd5ea141ee113cda1c2`；no-args PID 66644 与 cold Genesis-v2 PID 67540 的 raw OSLog 均可逐条解析，分别为 8 events、同 session 内严格顺序且 final valid/complete。日志/result 路径和精确命令见 [VALIDATION.md](VALIDATION.md)。r5 的失败日志、r8 warm Genesis 的 7-event 失败和早期截断 OSLog 均保留为失败/中间证据；r6 的历史全量数字是 44，r7 是 45，均不冒充当前 r8 cold 结果；旧安装包或截图不能替代当前 runtime/真机/视觉证据。

## 已完成或已有当前基础

- v0.5、v1.0、v1.1 的 Git 版本锚点已经建立；v2.0 保留给真正完成并验收的 Babel 2.0。
- `Babel2Core` 与 `Babel2UI` 的 Phase 0 隔离基础已提交，Core 保持平台无关，UI 只依赖 Core。
- Babel 2.0 产品合同和运动合同 amendment 已在 `1269bb9087d896a7a9e29f174461d60b47134575` 完成规范版本 QA、提交并获授权非 force 推送成功，状态为 `completed/committed`；产品实现仍未完成。
- M1 运动基础已在本地 commit `5db240499806bc4cae9be0b82194c838a32229de`（message：`Babel 2.0 M1: add interruptible motion foundation`）中提交，精确范围为 14 files / 2618 insertions。此前绑定该 M1 commit 的第 5 轮独立 QA 曾 PASS：30 项 package tests、8 项真实 iOS UIKit runtime tests、8 项 Boundary/Shell tests 及 Debug build 在 iPhone 17 / iOS 27 Simulator 成功；这不是本次 Phase 1A final QA 的结果，不能覆盖 A0–A15 尚缺的 runtime/真机/视觉证据。真机 120Hz 手感与 OSLogStore consumer integration 仍 pending。该 commit 已于 2026-09-05 获用户明确授权并推送，`git fetch` 核实 `origin/codex/reeder-classic-rebuild` 现含此 commit（见上方 Git 快照）；页面 consumer 接入、真机 120Hz 手感与 OSLogStore consumer integration 仍 pending，推送本身不代表这些验收关闭。
- Babel 2.0 AppIcon 的 Light/Dark/Mono 静态设计、独立 asset catalog、逐图检查、独立 QA、actool 和小尺寸结构检查已完成，并已在 `9fda5c565` 提交。用户先选定 Dark，并明确授权“生成好直接作为 Babel 2.0 图标”；早期“烧焦/全局黑蒙版”Light 被否决，随后按“亮木桌+逐本独立暗色封面+干净页边”重生成的当前 Final 才是提交资产。Round 4 草稿不构成回退。该状态只证明设计/静态资产完成，不证明 runtime appearance、模拟器或真机 Home Screen 接入；也不声称用户已逐像素口头确认最终 Light。Dark 的可复现 master 是仓库内 `Design/Babel2/Icon Concepts/Final/Babel2AppIcon-Dark.png`，临时用户附件仅作 provenance。

## Phase 2A 单轨实现与 fresh correction 验证

- 生产入口：`Babel2FeatureGate.decision(buildChannel:)` 在 AppDelegate 初始化边界固定返回 Babel2；没有 launch-argument 或 persisted-generation 选择入口。SceneDelegate 统一创建 Babel2 navigation/root；URL、shortcut、notification、NSUserActivity 和 restoration 输入保持 Babel2，识别动作只解析并安全 no-op，不切旧 root。
- 旧路径边界：AppDelegate/SceneDelegate 不再调用旧 lifecycle/bootstrap、Main storyboard、RootSplit/SceneCoordinator、BabelShell 或 WebView bootstrap；`Main.storyboard` 和旧实现目录保留在磁盘，未改 full target membership。canonical external parser 唯一 owner 为 `iOS/Babel2ExternalActionParser.swift`。trace-only diagnostic event/source IDs 不构成对旧 UI 的 production 依赖。
- Launch trace：一个 AppDelegate-owned recorder 从 process-entry/decision 开始，事件带 session/build/sequence/uptime/source/detail；legacy counters 从事件流派生，任一 legacy event 立即使 trace invalid，不能用硬编码零或 test suppression 得出 clean 结论。SceneDelegate 只记录 UIKit 实际 observed configuration，不合成 expected configuration；selected event 的 name 是真实 lookup input，observed event 的 name 是 UIKit 返回值（允许 nil，非 nil 必须 exact），并记录 privacy-safe tri-state match。缺失、错序、session/uptime/sequence、delegate metatype、storyboard 证据均 fail-closed。Root/container/content 记录最小 geometry/window/safe-area/key/hidden detail，root identity 由真实 `root is Babel2NavigationController` 记录；content first frame 不代表数据/截图验收。
- Launch logging：每个 event 以独立短 JSON line 输出，result 以不含 events 的短 JSON line 输出；`lastLoggedLaunchSequence` 防止重复输出，首帧后的 legacy WebView probe 拒绝追加，teardown 记录后也调用同一 `logLaunchTrace()`。这解决了单条长 trace 被 OSLog 截断的问题，但不替代 A10 reconnect/disconnect 证据。
- Legacy probes：RootSplit、SceneCoordinator、BabelShell、WebViewProvider 和 PreloadedWebView 仅在现有初始化边界记录事件；WebView/blank probe 只在 Babel2 content-surface first frame 前有效。BabelShell fixture 使用独立 recorder sink，不写 live AppDelegate session；Babel2FeatureGateTests 不再主动构造旧 coordinator fixture。
- Fresh package：`env -u MERCURY_CLIENT_ID -u MERCURY_CLIENT_SECRET -u FEEDLY_CLIENT_ID -u FEEDLY_CLIENT_SECRET -u INOREADER_APP_ID -u INOREADER_APP_KEY swift test --package-path Modules/Babel2UI`，exit 0，Swift Testing 30/30 项通过；日志 `/private/tmp/babel2-phase2a-r8-package-tests-final.log`。
- Fresh Debug iOS tests：同一目标，exit 0；console 为 XCTest 34/34（Babel2FeatureGate 26 + Babel2MotionDriverRuntime 8）并有 Swift Testing 18 项，合计 52；xcresult summary 为 `totalTestCount=52`、`passedTests=52`、`failedTests=0`。日志 `/private/tmp/babel2-phase2a-r8-ios-debug-tests-final.log`，result `/private/tmp/babel2-phase2a-r8-ios-debug-tests-final.xcresult`，DerivedData `/private/tmp/babel2-phase2a-r8-ios-debug-tests-final-dd`，escalated summary `/private/tmp/babel2-phase2a-r8-ios-debug-tests-final-xcresult-summary-escalated.json`。sandbox summary 的权限失败保留在 `/private/tmp/babel2-phase2a-r8-ios-debug-tests-final-xcresult-summary.json`。
- Fresh Debug build：同一目标，exit 0，`** BUILD SUCCEEDED **`；日志 `/private/tmp/babel2-phase2a-r8-debug-build-final.log`，result `/private/tmp/babel2-phase2a-r8-debug-build-final.xcresult`，DerivedData `/private/tmp/babel2-phase2a-r8-debug-build-final-dd`。
- Fresh Release build：同一目标，exit 0，`** BUILD SUCCEEDED **`；日志 `/private/tmp/babel2-phase2a-r8-release-r10.log`，result `/private/tmp/babel2-phase2a-r8-release-r10.xcresult`，DerivedData `/private/tmp/babel2-phase2a-r8-release-r10-dd`；可执行文件 SHA `aff2619cde1051078bbe58a6727b17138b2f114f18945cd5ea141ee113cda1c2`。
- Production standalone trace：r10 app fresh uninstall/install 后，无参数 metadata/command `/private/tmp/babel2-phase2a-r8-standalone-r10-noargs-metadata.json`、`...noargs-command.txt`，PID 66644，raw OSLog `/private/tmp/babel2-phase2a-r8-standalone-r10-noargs-final-oslog.ndjson`，独立验证 `/private/tmp/babel2-phase2a-r8-standalone-r10-noargs-final-validation.json`；冷 Genesis-v2 metadata/command `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-metadata.json`、`...genesis-cold-v2-command.txt`，PID 67540，raw OSLog `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-oslog.ndjson`，独立验证 `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-validation.json`。两次均为 8 events、final valid/complete；source/pre/post installed SHA 均为 `aff2619cde1051078bbe58a6727b17138b2f114f18945cd5ea141ee113cda1c2`。第一次未卸载重装的 warm Genesis 7-event `sceneConfigurationSelectionMissing` 失败证据保留，不能当作 cold 结果。
- Bundle boundary：r10 Release inventory 仍含 `Base.lproj/Main.storyboardc`、`blank.html`、多个 `.nnwtheme`/HTML template、3 个 `.appex`，并可见旧 `RootSplit`/`PreloadedWebView` 等编译/资源痕迹；这只是当前 target/bundle inventory，不是 A13 或 Gate A allowlist 通过证据。BoundaryTests 尚无 target-membership/resource allowlist gate；A0/A1/A6/A8/A10/A12/A13/A15 的完整逐项证据仍 pending。

## 进行中

- M1：contract layer 已完成，本地 commit 已通过第 5 轮独立 QA；2026-09-05 已获授权推送并经 `git fetch` 核实远端已含此 commit。同日随后完成页面 consumer 接入（`Babel2NavigationPopMotion`，见下方新增小节）；2026-09-08 用户在真机上确认左边缘滑动返回跟手、中途松手可正确取消弹回（用户口头确认，非 Instruments/自动化证据，见 VALIDATION.md「M1 页面消费者：真机手感验收」）。深栈/根路由/旋转/非边缘误触发/120Hz 具体帧率数据和 OSLogStore consumer integration 仍 pending。
- 合同：amendment `1269bb9087d896a7a9e29f174461d60b47134575` 已完成规范版本 QA、提交并非 force 推送；动态工作树/远端状态仍须实时检查。
- 项目记录：本目录文档首次建立；这些新文件在本次记录完成前也属于未提交范围。
- 图标：设计/静态资产已完成并提交；Light/Dark/Mono 的最终 runtime appearance、模拟器解析和设备 Home Screen 仍待接入和检查。

## 未开始或尚未达到验收门槛

- Babel 2.0 feature gate、独立 root composition、统一 navigation controller 和可重复进入/退出（r8 自动化与目标 Simulator startup trace 已通过对应范围；Phase 1A 仍为修复中 / 证据待补，待逐项 runtime/截图/真机、资源/allowlist 和 root 复审）。
- Feeds/Library root、Starred/Unread/All 过滤与正确计数、源/文件夹可见性。
- Feed hero 延伸至状态栏/动态岛、透明度和连续收缩动画。
- Reader 首屏标题/作者、连续收缩、进度环、性能/预加载、翻译稳定性和无重影。
- 横向正文图片 full-bleed 直角、Reader 与内置浏览器双向边缘手势。
- 统一底栏、普通分享和 tap-only 生成长图。
- 新 Settings IA、主题色语义、订阅源管理、添加订阅源搜索/发现。
- 中英文完整 i18n、loading/empty/error/offline/sync 状态和单一 loading owner。
- 旧视觉/死代码清理；技术命名和系统 identity 的完整迁移按路线 A 延后，不能现在全局替换。
- 模拟器回归、性能测量和目标 iPhone 冷热启动、滚动、手势、外观、数据恢复验收。

## 当前工作树边界

本批 Phase 2A 实现修改/新增范围包括：`iOS/AppDelegate.swift`、`iOS/SceneDelegate.swift`、`iOS/Babel2/**`、`iOS/Babel2Integration/**`、`iOS/Babel2ExternalActionParser.swift`、`Tests/NetNewsWire-iOSTests/Babel2FeatureGateTests.swift`、`Tests/NetNewsWire-iOSTests/Babel2BoundaryTests.swift` 和本目录中与单轨状态/证据直接相关的文档。工作树中其他改动属于既有工作，不能由本任务清理、回滚或覆盖；包括工程配置、M1 motion 源码/测试、图标概念与最终资产、Figma/比较图产物以及历史功能代码修改。被 `.gitignore` 忽略的 `SecretKey.swift` 只因 scheme pre-action 改写，已恢复基线，不纳入本批 diff。

允许未来实现代理修改的范围，必须由当前 Slice 的任务单明确列出；不得借“清理”之名触碰存量数据 identity、外部 bundle/App Group/Keychain/Core Data/GitHub 身份或未授权的历史代码。

## 下一步顺序

1. 由 root 复审本批 diff、静态边界和 `PHASE1A-ACCEPTANCE.md` 中 A8/A14 的新单轨语义；不把 r5 失败日志或旧 fallback 文字当作当前行为。
2. 补齐 A0–A15 尚缺的启动 trace 文件、A10 scene reconnect/disconnect、0.5/1/2 秒截图、模拟器状态矩阵和目标 iPhone 冷热启动/恢复/手势/性能/视觉证据；当前 52 项 iOS results、Release-r10 no-args/冷 Genesis startup trace、Debug/Release build 只能关闭对应自动化/编译/启动层，不能替代 production package resource allowlist、A13 WebKit/blank runtime、A15 exact allowlist 或目标 iPhone 验收。
3. Phase 1A 通过 root 复审后，取得 `5db240499806bc4cae9be0b82194c838a32229de` 的明确推送授权，并核对本地 HEAD、remote-tracking 和 hosted remote。
4. 统一导航壳已消费 M1（见下方新增小节）；下一步是补做真机 120Hz 手感与 OSLogStore consumer integration，再按 REQUIREMENTS.md 的 Slice 顺序推进页面；最后才做真机稳定后的分阶段技术改名和旧代码删除。

## Phase 3：账户限定 Feed→Article 垂直切片（2026-09-01，Asia/Tokyo）

本节为 append-only 当前状态；不改写上方 Phase 2A 历史。Phase 3 的最小数据切片已在未提交工作树实现并通过当前自动化矩阵，不能据此宣称 Babel 2.0 完整产品、真机通过或 Phase 1A 完成。主控复审结论限定为“实现代码 P0/P1=0”。Phase 3 持久 evidence gate 已关闭；入口为 [evidence/phase3/manifest.json](evidence/phase3/manifest.json)。

实现文件精确清单：

- `Modules/Babel2UI/Sources/Babel2Core/Contracts.swift`
- `Modules/Babel2UI/Sources/Babel2Core/Snapshots.swift`
- `Modules/Babel2UI/Tests/Babel2UITests/Babel2UITests.swift`
- `iOS/Babel2Integration/Babel2LiveDataAdapters.swift`
- `iOS/Babel2/Babel2DataAdapters.swift`
- `iOS/Babel2/Babel2RootViewController.swift`
- `iOS/Babel2/Babel2LibraryViewControllers.swift`
- `iOS/Babel2/Babel2SceneComposition.swift`
- `Tests/NetNewsWire-iOSTests/Babel2FeedReaderTests.swift`
- `NetNewsWire.xcodeproj/project.pbxproj`（仅加入上述独立 iOS 测试到既有 group/Sources 的最小 membership）
- 本文件及 `HANDOFF.md`、`PHASE1A-ACCEPTANCE.md`、`VALIDATION.md`、`README.md`（本次同步）

代码边界：Feed/Article identity 现在显式携带 `accountID`、`feedID`、`articleID`；文章 URL 可缺省，仍保留有缓存正文的文章；新增窄的 `feedArticlesSnapshot(for:)` 查询，Feed 点击按三元 identity 定位真实 Account+Feed 并复用 `account.fetchArticlesAsync(.feed(feed))`；根页只读取账户/文件夹/Feed 元数据，不遍历所有文章，也不再合并 Today/Unread/Starred SmartFeeds。根页不显示伪造的 0；不可用计数隐藏，进入 Feed 后用已加载列表数量更新 header。已加载 snapshot 直接传给 reader；article/action cache 与 lookup 均按账户限定并复核三元组；Root/Feed/Article 加入 generation、取消和 stale identity guard；Open Original 通过可注入 closure 接系统打开，缺 URL 时不显示按钮。未修改 Account、Articles、ArticlesDatabase、SmartFeeds，未引入新的 repository/cache/sync engine，也未扩展 Starred/Unread/All、Folder IA、WebKit 完整阅读器或其他后续功能。

自动化与构建证据：持久化摘要入口为 [evidence/phase3/package-summary.json](evidence/phase3/package-summary.json)、[evidence/phase3/test-results-targeted-summary.json](evidence/phase3/test-results-targeted-summary.json)、[evidence/phase3/test-results-full-summary.json](evidence/phase3/test-results-full-summary.json) 和 [evidence/phase3/build-results.json](evidence/phase3/build-results.json)，对应 Package `31/31`、targeted `4/4`、full Debug `56/56`、Debug r3/Release r1 成功。`/private/tmp/babel2-phase3-*.log` 与 `.xcresult` 仅为原始临时来源；中间失败与无效 0-test 证据不删除，持久索引见 [evidence/phase3/validation-iterations.json](evidence/phase3/validation-iterations.json) 和 [VALIDATION.md](VALIDATION.md)。

运行时边界：Release r1 app 已安装到目标 iPhone 17 / iOS 27 Simulator（UDID `555E35FA-6BFE-45F0-BCFC-0819FFE48CD2`），未卸载、未清空数据、未添加订阅；无参数 cold launch 后 Feeds root 可见。持久化 runtime 入口为 [evidence/phase3/runtime-summary.json](evidence/phase3/runtime-summary.json)、[evidence/phase3/runtime-probe.json](evidence/phase3/runtime-probe.json)、[evidence/phase3/live-trace-summary.json](evidence/phase3/live-trace-summary.json) 和 [evidence/phase3/cold-launch-final.png](evidence/phase3/cold-launch-final.png)；`/private/tmp/babel2-phase3-runtime-r1/` 仅为原始临时日志/截图来源。真实本地数据证据为 active `OnMyMac` account、10 个 FeedSettings、`articles/statuses/search` 各 424 行、SQLite integrity `ok`。Simulator 没有可用 tap/accessibility 驱动，因此单源选择、文章正文和 Open Original 的 runtime 链路为 `INTERACTION BLOCKED`；未使用 deep link 或伪造数据。确定性测试覆盖 snapshot 传递、缓存正文、无 URL 按钮、迟到结果拒绝和 renderer cancellation。启动 trace 虽记录到 7 个事件并显示 root/content frame，但结果含既有 `sceneConfigurationSelectionMissing`、`isValid=false`，不能当作完整 Phase 1A runtime trace 通过。

仍开放：cache 先读后验证与无界问题、同名标题稳定 tie-break、Starred/Unread/All 与 Folder IA、HTML/WebKit 完整 reader、translation/media/share/long image、同步引擎、icon/Figma 视觉润色、旧 storyboard/nib 与 3 个 `.appex` 的 bundle/allowlist 清理、目标物理 iPhone、性能/视觉/手势和完整 scene 恢复。SecretKey 与六个环境变量状态的持久入口为 [evidence/phase3/secret-status.json](evidence/phase3/secret-status.json)；无 commit、无 push。

## Phase 3B：真实 Simulator Feeds→source→Article UI driver（2026-09-01，Asia/Tokyo）

Phase 3B 在 Phase 3 的账户限定数据切片之上增加一个最小 XCUITest driver，并以目标 iPhone 17 / iOS 27 Simulator 的真实现有数据验证 Feeds→单一 source→缓存文章正文→返回根页。这里的“P0/P1=0”仍只指实现代码复审，不是整个产品或 Phase 1A 的结论。持久化入口为 [evidence/phase3b-ui/manifest.json](evidence/phase3b-ui/manifest.json)，构建与 test-without-building 索引为 [build-summary.json](evidence/phase3b-ui/build-summary.json)，脱敏运行时探针为 [runtime-probe.json](evidence/phase3b-ui/runtime-probe.json)。

本切片的精确新增/修改文件为：`Tests/NetNewsWire-iOSTests/Babel2FeedReaderUITests.swift`；`NetNewsWire.xcodeproj/project.pbxproj`（新增独立 UI-testing target 及其最小 membership/dependency）；`NetNewsWire.xcodeproj/xcshareddata/xcschemes/NetNewsWire-iOS UI Driver.xcscheme`；`xcconfig/NetNewsWire_iOSUITests_target.xcconfig`；`iOS/Babel2/Babel2LibraryViewControllers.swift`（仅增加 feed/article/body accessibility identifiers）；以及 `Design/Babel2/Project/evidence/phase3/manifest.json` 的 tree hash 方法修正和本节所链接的 `evidence/phase3b-ui/**`。没有改现有 iOS scheme/test plan，没有 preaction、launch 参数或环境注入。

静态检查中，sandbox `xcodebuild -list` 的 CoreSimulator/权限失败原始记录保留；同一检查在 escalated 环境成功枚举 `NetNewsWire-iOSUITests` 与 `NetNewsWire-iOS UI Driver`，target build settings 确认 generated Info.plist 且无 `TEST_HOST`/`BUNDLE_LOADER`。Release `build-for-testing` r1、r2 均成功。r1 UI test 实际执行 1 个但因修复前的通用第二张 table lookup 失败，分类为 `UI_SELECTOR_TIMEOUT`；该失败证据保留，不计为最终通过。稳定 identifier 后，r2 与同一产物重复的 r3 均实际执行 1/1 passed。

真实 UI driver 断言了：无参数、六个 secret 环境变量 unset 的启动；root `babel2.feeds.table` 的 10 个现有 feed rows；按当前 UI 顺序选择 source；`babel2.feed.articles.table` 与缓存文章 row；正文非空、非 `Loading`、非纯标签/script；Open Original enabled 路径将 `SafariViewService` 置于 foreground；以及 article back→feed back 后 root 的 10 行恢复。root/feed/back 三张不含正文/URL 的截图持久化于 [screenshots/](evidence/phase3b-ui/screenshots/)；其中 feed.png 已从 r2 原始附件按 [screenshot-inventory.json](evidence/phase3b-ui/screenshot-inventory.json) 的确定性命令裁为 1206×390 的顶部 status/header/feed name/count 区域，不含文章标题、日期、正文或 URL；reader/after-browser 原始附件只留在临时 xcresult，未复制正文、标题、URL 或 UI hierarchy。

数据不能标成只读：基线与 UI 序列中观察到 `articles/statuses/search` `424→425→426`，同时出现 data-container UUID 轮换；同一 r2 产物的 r3 重复为 `426→426`，FeedSettings 始终 10，SQLite integrity 始终 `ok`。状态明确记为 `UNEXPECTED_DATA_MUTATION`；增量原因未证实，不归因为后台同步，也不把它解释成测试必然写入。旧 Phase 3 Release r1 hash 只作为 provenance，新 Phase 3B r2 artifact/installed executable hash 以 evidence manifest 为准。

Phase 3B 本轮已应用截图隐私边界和 bundle tree digest 的 P1 evidence correction，并通过独立只读复核；manifest 状态为 `phase3b_evidence_gate_closed_after_independent_recheck`，范围仅是 Phase3B implementation + automation + persistent evidence，未暗示 Phase1A 或全产品完成。复核仅验证 7 个 JSON、裁剪截图/inventory、245 文件 bundle/hash/content-identical、logs/xcresults/counts、docs/security/refs，未重跑 build/test/install/launch。当前 bundle 校验使用 bundle-root-relative、无 `./` 前缀、按路径排序、每条 `SHA256  relative/path\n` 的拼接摘要，BFT r2 与 installed r3 均为 245 文件、tree SHA `64ef2ec5…`，旧绝对路径 digest 仅作 historical/path-bound provenance。Phase 1A、真实物理 iPhone、完整 scene 恢复、视觉/性能人工验收、旧 storyboard/nib 与 3 个 `.appex` allowlist、数据增量原因、cache first-hit/验证与无界问题、同名 tie-break P2，以及 Open Original 无 URL 的语义缺口 P2 仍 OPEN；enabled URL 路径到 SafariViewService 的真实通过仍保留。SecretKey 和 `.gyb` 目标 hash、六个环境变量 unset 状态仍见 [evidence/phase3/secret-status.json](evidence/phase3/secret-status.json)；无 commit、无 push。

## Feeds/Timeline 卡片打磨 checkpoint（2026-09-05，Asia/Tokyo）

本节是与 Phase 2A/M1 主线并行、独立于 HANDOFF.md「当前下一任务」的一次打磨收口；不改写上方 Phase 2A/3/3B 结论，也不代表 Phase 1A、M1 或 REQUIREMENTS 中任何 motion/同步语义行的完成。

接手时工作树已存在 7 个已跟踪文件的未提交改动（Feeds 文件夹层级、`BabelPalette` 统一配色、默认档 `.all→.unread`、筛选按钮改 Figma 校准像素坐标、Timeline 卡片加缩略图与翻译标题副标题行）与 9 张 `evidence/stabilize/feeds-v1*`/`timeline-v1*` 截图；本轮只做验证、修复、文档同步与提交，未新增产品范围。

验证过程中用全量 `xcodebuild … test`（此前只跑过 package tests 和 `xcodebuild … build`，未覆盖真实 UIKit 交互）发现 2 个真实回归并已修复：筛选按钮在容器宽度未知时永久停留在零尺寸 frame（`Babel2RootViewController.swift` 的 `layoutScopeControlsIfNeeded()`）；`testStaleScopeResultCannotPublishAfterLatestIntentChanges` 因默认档改为 `.unread` 后沿用旧的竞态角色分配而永久超时。完整根因、修复方式与前后测试数字见 [VALIDATION.md](VALIDATION.md) 「Feeds/Timeline 卡片打磨 checkpoint」一节；教训记录见 [LESSONS.md](LESSONS.md) 第 21 条。

修复后 fresh 证据：Babel2UI package tests 32/32；全量 Debug iOS tests `xcresulttool` summary `failedTests:0`、`passedTests:62`（console XCTest 44 + Swift Testing 18）；Debug build 随 test 一并 `BUILD SUCCEEDED`。环境为 iPhone 17 / iOS 27 Simulator `555E35FA-6BFE-45F0-BCFC-0819FFE48CD2`，六个第三方 secret 环境变量本轮全程 unset。

提交状态：本地提交 `3dfd7188289fe06e770dc1408b8eaf39706dcc98`（`git rev-parse HEAD` 核实；20 files changed, 902 insertions(+), 228 deletions(-)），父提交为 `3e4f5e7f8f20af2737d375102b6ec420ba84c206`。2026-09-05 随 M1 一起被推送（用户对 M1 的推送授权覆盖了这次线性推送里 M1 之后的全部本地提交，见上方 Git 快照）；`git fetch` 核实 `origin/codex/reeder-classic-rebuild` 现为 `c4335576d55b46431cd58e5b26f84ca10407fd9f`，即本次 checkpoint 之后再加一个 SHA 回填提交（下条）。提交后 `git status --short --branch` 确认工作树干净（无残留改动）。

仍未关闭：`evidence/stabilize/` 截图未经独立复核，不构成模拟器或真机验收证据；REQUIREMENTS 中 Feed/Timeline header 无空带、pFilter selection pill/列表/计数同 progress 两行要求的动效同步语义本次未触及，维持"未开始"；M1 推送授权与 Phase 1A 剩余 A0–A15 证据缺口独立于本节，状态仍以上方 Phase 2A 记录与 HANDOFF.md 为准。

## M1 页面消费者接入：Babel2NavigationPopMotion（2026-09-05，Asia/Tokyo，尚未提交）

按 MOTION-CONTRACT.md 第 6 节"Navigation pop"，把已经过独立 QA 的 M1 引擎（`Babel2MotionDriver`/`GesturePolicy`/`MotionProjection`，均未改动）接到 `Babel2NavigationController` 的左边缘滑动返回手势上。这是 M1 落地的第一个、也是范围最窄的消费者——合同里点名的其它 owner（Reader→Browser 右边缘手势、文章上下翻页、Reader 收缩标题、Feed hero、pFilter）都不在本次范围内，仍是"未开始"。

**实现**：新文件 `iOS/Babel2/Babel2NavigationPopMotion.swift`。只接管"手指从左边缘拖拽返回"这一条交互路径——`UIScreenEdgePanGestureRecognizer(edges: .left)` 装在 `navigationController.view` 上，系统默认的 `interactivePopGestureRecognizer` 被禁用（`isEnabled = false`，避免两个手势同时抢同一个动作）；点击返回按钮触发的 `popBabel2(animated:)` 完全不受影响，继续走系统默认动画，因为这个类的 `UINavigationControllerDelegate` 方法只在"边缘手势正在进行"时才返回自定义的动画/交互控制器，其余时候返回 `nil`。进度映射、松手后 finish/cancel 的投影判定，全部复用 M1 已有的 `MotionProjection`/`Babel2MotionDriver`，这个新文件本身不重新实现任何数学，只做"手势事件 → driver 调用 → 真实 view transform"的翻译，对应合同公式 `p = clamp(x/W, 0,1)`、`currentX = W*p`、`previousX = -0.22*W*(1-p)`、`shadowOpacity = 0.18*(1-p)`。`Babel2NavigationController.swift` 只加了 3 处小改动：持有一个 `popMotion` 实例、在 `viewDidLoad` 创建、在 `tearDown` 释放。

**验证**：`Tests/NetNewsWire-iOSTests/Babel2FeatureGateTests.swift` 新增 12 个测试方法，直接调用 `beginPop()`/`updatePop(translationX:)`/`endPop(velocityX:forceCancel:)`（而不是通过真实手势识别器——XCTest 无法合成真实触摸），覆盖：只有一页时拒绝开始、开始后重复调用不替换 token、位移到进度的换算与两端 clamp、没有活跃 token 时更新/结束是安全 no-op、根据末端投影正确判定 finish 或 cancel、手势级强制取消（`.cancelled`/`.failed`）无视进度和速度、系统交互手势被禁用、自己的边缘手势被正确装上/卸载、转场代理只在边缘手势进行中才返回非 nil（push 操作永远不拦截）。12/12 通过；全量 Debug iOS test suite 重新跑过，77/77 通过，0 失败。

**诚实的证据边界（记入 LESSONS.md 第 27 条）**：这些测试全部是在没有真实 window 的测试环境里跑的。实测发现 `UINavigationController.popViewController(animated:)` 在没有 window 时**不会**调用 `UINavigationControllerDelegate` 的转场方法（`animationControllerFor:`/`interactionControllerFor:`/`startInteractiveTransition`）——`viewControllers` 数组本身会同步更新，但转场代理整条链路被跳过。这意味着本次测试只覆盖了 M1 driver 的状态机和这层胶水代码的调用是否正确，**没有**、也**不可能**在无窗口环境下覆盖真实的 `transitionContext` 生命周期（`finishInteractiveTransition`/`cancelInteractiveTransition`/`completeTransition`）和实际的 view transform 渲染。这部分——也就是"手指拖的时候画面到底跟不跟手、松手后动画顺不顺、取消时会不会真的弹回原页面"——只能靠真机或者至少有真实窗口的模拟器交互验证，属于用户负责的那一半，本节不冒充已验证。

限制：本次只做了 Navigation pop 这一个 owner；`UIScreenEdgePanGestureRecognizer` 本身的边缘宽度用的是系统默认区域，没有额外用 `GesturePolicy.isInsideEdge` 强制卡在合同建议的 24–32pt（`to-tune`，边缘识别本身已经由系统识别器结构性保证，属于合理的实现简化）；没有触碰 Reader→Browser、文章翻页、Reader 收缩、Feed hero、pFilter 这些 MOTION-CONTRACT.md 里其余的 owner。
