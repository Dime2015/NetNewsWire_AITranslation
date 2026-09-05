# Babel 2.0 接手说明

这不是完成声明。当前未提交工作树已经可以在目标 iPhone 17 / iOS 27 Simulator 启动 Babel2 root，并通过 r8 fresh matrix：Babel2UI package 30/30、全量 iOS Debug console XCTest 34/34 + Swift Testing 18（xcresult 52/52）、Debug/Release build；Release-r10 的 no-args 与卸载重装后的 cold `-GenesisV2` 均通过真实结构化 8-event startup trace。仍没有可真机验收的完整 Babel 2.0 App。

## 接手者十分钟启动顺序

1. 执行只读 Git 检查：确认分支、`HEAD`、remote-tracking ref、tag 和完整 dirty worktree；不要先清理或 reset。
2. 按固定顺序阅读 [README.md](README.md) → [PRODUCT-CONTRACT.md](../PRODUCT-CONTRACT.md) 与 [MOTION-CONTRACT.md](../MOTION-CONTRACT.md) → [STATUS.md](STATUS.md) → [REQUIREMENTS.md](REQUIREMENTS.md) → [PHASE1A-ACCEPTANCE.md](PHASE1A-ACCEPTANCE.md) → [DECISIONS.md](DECISIONS.md) → [VALIDATION.md](VALIDATION.md) → [LESSONS.md](LESSONS.md) → [HANDOFF.md](HANDOFF.md) → [UPDATE-PROTOCOL.md](UPDATE-PROTOCOL.md)。
3. 读完上述顺序后，重点核对 feature gate、命名路线、运动 ownership、颜色、loading、媒体和图标决策；不得用摘要跳过合同或验证边界。
4. 阅读 [VALIDATION.md](VALIDATION.md)；把“前序代理报告”与当前可复跑证据分开，未绑定当前提交的结果不能当绿灯。
5. 检查当前 M1 文件、Babel2 Core/UI package、`iOS/Babel2` 资产和现有测试；确认实现代理没有越过授权路径，并在当前 working tree 重新核对，不依赖永久 agent handle。
6. 确认合同 amendment 为 `1269bb9087d896a7a9e29f174461d60b47134575`，已完成规范版本 QA、提交并非 force 推送；后续实现直接以该版本为准，同时以 STATUS 的动态 SHA 为当前工作树事实。

## 当前安全边界

- Phase 1A A0–A15 当前仍为 **修复中 / 证据待补**；r8 已通过 package 30/30、全量 iOS 52/52、Debug/Release build，以及 Release-r10 no-args/cold Genesis production startup trace。前序独立 QA 的源码编译错误、root 约束异常、test-host scene name 断言、r5 WebView 注入顺序、trace-only token 误报和 warm Genesis 复用 session 均标为历史/中间尝试；不得把局部自动化/build、模拟器 startup trace、旧安装包或旧截图写成 Phase 1A 总体/production package 通过。独立审查的 P0 根因是 generation gate 晚于 `AppDelegate` 的 legacy bootstrap；当前以 AppDelegate 初始化边界和 Babel2-only SceneDelegate 修复，仍需 root 复审。

- 当前 r8 fresh 证据：iPhone 17 / iOS 27 Simulator，UUID `555E35FA-6BFE-45F0-BCFC-0819FFE48CD2`；package `/private/tmp/babel2-phase2a-r8-package-tests-final.log`；全量 Debug tests `/private/tmp/babel2-phase2a-r8-ios-debug-tests-final.log`、`/private/tmp/babel2-phase2a-r8-ios-debug-tests-final.xcresult`；Debug build `/private/tmp/babel2-phase2a-r8-debug-build-final.log`、`/private/tmp/babel2-phase2a-r8-debug-build-final.xcresult`；Release-r10 `/private/tmp/babel2-phase2a-r8-release-r10.log`、`/private/tmp/babel2-phase2a-r8-release-r10.xcresult`。production startup trace 与失败尝试的完整索引见 [VALIDATION.md](VALIDATION.md)。旧安装包/截图不能替代当前真机、视觉、性能和资源 allowlist 证据。

