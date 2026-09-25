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
