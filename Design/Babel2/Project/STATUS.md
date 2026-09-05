# Babel 2.0 当前状态

更新时间：2026-09-01（Asia/Tokyo）

## Git 快照

- 分支：`codex/reeder-classic-rebuild`
- 当前本地 `HEAD`：`5db240499806bc4cae9be0b82194c838a32229de`（`Babel 2.0 M1: add interruptible motion foundation`）
- 2026-09-05：用户明确授权推送 M1 commit `5db240499806bc4cae9be0b82194c838a32229de`；实际执行 `git push origin codex/reeder-classic-rebuild` 推送的是当时本地 HEAD `c4335576d55b46431cd58e5b26f84ca10407fd9f`（线性历史，`5db240499` 是其祖先，中间还含 `3e4f5e7f8`、`3dfd71882` 两个已测试提交），推送后立即 `git fetch origin codex/reeder-classic-rebuild` 核实，`origin/codex/reeder-classic-rebuild` 与本地 HEAD 一致，均为 `c4335576d55b46431cd58e5b26f84ca10407fd9f`。这是本次 live verify 的结果，不代表之后不需要再核实。
- 当前 `origin/codex/reeder-classic-rebuild` remote-tracking ref：`c4335576d55b46431cd58e5b26f84ca10407fd9f`（2026-09-05 fetch 核实）。历史记录：此前 remote-tracking 长期停在 `1269bb9087d896a7a9e29f174461d60b47134575`，M1 commit 当时尚未推送；这一条只作历史参照，不代表当前远端状态。
- 版本谱系：v0.5 与 v1.0 是历史稳定基线，v1.1 是 Babel 2.0 前 UIKit 基线；Babel 2.0 尚未发布，因此不创建 v2.0 标签。
- 当前工作树不是干净树。以下记录以当前文件系统为准，不把 `HEAD` 误称为工作树完整状态。

## 结论先行

Babel 2.0 的 Phase 2A 单轨启动接线已落在当前未提交工作树：AppDelegate、SceneDelegate 和 Babel2 scene lifecycle 只建立 Babel2 root，外部动作保持 Babel2 并安全 no-op，旧 storyboard/controller/WebKit 路径不再由生产 lifecycle 实例化。r8 fresh matrix 的 Babel2UI package tests 为 30/30；全量 iOS Debug tests 为 XCTest console 34/34 加 Swift Testing 18 项（共 52），xcresult summary 为 52/52 passed、0 failed；Debug 与 Release build 也通过。Release-r10 在目标 iPhone 17 / iOS 27 Simulator 的 no-args 和卸载重装后的 cold `-GenesisV2` 均产生同一结构化 8-event trace，final `isComplete=true`、`isValid=true`。完整 Phase 1A A0–A15 矩阵、0.5/1/2 秒截图、目标 iPhone、性能和视觉验收仍未完成。

## Phase 1A 当前状态

Phase 1A 的 generation gate、启动顺序、Babel2 root composition、外部动作 no-op 和当前 restoration/teardown 接线已完成本批实现与自动化回归；Gate A 仅完成当前 source/runtime trace 子项，production target/resource allowlist 未通过。状态仍为：**修复中 / 证据待补**，因为 A0–A15 仍要求逐项 runtime/截图/真机证据和 root 复审，不能只凭 52 项 iOS 结果、模拟器 startup trace 或 build 关闭 Phase 1A。当前 production lifecycle 没有可运行的 legacy fallback；旧实现仍留在 target/bundle/磁盘供审计，不能把 simulator startup trace 当成 production package/最终 allowlist 通过。矩阵和证据见 [PHASE1A-ACCEPTANCE.md](PHASE1A-ACCEPTANCE.md)。