- 当前剩余证据：A0/A1/A6/A8/A12/A13 的逐项归档、A10 scene reconnect/disconnect teardown、完整 launch-argument/scene 恢复矩阵、0.5/1/2 秒截图、目标 iPhone/性能/视觉验收和最终 bundle allowlist。r10 startup trace 已证明本次两个参数状态的真实 scene/config/root 观测，但不证明 production package 无旧资源：target 仍编译旧 `PreloadedWebView`/`WebViewProvider`/`RootSplit`/`SceneCoordinator`/`BabelShell`，bundle 仍含 `Main.storyboardc`、`blank.html`、themes 和 3 个 extensions；BoundaryTests 尚无 target-membership/resource allowlist gate。canonical parser、Babel2 trace order、restoration validation、root teardown、weak/token callback safety 与 production boundary 已有当前自动化/static boundary，待 root 复审。详见 [PHASE1A-ACCEPTANCE.md](PHASE1A-ACCEPTANCE.md)。

- 新代码、资源、测试、路由、日志和用户可见表面使用 Babel/Babel2 命名。
- 可复用的是数据、同步、账户、文章和图片服务能力；不能隐式复用历史视觉、toolbar、navigation、WebView 状态或旧 motion owner。
- Core 不得依赖 UIKit/WebKit；Reader/Browser 的 WebKit 只允许进入合同规定的专用路径，并且每个 route 要有独立状态 token。
- 只有一个 Babel2 navigation/root composition owner；只有一个 motion owner 写每个动画 surface；只有一个 loading owner 显示每个 surface 的等待状态。
- 当前 `iOS/Babel2` 已由 AppDelegate/SceneDelegate 接为 production Babel2 root；trace counters 从真实事件流派生，legacy event、错序、session/uptime/sequence、缺 observed configuration 或 storyboard evidence、错误 delegate metatype、无效 surface geometry 均 fail-closed；OSLog 用逐 event 短 JSON + 独立 result，避免长 trace 截断。仍只覆盖基础 Feeds/placeholder surface，不代表完整页面、production package allowlist 和真机验收完成。`LegacyIdentityCompatibility` 仍是 PRODUCT-CONTRACT/A15/Phase6 requirement，当前没有空 facade 或实现。
- 图标设计/静态资产已完成并提交（包括 Light/Dark/Mono、逐图检查、独立 QA 和 actool）；用户先选定 Dark 并授权生成后直接作为 Babel 2.0 图标，早期烧焦/全局蒙版 Light 已否决，当前 Final 按亮木桌、独立暗色封面和干净页边重生成，Round 4 草稿不构成回退。Dark master 是 `Design/Babel2/Icon Concepts/Final/Babel2AppIcon-Dark.png`；三态 runtime appearance、模拟器解析和 Home Screen 仍需验证，临时用户附件仅作 provenance，不声称用户已逐像素口头确认最终 Light。
- M1 已在本地 commit `5db240499806bc4cae9be0b82194c838a32229de`（`Babel 2.0 M1: add interruptible motion foundation`）提交，14 files / 2618 insertions；此前绑定 M1 commit 的第 5 轮独立 QA PASS（30 package、8 真实 iOS UIKit runtime、8 Boundary/Shell、Debug build，iPhone 17 / iOS 27 Simulator）不等于本次 Phase 1A final QA 通过，后者仍因缺少 A0–A15 runtime/真机/视觉证据而 open。远端推送等待用户对具体 commit 授权；页面 consumer、真机 120Hz 手感和 OSLogStore consumer integration 仍 pending。
- 技术命名、系统 identity 和历史代码清理遵循路线 A：稳定且真机验收后分批做，外部 identity 变更另需授权。

