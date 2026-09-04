# Babel 2.0 项目记录

本目录是 Babel 2.0 的持续交接记录。它记录当前事实、决策、验证证据、经验和下一步，不替代产品合同，也不把计划写成完成。

## 建议阅读顺序

1. [README.md](README.md)：先理解本目录的职责、证据层级和命名边界。
2. [PRODUCT-CONTRACT.md](../PRODUCT-CONTRACT.md) 与 [MOTION-CONTRACT.md](../MOTION-CONTRACT.md)：amendment 已完成规范 QA、提交并非 force 推送的产品与运动合同。
3. [STATUS.md](STATUS.md)：当前分支、工作树、已完成和缺口。
4. [REQUIREMENTS.md](REQUIREMENTS.md)：用户反馈到 Slice、模块、测试和设备验收的映射。
5. [DECISIONS.md](DECISIONS.md)：带重新评估条件的 ADR 决策记录。
6. [VALIDATION.md](VALIDATION.md)：只收录带提交、时间、环境和范围的真实证据。
7. [LESSONS.md](LESSONS.md)：已经暴露的失败模式，以及下一轮必须设置的 gate。
8. [HANDOFF.md](HANDOFF.md)：接手者十分钟启动顺序和当前下一任务。
9. [UPDATE-PROTOCOL.md](UPDATE-PROTOCOL.md)：以后如何同步这些记录。

## Source of truth 层级

发生冲突时，按以下顺序处理：

1. 用户最新的明确反馈和已确认的视觉/交互决定；
2. 已批准的 Babel 2.0 产品与运动合同；若未来合同出现复审中的改动，先标记为 in-review；
3. 当前文件系统、当前 Git 提交、工作树和工程实际状态；
4. 绑定到具体提交和环境的自动化、构建、模拟器、真机和人工验收证据；
5. Figma 静态画面、图像参考和设计草稿；
6. 计划、旧报告、代理摘要和口头意图。

较高层级的规则覆盖较低层级的草稿，但“没有发现反例”不等于“已完成”。每项完成声明必须有与需求范围相同范围的证据。

合同负责规范语义，不负责动态 Git 状态；当前本地 HEAD、remote-tracking、hosted remote 和 working-tree 边界以 [STATUS.md](STATUS.md) 为准，验证命令与结果以 [VALIDATION.md](VALIDATION.md) 为准。

## 命名与历史资料

新的产品表面、代码、资源、测试、日志、路由和本文档统一使用 Babel/Babel2 命名。历史版本、存量工程路径和兼容 identity 只可在明确标记为 `audit-only historical reference` 的审计记录中出现；它们不是新代码命名模板。路线 A 的技术改名被延后到 Babel 2.0 真机稳定后分阶段执行，具体见 [DECISIONS.md](DECISIONS.md) 和合同中的命名 gate。

## 当前结论

当前未提交工作树已经把 AppDelegate、SceneDelegate 和 Babel2 scene lifecycle 收紧为单一 Babel2 root：URL、shortcut、notification、NSUserActivity、restoration 和旧启动选择不会切换到 legacy generation；旧 controller/storyboard/WebKit 实现仍在 target、bundle 或磁盘上保留，不能把 startup trace 当作 production package/resource allowlist 通过。

r8 fresh evidence（目标 iPhone 17 / iOS 27 Simulator，UDID `555E35FA-6BFE-45F0-BCFC-0819FFE48CD2`）为：Babel2UI package 30/30；全量 iOS Debug console XCTest 34/34 + Swift Testing 18，xcresult 52/52 passed、0 failed；Debug/Release build 均成功。Release-r10 app 可执行文件 SHA 为 `aff2619cde1051078bbe58a6727b17138b2f114f18945cd5ea141ee113cda1c2`；fresh uninstall/install 后 no-args 与 cold `-GenesisV2` 各自以 exact metadata/command 启动并通过独立 structured validation（8 events seq0–7、单 session、严格 order/uptime、真实 lookup/observed/delegate/surface、legacy=0、final valid/complete）。test-host 的 26/26 gate tests 是结构化约束证据，不替代 production standalone authenticity；warm Genesis 复用 scene session 的 7-event failure 仍保留为中间失败证据。