2026-09-05 补充：在当前已推送 commit `7b8ff453e` 重新编译 Debug/Release 后，A1（gate 与旧 bootstrap 隔离）、A2（Debug/Release 10 组启动参数矩阵）、A3（Release 忽略参数）、A7（未识别 URL no-op，含真实 route/anchor 状态下的前后截图 SHA-256 比对）四行已产出证据并标记"通过（需 root 复审）"，详见 [PHASE1A-ACCEPTANCE.md](PHASE1A-ACCEPTANCE.md) 对应新增小节与 [VALIDATION.md](VALIDATION.md)。这四行仍待 root 复审终审，且不代表 A4–A6 剩余子项、A8–A15 或目标物理 iPhone 的任何一项关闭。

2026-09-05 同日第二批（commit `fb0a43f14`，已推送）：A13（启动路径无 blank.html/WebKit）产出证据并标记"通过（需 root 复审）"。A8（识别外部动作）与 A10（restoration/teardown）各自的部分子场景也已验证——A8 的 4 种已注册 URL（showunread/showtoday/showstarred/addFeed）子集、A10 的真实后台↔前台切换子场景——但 shortcut item/notification response（A8）和真正的 scene disconnect/真机 30-cycle（A10）用 `xcrun simctl` 脚本化不出来，这两行整体状态仍是"实现进行中/证据待补"。详见 [PHASE1A-ACCEPTANCE.md](PHASE1A-ACCEPTANCE.md) 对应新增小节。

2026-09-05 同日第三批（已提交 `733275b72`，未推送）：A4（persisted generation 边界）、A5（stale/corrupt fail-closed）、A9（restoration 校验矩阵）——在 `Babel2FeatureGateTests.swift` 新增两个测试方法，补齐了 A5/A9 点名但原来没测过的输入（真正损坏的字节、空 routes、首 route 非 home、未知 route 值），全量 Debug iOS test suite 重新跑过一遍全绿。这三行的诚实缺口是同一个：全部证据都停在"直接调用生产的校验/root 组装函数"，还没有一条经过真实 `UISceneSession.stateRestorationActivity` 触发的 `SceneDelegate.scene(_:willConnectTo:options:)`——`UISceneSession` 没有公开初始化方法测试代码构造不出来，`simctl` 也没有命令能复现"系统真的回收 scene 又冷启动恢复"这个场景，需要真机或者一次代码改动（加测试 seam），本轮没有做后者。三行均标记"实现进行中/证据待补"。详见 [PHASE1A-ACCEPTANCE.md](PHASE1A-ACCEPTANCE.md) 对应新增小节。

2026-09-05 同日第四批（尚未提交）：A11（30-cycle re-entry）产出证据并标记"通过（需 root 复审）"——除了已有的进程内 30 次单元测试，新增一个含真实视图加载与路由校验的进程内 30 次测试，另外做了本轮 Phase 1A 里唯一一次"30 次真实冷启动"（30 个不同 PID/session，全部 valid+complete+零 legacy）。A15（single owner + Gate A 白名单）在做交叉引用时，独立复核了现有 `Babel2BoundaryTests` 的扫描范围，**发现并修复了一个真实缺口**：扫描目录漏了 `iOS/Babel2Integration/` 和 `iOS/Babel2ExternalActionParser.swift`，补扫后发现的一处 `AccountManager.shared` 使用是合理的（唯一集中的真实数据桥接层）但此前无自动化盯防，已加精确白名单纳入监控。A15 的 persisted identity 边界（`LegacyIdentityCompatibility` 仍零实现，如实记录现状）和完整 target/resource allowlist 仍是 open，整行标记"实现进行中/证据待补"。详见 [PHASE1A-ACCEPTANCE.md](PHASE1A-ACCEPTANCE.md) 对应新增小节。

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

- M1：contract layer 已完成，本地 commit 已通过第 5 轮独立 QA；2026-09-05 已获授权推送并经 `git fetch` 核实远端已含此 commit；页面 consumer 接入、真机 120Hz 手感和 OSLogStore consumer integration 仍 pending。
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
4. 由统一导航壳消费 M1，补做真机 120Hz 手感与 OSLogStore consumer integration，再按 REQUIREMENTS.md 的 Slice 顺序推进页面；最后才做真机稳定后的分阶段技术改名和旧代码删除。

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