## 禁止动作

- 不要把 Babel2 assembly 或静态 asset catalog 直接宣传为可运行 App。
- 不要在 feature gate/root 完成前批量删除历史代码或重命名持久化 identity。
- 不要修改、回滚或删除共享工作树里未授权的合同、图标、比较图、Figma 产物、工程配置或别的代理改动。
- 不要创建第二套导航、手势 driver、Reader WebView pool 或 spinner 来绕过现有合同。
- 不要用模拟器截图、Figma 预览、单元测试或代理口头报告替代真机和用户视觉验收。
- 不要把旧名称塞进新的叶子文件名、类型、accessibility ID、日志、route 或用户文案；审计引用必须标记 `audit-only historical reference`。

## 当前未提交范围

本次接手时至少要重新检查：合同工作树修改、M1 motion 源码和测试、图标概念与三态静态资产、工程配置、比较图与本目录文档。不要凭本文件的摘要假定范围没有变化；以任务开始时的 `git status` 为准。

## 验证顺序

1. 已提交合同版本核对和文档一致性检查。
2. Babel2 package 测试、边界/命名 gate、iOS Debug simulator build。
3. feature gate/root/re-entry 和 route generation 测试。
4. M1 motion driver、导航边缘返回、Reader→Browser 边缘手势的自动化与 runtime 检查。
5. Feeds、Feed hero、Reader、媒体、翻译、Settings、订阅管理、i18n 和 loading/error 状态的 Slice 验证。
6. 模拟器深浅色/中英文/错误/恢复回归。
7. 目标 iPhone 冷热启动、真实文章和图片、性能、滚动、翻译、状态栏、手势、图标和状态恢复。
8. 真机稳定后，才启动分批技术改名和历史代码清理；每批都要有迁移/回滚证据。

## 当前下一任务

由 root 复审当前单轨 diff 和 r8 fresh evidence，按 [PHASE1A-ACCEPTANCE.md](PHASE1A-ACCEPTANCE.md) 回填 A0–A15 的逐项 trace/manifest；A6/A14 的 no-args 与 cold `-GenesisV2` startup trace 已有真实 8-event 证据，但 A10 scene 重连/后台恢复/teardown、A12 0.5/1/2 秒截图、A13 no blank.html/WebKit runtime、Gate A exact resource/target allowlist 和目标 iPhone 冷热启动/性能/视觉验收仍 open。全部当前 runtime/结构证据完成前保持“修复中/证据待补”；r5 失败、warm Genesis 7-event 失败、旧安装包和旧截图不能替代当前构建或 cold runtime evidence。`5db240499806bc4cae9be0b82194c838a32229de` 已于 2026-09-05 获用户明确授权并推送（实际推送的本地 HEAD 是其之上的 `c4335576d`，`git fetch` 核实 hosted remote 一致，见 STATUS.md）；下一步是让统一导航壳消费 M1，补做真机 120Hz 手感与 OSLogStore consumer integration，之后按 REQUIREMENTS 实现 Feed/Timeline 的无透明空带 header 几何及 pFilter（Starred/Unread/All）的 selection pill、列表、计数同 progress 的可中断反向动画。合同 amendment `1269bb9087d896a7a9e29f174461d60b47134575` 已 completed/committed；完成前不要开始全量旧名删除。图标设计/静态资产已经是提交状态，但不要在 runtime appearance 未验收前宣称最终品牌接入完成。

## Phase 3 接手记录（2026-09-01，Asia/Tokyo）

以下记录覆盖本次账户限定 Feed→Article 垂直切片，保留上方 Phase 2A handoff。当前工作树未提交、无 commit/no push；当前没有活跃命令或测试会话。主控复审结论限定为“实现代码 P0/P1=0”；持久 evidence gate 已关闭，入口为 [evidence/phase3/manifest.json](evidence/phase3/manifest.json)。