Phase 1A 仍为 **修复中 / 证据待补**：A0/A6 部分 startup trace 可供 root 复审，但 A10 scene reconnect/disconnect、A12 0.5/1/2 秒截图、A13 blank.html/WebKit runtime、完整 A2–A5 参数/恢复矩阵、目标 iPhone、真实性能/视觉和最终 Gate A target-membership/resource allowlist 尚未关闭。r10 bundle inventory 仍含 `Main.storyboardc`、`blank.html`、themes、HTML templates 和 3 个 `.appex`，target 仍编译旧 `PreloadedWebView`/`WebViewProvider`/`RootSplit`/`SceneCoordinator`/`BabelShell`；本轮不做 Feeds/UI、真机或 allowlist 清理。M1 仍只在本地提交，远端推送等待用户对具体 commit 授权；页面 consumer、120Hz 真机手感、运行时图标接入、完整屏幕和真实数据路径仍需按 Slice 推进。

## Phase 3 当前结论（2026-09-01，Asia/Tokyo）

Phase 3 账户限定 Feed→Article 垂直切片已在未提交工作树完成实现与自动化验证，主控复审结论限定为“实现代码 P0/P1=0”；持久 evidence gate 已关闭，入口为 [evidence/phase3/manifest.json](evidence/phase3/manifest.json)。这不是完整 Babel 2.0、Phase 1A 或真机验收结论。实现涉及 Babel2Core contracts/snapshots、Babel2 live/data adapters、Root/Library controllers、SceneComposition、package tests、独立 `Babel2FeedReaderTests`，以及仅将该测试加入既有 group/Sources 的 `NetNewsWire.xcodeproj/project.pbxproj` membership；具体精确文件清单与不变更 Account/Articles/ArticlesDatabase/SmartFeeds 的边界见 [STATUS.md](STATUS.md) 和 [HANDOFF.md](HANDOFF.md)。

关键语义是显式 account/feed/article value identity；无 canonical URL 但有缓存正文的文章仍进入 Feed/reader，Open Original 隐藏；root 只读元数据，不加载全库文章、不做 SmartFeeds union、不用账户聚合 count 冒充 per-feed count；Feed 查询按 account+feed 定位真实缓存，已加载 snapshot 直接传 reader，异步 stale/cancel 回写受 guard 约束。Package 31/31、targeted 4/4、full Debug 56/56、Debug/Release build 均有可复核证据，但没有扩展后续筛选、Folder、WebKit、同步或缓存架构。

Release r1 app 在目标 iPhone 17 / iOS 27 Simulator 无参 cold launch 后真实显示 Feeds root；现有数据只读检查到 active `OnMyMac`、10 个 FeedSettings、424 个 cached article/status/search rows。持久 runtime 证据为 [evidence/phase3/runtime-summary.json](evidence/phase3/runtime-summary.json)、[evidence/phase3/runtime-probe.json](evidence/phase3/runtime-probe.json)、[evidence/phase3/live-trace-summary.json](evidence/phase3/live-trace-summary.json) 和 [evidence/phase3/cold-launch-final.png](evidence/phase3/cold-launch-final.png)。由于当前环境没有可用 tap/accessibility 驱动，单源文章、正文和 Open Original 的真实交互为 `INTERACTION BLOCKED`，没有伪造数据或 deep-link。启动 live trace 仍有既有 `sceneConfigurationSelectionMissing` / `isValid=false`，不能当作 Phase 1A 完整 runtime 通过；完整成功/失败索引见 [evidence/phase3/validation-iterations.json](evidence/phase3/validation-iterations.json) 和 [VALIDATION.md](VALIDATION.md)。

