# 未提交工作区账本

> 快照日期：2026-08-27
>
> 基线：`design/custom-dock` @ `e2b8fd153`
>
> 目的：解释 44 个未提交文件分别属于什么功能、依赖什么、证据到哪一步，并给出可审查的拆分顺序。

> 真机验收：2026-08-27，用户确认本账本所列下一阶段验收项目均无问题。这个结论绑定于当日当前工作区；后续代码变化需要按影响范围回归。

## 状态定义

- **构建通过**：只能证明当前代码能通过编译或现有静态检查。
- **行为验证**：有真实页面、数据或离线 DOM 测试支撑，但不等于真机视觉验收。
- **用户验收**：进度记录明确记载用户在当时版本上确认。
- **待复验**：后来又改过，或者失败版本被重写后没有最终用户确认。

## 建议拆分为 9 个功能包

### A. 统一订阅发现与凭据设置

**目标**：关键词并行搜索四类来源，按组展示；网址仍走定向解析；凭据独立管理。

**文件**：

- `Shared/Discovery/FeedDiscoveryViewController.swift`
- `Shared/Discovery/FeedSearchResult.swift`
- `Shared/Discovery/FeedDiscoveryKeychain.swift`（新）
- `Shared/Discovery/RedditSearcher.swift`（新）
- `Shared/Discovery/WebsiteSearcher.swift`（新）
- `Shared/Discovery/YouTubeSearcher.swift`（新）
- `iOS/Settings/DiscoveryAPIKeysViewController.swift`（新）
- `iOS/Settings/SettingsViewController.swift`
- `CLAUDE.md` 中对应架构说明

**边界与依赖**：`FeedDiscoveryViewController.swift` 同时包含“新源置顶”的调用，拆提交时要按 hunk 分开。网站关键词搜索依赖非公开 Feedly 端点；Reddit/YouTube 依赖 Keychain 中的用户凭据。

**证据**：iOS/macOS 构建通过；统一分组界面于 2026-08-27 经用户真机验收。外部服务的长期可用性仍不能由一次验收保证。

### B. 试读失败路径与菜单稳定性

**目标**：首次加载失败使用页内错误，避免 push 转场中弹模态；共用菜单等待转场结束，并保证隐形浮层不能锁死整页。

**文件**：

- `Shared/Discovery/FeedPreviewViewController.swift`
- `Shared/Discovery/FeedPreviewArticleViewController.swift`
- `iOS/DesignKit/NNWMenu.swift`

**边界与依赖**：试读文章页同时删除了“长图”工具栏动作；这可以作为同一试读 UX 包，也可独立成很小的提交。`NNWMenu.swift` 是全 App 共用组件，影响范围远大于发现页。

**历史风险**：第一版只检查 `view.window` 和宽度，被真机日志证伪；当前第二版改查 `transitionCoordinator`，并增加禁用交互、0.8 秒补显/退场、dismiss 失败强拆三道兜底。

**证据**：构建通过；当前第二版于 2026-08-27 经用户真机验收，无问题。

### C. 取消订阅入口与措辞

**目标**：单源设置页提供取消订阅；所有 feed 删除动作说“取消订阅”，文件夹删除仍说“删除”。

**文件**：

- `iOS/Inspector/FeedInspectorViewController.swift`
- `iOS/Inspector/FeedInspectorViewController+NNWUnsubscribe.swift`（新）
- `iOS/MainFeed/MainFeedCollectionViewController.swift` 中措辞相关 hunk
- `iOS/FeedListEdit/MainFeedCollectionViewController+Edit.swift`
- `Shared/Localizable.xcstrings`
- `i18n/zh-Hans.json`

**历史风险**：第一版给 storyboard 静态表增加 section，真机触发 `NSRangeException`。当前版本改为 `tableFooterView`，不再改变静态表的数据源结构。取消订阅跨账户移除所有落点，失败时留在当前页显示错误；没有撤销入口。

**证据**：构建和本地化检查通过；重写后于 2026-08-27 经用户真机验收，无问题。

### D. 新订阅源置顶

**目标**：所有主动添加的新源在所属容器顶部出现。

**文件**：

- `Shared/FeedOrder/FeedOrderStore.swift`
- `Shared/Discovery/FeedDiscoveryViewController.swift` 中订阅成功 hunk
- `iOS/SceneCoordinator.swift`

**实现边界**：新源取得递减负权重；标准添加流程和发现页添加流程分别接入，因为后者不发送同一条通知。

**证据**：构建通过；2026-08-27 用户确认下一阶段验收项目均无问题。

### E. 正文翻译完整性、缓存与交互

**目标**：保证译文替换不挪动媒体、不吞段落；改善缓存可信度、失败恢复、半途重翻和骨架反馈。

**文件**：

- `Shared/Translation/translation.js`
- `Shared/Translation/TranslationController.swift`
- `Shared/Translation/TranslationCache.swift`
- `Shared/Translation/NNWArticlePageHost.swift`
- `iOS/Article/ArticleViewController.swift`

**主要行为**：

- 媒体或包裹媒体的元素强制形成分组边界。
- 每组最多 6 个顶层元素；译文少还元素时拒绝替换。
- 缓存代际从 6 升到 7，使旧的错误图文分组缓存失效。
- 点翻译不滚动；完整或部分翻译都可长按重翻。
- 骨架色条有看门狗和退出清理；首组流式呈现“吃豆人”效果。

**证据**：JS 检查和完整构建通过；MacRumors 类结构、Daily Portal Z 阅读模式图片结构、Rest of World 缺段问题有真实 DOM/页面数据验证记录；骨架动画、滚动和翻译完整性于 2026-08-27 经用户真机验收。