实现与工程 membership 的精确文件范围为：`Modules/Babel2UI/Sources/Babel2Core/Contracts.swift`、`Modules/Babel2UI/Sources/Babel2Core/Snapshots.swift`、`Modules/Babel2UI/Tests/Babel2UITests/Babel2UITests.swift`、`iOS/Babel2Integration/Babel2LiveDataAdapters.swift`、`iOS/Babel2/Babel2DataAdapters.swift`、`iOS/Babel2/Babel2RootViewController.swift`、`iOS/Babel2/Babel2LibraryViewControllers.swift`、`iOS/Babel2/Babel2SceneComposition.swift`、`Tests/NetNewsWire-iOSTests/Babel2FeedReaderTests.swift`，以及 `NetNewsWire.xcodeproj/project.pbxproj` 中将该独立测试加入既有 group/Sources 的最小 membership。本轮同步文件为 `STATUS.md`、`HANDOFF.md`、`PHASE1A-ACCEPTANCE.md`、`VALIDATION.md`、`README.md`；未授权文件没有纳入实现清单。

交接时必须保留的行为边界：identity 是显式 account/feed/article value，不是未转义冒号字符串；没有 canonical URL 的缓存正文仍进入 Feed/reader，Open Original 隐藏；root 不遍历全库文章、不做 SmartFeeds union、不用 aggregate account count 冒充 per-feed count；不可用 root count 隐藏，Feed header 使用已加载列表实际数量；Feed 已加载 snapshot 直接传入 reader；所有 lookup/action/cache 复核 account/feed/article 三元组；异步回写需通过 cancellation、generation 和 identity guard。没有改 Account/Articles/ArticlesDatabase/SmartFeeds，没有新增 repository、cache engine、sync engine、WebKit 或后续筛选/Folder 功能。

验证接手点：Package 31/31、targeted `Babel2FeedReaderTests` 4/4、full Debug iOS 56/56、Debug build r3、Release build r1 均为有效成功；持久化入口为 [evidence/phase3/manifest.json](evidence/phase3/manifest.json)、[evidence/phase3/test-results-targeted-summary.json](evidence/phase3/test-results-targeted-summary.json)、[evidence/phase3/test-results-full-summary.json](evidence/phase3/test-results-full-summary.json)、[evidence/phase3/build-results.json](evidence/phase3/build-results.json) 和 [evidence/phase3/validation-iterations.json](evidence/phase3/validation-iterations.json)，[VALIDATION.md](VALIDATION.md) 只作解释与原始临时来源索引。targeted r1 的 `Executed 0 tests` 是无效证据，r2 sandbox 是环境失败，r2-escalated/r3/r4 是已保留的编译失败，均不得重新标绿。Release r1 app runtime 只证明无参 cold launch 后 Feeds root 可见；目标 Simulator 有 10 个 FeedSettings 和 424 个缓存 article/status/search 行，但没有 tap/accessibility driver，故 `INTERACTION BLOCKED`，不得把单元测试替代真实 Feed→Article 交互。旧 storyboard/nib/3 appex allowlist、物理 iPhone、视觉/性能/完整 scene 恢复，以及 cache first-hit/bound 和同名 tie-break P2 仍 OPEN。

最终安全状态：最后一次 build/test 与运行时完成后，`SecretKey.swift` 已按可信快照恢复并 byte-identical；hash 与六个环境变量状态的持久入口为 [evidence/phase3/secret-status.json](evidence/phase3/secret-status.json)。恢复后不得再启动 build/test；只做 docs 与只读边界检查。

## Phase 3B 接手记录：真实 Simulator UI driver（2026-09-01，Asia/Tokyo）