当前仍 OPEN：cache first-hit/validation 与无界、同名 tie-break、旧 storyboard/nib/3 appex allowlist、物理 iPhone、视觉/性能/手势/scene 恢复，以及后续产品功能。最终 SecretKey 与 `.gyb` hash、六个 secret 环境变量状态见 [evidence/phase3/secret-status.json](evidence/phase3/secret-status.json)；恢复后未再 build/test。无 commit、无 push。

## Phase 3B：真实 Simulator UI driver（2026-09-01，Asia/Tokyo）

Phase 3B 在当前账户限定 Feed→Article 实现上增加最小 XCUITest driver，使用目标 iPhone 17 / iOS 27 Simulator 的现有真实数据完成无参数启动、Feeds 根页、当前 UI 顺序的单一 source、缓存文章正文、Open Original 系统 handoff 和返回根页。持久化入口为 [evidence/phase3b-ui/manifest.json](evidence/phase3b-ui/manifest.json)；构建/test 摘要、脱敏 runtime probe 和截图清单分别见 [build-summary.json](evidence/phase3b-ui/build-summary.json)、[runtime-probe.json](evidence/phase3b-ui/runtime-probe.json)、[screenshot-inventory.json](evidence/phase3b-ui/screenshot-inventory.json)。本轮截图与 bundle digest 的 P1 correction 已通过独立只读复核，manifest 状态为 `phase3b_evidence_gate_closed_after_independent_recheck`；该 gate 仅覆盖 Phase3B implementation + automation + persistent evidence，未暗示 Phase1A 或全产品完成，且复核没有重跑 build/test/install/launch。

本切片精确文件为：`Tests/NetNewsWire-iOSTests/Babel2FeedReaderUITests.swift`、`NetNewsWire.xcodeproj/project.pbxproj`、`NetNewsWire.xcodeproj/xcshareddata/xcschemes/NetNewsWire-iOS UI Driver.xcscheme`、`xcconfig/NetNewsWire_iOSUITests_target.xcconfig`、`iOS/Babel2/Babel2LibraryViewControllers.swift`，以及 Phase 3 manifest tree hash wording、本证据目录和五份项目文档。新 target 只承担独立 UI test，scheme 没有 updateSecrets preaction；产品改动仅为稳定 feed/article/body accessibility identifiers。

静态 target/scheme 检查成功，Release build-for-testing r1/r2 成功。UI r1 是实际 1-test 的 `UI_SELECTOR_TIMEOUT` 失败轮次；修复稳定 identifier 后 r2、r3 均为实际 1/1 passed。通过项包括 10 个 root feed rows、单 source 的 article table/cached row、正文非空且非 loading/纯标签、SafariViewService foreground handoff 及 article/feed 返回恢复。root/back PNG 保持完整状态；feed.png 已从 r2 原始附件按 `[0,0,1206,390]` 确定性裁为仅含顶部 status/header/feed name/count 的 crop，不含文章标题、日期、正文或 URL；reader/after-browser 原始附件不进入仓库，避免正文/标题/URL 泄露。

数据边界必须保留：安装/测试序列中的 `articles/statuses/search` 观察值为 `424→425→426`，并伴随 data-container UUID rotation；同一 r2 artifact 的 r3 前后为 426，FeedSettings=10、integrity=`ok`。状态是 `UNEXPECTED_DATA_MUTATION`，原因未证实，不能声称 read-only，不能无证据归因后台同步。bundle digest 已按 bundle-root-relative 独立算法重算，BFT r2 与 installed r3 均 245 文件且 tree SHA 为 `64ef2ec5…`；旧绝对路径 digest 仅为 historical/path-bound。Phase 3B 的 “P0/P1=0” 仅限实现代码复审，独立复核已关闭本切片 evidence gate；Phase 1A、物理 iPhone、旧 storyboard/nib/3 appex allowlist、完整 scene/视觉/性能验收、cache 两个 P2、同名 tie-break、Open Original 无 URL 语义缺口和数据变化原因仍 OPEN。enabled URL → SafariViewService 的真实通过仍保留。无 commit、无 push。