### F. 标题翻译与模型目录

**目标**：标题批处理遇到内容格式错误时拆批隔离；避免网页标题应用失败后被误判为成功；刷新模型目录时绕过缓存。

**文件**：

- `Shared/Translation/NNWTitleTranslationController.swift`
- `Shared/Translation/TranslationController.swift` 中标题应用 hunk
- `Shared/Translation/OpenRouterCatalog.swift`

**边界与依赖**：`TranslationController.swift` 同时属于正文翻译包，必须按 hunk 拆。拆批最多重试 8 次；传输错误仍采用原有整批失败策略。模型目录的“刷新”改用忽略本地和远端缓存的策略。

**证据**：构建通过；2026-08-27 用户确认下一阶段验收项目均无问题。模型价格是否持续最新属于在线数据问题，不能由一次真机验收保证。

### G. 阅读提取与阅读模式滚动

**目标**：提取时保留真实可见内容和图片地址；切换两套排版时不错误复用像素位置。

**文件**：

- `Shared/ReaderView/ReaderViewExtractor.swift`
- `iOS/Article/WebViewController.swift`

**主要行为**：提取前删除明确 `display:none`、`visibility:hidden` 或 `aria-hidden=true` 的内容；归一化常见懒加载图片属性；切换阅读模式清零滚动位置。

**证据**：Rest of World 和 Daily Portal Z 样本有针对性验证记录；构建通过。代价明确：长文中途切换阅读模式回到开头。

### H. 文章导航、顶栏与视觉稳定性

**目标**：采用系统原文浏览器返回手势；封存过度拖拽翻篇；修正头像进度环同步；恢复暖纸画布。

**文件**：

- `iOS/Article/NNWArticlePaging.swift`
- `iOS/Article/ArticleHeaderBar.swift`
- `iOS/Appearance/AppAppearance.swift`
- `NOTES-archive-overscroll-paging.md`（新）

**终局而非中间方案**：左滑仅在手势结束后打开原文，普通 `present` 保留系统左缘右滑关闭；自定义交互式转场文件已经删除。竖向过度拖拽手势不安装，但实现保留。

**证据**：用户明确选择“右滑返回优先于左滑跟手”；最终代码构建通过，并于 2026-08-27 经用户真机验收。

### I. 列表缩略图、外文图标与文档

**目标**：图片下载前预留布局、修正透明图标灰边，并整理开发记录。

**文件**：

- `iOS/MainTimeline/ArticleThumbnail.swift`
- `iOS/MainTimeline/Cell/MainTimelineCell.swift`
- `iOS/MainTimeline/Cell/MainTimelineCellData.swift`
- `iOS/MainTimeline/Cell/MainTimelineCellLayout.swift`
- `iOS/MainTimeline/MainTimelineModernViewController.swift`
- `iOS/MainTimeline/TimelineStyle.swift`
- `iOS/ForeignFeed/NNWForeignFeedIcon.swift`
- `NOTES-lessons.md`
- `NOTES-progress.md`
- `NOTES-todo.md`
- `NEXT-PROMPT.md`

**边界与依赖**：缩略图是否预留空间只扫描 HTML 得到 URL，不等待位图；无图文章不应出现空占位。外文图标处理必须保持原 alpha。文档包含大量历史中间方案，提交时应和对应代码包一起拆，或最后单独做“状态归档”提交。

**证据**：构建通过；相关布局和视觉项于 2026-08-27 经用户真机验收。

## 跨包文件

这些文件不能按“整个文件一次暂存”的方式拆提交：

| 文件 | 涉及功能包 |
|---|---|
| `Shared/Discovery/FeedDiscoveryViewController.swift` | A 统一发现、D 新源置顶 |
| `Shared/Translation/TranslationController.swift` | E 正文翻译、F 标题翻译 |
| `iOS/MainFeed/MainFeedCollectionViewController.swift` | C 取消订阅措辞，另含 `+` 菜单回归修复 |
| `NOTES-progress.md` / `NOTES-lessons.md` / `NOTES-todo.md` | 几乎全部功能包 |

## 推荐落地顺序

1. **I 的纯视觉小改**：缩略图与外文图标，边界较小，便于先验证拆分流程。
2. **D 新源置顶**：实现集中，两个入口容易做 A/B 回归。
3. **C 取消订阅**：先解决曾经真机崩溃的路径。
4. **B 菜单与试读失败**：共用组件风险高，必须独立审查和真机验证。
5. **G 阅读提取**：有真实样本，验证路径明确。
6. **E + F 翻译**：耦合最高，先按 hunk 分正文/标题，再一起做完整构建和样本回归。
7. **H 阅读导航与顶栏**：系统手势和动画需要真机判断。
8. **A 统一发现**：最后做外部服务在线回归，避免把服务故障误判为本地拆分回归。
9. **文档收口**：删除或明确归档过时交接，确保 `CURRENT-STATE.md` 成为新的入口。

## 进入提交前的最低门槛

- 每个功能包有独立暂存差异，`git diff --cached` 能单独讲清楚目的。
- 每个包至少通过 `git diff --check` 和对应平台构建；翻译包额外通过 JS 检查。
- B、C、H 必须有真机结果；视觉项不能只用编译结果替代。
- A 必须记录四类搜索各自的成功/失败状态，并证明一类失败不会阻断其他组。
- 不把 API Key、构建产物、DerivedData 或用户数据纳入提交。
- 未获得明确授权前，不创建提交、不推送远端。