Phase 3B 已完成最小 UI driver 的真实运行，并已通过独立只读 evidence recheck；manifest 当前为 `phase3b_evidence_gate_closed_after_independent_recheck`。该 gate 仅覆盖 Phase3B implementation + automation + persistent evidence，未暗示 Phase1A 或全产品完成；复核没有重跑 build/test/install/launch。后续接手先阅读 [evidence/phase3b-ui/manifest.json](evidence/phase3b-ui/manifest.json)、[build-summary.json](evidence/phase3b-ui/build-summary.json)、[runtime-probe.json](evidence/phase3b-ui/runtime-probe.json) 和 [screenshot-inventory.json](evidence/phase3b-ui/screenshot-inventory.json)。原始 log、xcresult、derived data 与 simulator probe 仍只在 `/private/tmp/babel2-phase3b-ui-*`，仓库只保存精简摘要和不含正文/URL 的 root/feed/back 截图。

精确改动范围：`Tests/NetNewsWire-iOSTests/Babel2FeedReaderUITests.swift`；`NetNewsWire.xcodeproj/project.pbxproj`（独立 UI target、app dependency/container proxy、sources/frameworks/resources phases 和最小 membership）；`NetNewsWire.xcodeproj/xcshareddata/xcschemes/NetNewsWire-iOS UI Driver.xcscheme`；`xcconfig/NetNewsWire_iOSUITests_target.xcconfig`；`iOS/Babel2/Babel2LibraryViewControllers.swift` 的三个稳定 accessibility identifiers；`Design/Babel2/Project/evidence/phase3/manifest.json` 的 tree hash wording；以及本次同步的五份文档和 `evidence/phase3b-ui/**`。没有新 service、cache/sync engine、browser route、preaction 或旧 UI 清理。

验证结果：target/scheme 在 escalated `xcodebuild -list` 中枚举成功；Release build-for-testing r1/r2 成功；UI r1 是实际 1-test 的 `UI_SELECTOR_TIMEOUT`，原因是修复前的通用 table 层级查询；UI r2、r3 均实际 1/1 passed。driver 真实看到 10 个 root feed rows，进入当前 UI 顺序中的单一 source，读取缓存正文，检查非空/非 loading/非纯标签，Open Original 的 `SafariViewService` foreground handoff，并完成 article back→feed back→root 恢复。Open Original 的通过仅表示系统 surface foreground，不表示网络页面内容验收。持久 feed.png 已从 r2 原始附件以 `[0,0,1206,390]` 确定性裁剪为 header/count crop，不含文章标题、日期、正文或 URL；BFT r2 与 installed r3 的 245 个 bundle-root-relative 文件内容一致，tree SHA 均为 `64ef2ec5…`。

必须保留的数据边界：UI 序列观察到 `articles/statuses/search` `424→425→426` 与 data-container UUID 轮换；同一 r2 artifact 的 r3 前后均为 426，FeedSettings=10，integrity=`ok`。分类为 `UNEXPECTED_DATA_MUTATION`，原因未证明，不可写成 read-only 或 background sync。旧 Phase 3 Release r1 的 `6be10d…` 只是 provenance；Phase 3B 新产物的 artifact/installed hash 以 manifest 为准。

主控复审只可把“实现代码 P0/P1=0”和 Phase3B evidence gate closed after independent recheck 用于本切片；这不改变未完成范围。Phase 1A、物理 iPhone、完整 scene reconnect/restore、视觉/性能人工验收、旧 storyboard/nib 与三个 `.appex` allowlist、cache 两个 P2、同名 tie-break P2、Open Original 无 URL 语义缺口 P2 及数据变化原因仍 OPEN；enabled URL 路径的 SafariViewService 通过仍保留。最终 SecretKey/.gyb hash 与六个 env 状态见 [evidence/phase3/secret-status.json](evidence/phase3/secret-status.json)；恢复后不要再 build/test/install/launch；无 commit、无 push。

## Feeds/Timeline 卡片打磨 checkpoint 接手记录（2026-09-05，Asia/Tokyo）

这是与上方 Phase 2A/M1「当前下一任务」并行、范围独立的一次工作树打磨收口。M1 推送授权当时待定，本节完成后（2026-09-05）已获用户授权并实际推送，见 STATUS.md「Git 快照」；本节本身不改变 Phase 1A A0–A15 证据缺口的状态。接手时已存在 7 个已跟踪文件的未提交改动（Feeds 文件夹层级、`BabelPalette` 统一配色、默认档 `.all→.unread`、筛选按钮 Figma 校准坐标、Timeline 卡片缩略图与翻译标题副标题）与 9 张 `evidence/stabilize/` 截图；本轮工作是：用全量 `xcodebuild … test`（而非只跑 package tests 或 `build`）验证这批改动，发现并修复 2 个真实回归（筛选按钮零尺寸 frame；`testStaleScopeResultCannotPublishAfterLatestIntentChanges` 因默认档变化而永久超时），随后把这批改动与本次文档同步一并提交；2026-09-05 随 M1 一起获授权推送，`git fetch` 核实远端已含此提交。完整根因、命令与前后测试数字见 [VALIDATION.md](VALIDATION.md)「Feeds/Timeline 卡片打磨 checkpoint」一节；教训见 [LESSONS.md](LESSONS.md) 第 21 条；提交 SHA 见 [STATUS.md](STATUS.md) 对应章节。

交接边界：本次修复只改了 `iOS/Babel2/Babel2RootViewController.swift` 的按钮布局保底分支与 `Tests/NetNewsWire-iOSTests/Babel2FeedReaderTests.swift` 的一个测试的竞态角色分配，没有触碰接手时已存在的其余 6 个文件的实现内容。`evidence/stabilize/` 截图未经独立复核，不能当作模拟器或真机验收证据；REQUIREMENTS 中依赖 motion/进度同步语义的两行（Feed/Timeline header 无空带、pFilter 的 pill/列表/计数同 progress）本次未触及，仍是"未开始"。

## Phase 1A：A1/A2/A3/A7 证据补齐接手记录（2026-09-05，Asia/Tokyo）

在 M1 获授权推送（commit `7b8ff453e`）之后，按用户指定顺序补齐了 Phase 1A 矩阵里能靠命令行/模拟器自证的四行：A1（gate 与旧 bootstrap 隔离，静态引用）、A2（Debug/Release 各 5 组启动参数、共 10 次真实冷启动的 OSLog trace）、A3（Release 忽略参数，A2 的子集+源码级理由）、A7（未识别 URL no-op，含 route/anchor 状态下的前后截图字节级比对）。四行均已产出 `evidence/phase1a/A{1,2,3,7}-*.json` 并标记"通过（需 root 复审）"；过程中的三个流程性坑（warm terminate 复用 scene session、全新 install 后首次冷启动更慢、`simctl openurl` 需要已注册的 URL scheme）记在 [LESSONS.md](LESSONS.md) 第 22 条。完整命令与结果表见 [VALIDATION.md](VALIDATION.md)「Phase 1A：A1/A2/A3/A7 fresh evidence」一节。

交接边界：本轮只新增证据文件（`Design/Babel2/Project/evidence/phase1a/A1-bootstrap-isolation.json`、`A2-build-channel-matrix.json`、`A3-release-ignore-args.json`、`A7-unknown-url-noop.json`、两张 A7 头部裁剪截图）和四份项目文档（本文件、STATUS.md、VALIDATION.md、LESSONS.md、PHASE1A-ACCEPTANCE.md）；没有修改任何生产代码。仍未关闭：A4/A5（persisted generation/restoration 真实 launch）、A6 的 A10 相关部分、A8/A9/A10/A11/A12/A13/A15、目标物理 iPhone 与全部视觉/性能验收。下一步按用户指示继续处理哪一部分（剩余 Phase 1A 证据、还是回到统一导航壳消费 M1）尚未确定，本记录不预设顺序。
