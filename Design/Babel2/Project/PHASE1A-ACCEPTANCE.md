# Babel 2.0 Phase 1A 验收矩阵

更新时间：2026-09-01（Asia/Tokyo）

范围：generation decision、启动顺序、Babel2 root composition、外部动作 no-op、状态恢复与命名门禁。
当前状态：**修复中 / 证据待补**。Phase 2A correction 已完成当前单轨 production lifecycle 的实现、fresh 自动化/build 验证和目标 Simulator startup trace；Gate A 仅覆盖当前 source/runtime trace 子项，production target/resource allowlist 仍未通过。A0–A15 仍需要逐项 runtime/截图/目标 iPhone 证据与 root 复审；本文件不把旧 fallback 计划或历史失败日志当作当前行为。

## 使用规则

1. 先记录只读 Git 快照：分支、`HEAD`、remote-tracking ref、`git status --short --branch`。当前基线为本地 M1 `5db240499806bc4cae9be0b82194c838a32229de`，尚未推送；remote-tracking 为 `1269bb9087d896a7a9e29f174461d60b47134575`。
2. 每行都必须填写 `owner`、`status` 和 `evidence path`。状态只能使用：`修复中/证据待补`、`实现进行中/证据待补`、`通过（需 root 复审）` 或 `失败`。只有与当前工作树、环境和实际观察匹配的自动化/运行时证据才能标为 `通过（需 root 复审）`；局部通过不得升级为 Phase 1A 总体通过。
3. 每个证据文件至少包含：`commit_or_worktree`、采集日期/时区、设备/OS/SDK、build channel、完整 launch arguments、执行命令或操作、观察结果、限制、`owner`、`status`。路径相对于仓库根目录；未生成的路径是待补字段，不是证据。
4. 新增内部命名统一使用 `Babel`/`Babel2` 与 `legacy`。`-GenesisV2`、旧 build/module 引用和旧 persisted/system identity 只能作为精确兼容边界测试或显式 allowlist 命中；相关段落标记为 `audit-only historical reference`，不得复制成新的类型、文件、route、日志或用户文案。
5. Phase 1A 通过的必要条件：A0–A15 全部有匹配范围的自动化/运行时证据，且没有 P0/P1 失败；单元测试、模拟器截图或“未发现异常”不能替代启动 trace、恢复/销毁和目标设备证据。

矩阵中出现的 `-GenesisV2` 等旧兼容字面量均属于 `audit-only historical reference`：它们只用于精确回归输入或已登记的兼容边界，不授权新增内部命名。

## A0–A15 可执行矩阵

| ID | 场景 / 输入 | 执行与通过条件 | 证据路径（待补） | owner | status |
|---|---|---|---|---|---|
| A0 | 最早 generation decision | 在进程第一次旧副作用之前，于 AppDelegate 初始化边界计算 Babel2 decision；trace 显示 `gateUptime` 早于 scene/root 事件，legacy counters 必须由真实事件流派生，任一 legacy event 使 trace invalid，不能用硬编码零证明。 | `/private/tmp/babel2-phase2a-r8-standalone-r10-noargs-final-validation.json`、`/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-validation.json` | Gate/Bootstrap owner | 通过（需 root 复审） |
| A1 | gate 与旧 bootstrap 的隔离 | 每个 build channel 的 decision 都固定为 Babel2；gate 之后只建立 Babel2 scene/root，生产路径不再有旧 lifecycle/bootstrap 选择分支。P0 根因检查覆盖 AppDelegate bootstrap 时序，而不只检查 storyboard 是否为 nil；缺失 process/decision/session/uptime/sequence 证据 fail-closed。 | `Design/Babel2/Project/evidence/phase1a/A1-bootstrap-isolation.json` | Gate/Bootstrap owner | 通过（需 root 复审）——2026-09-05，见下方新条目 |
| A2 | Debug / Test / Release 总矩阵 | 对每个 channel 验证无输入、未知输入、旧兼容字面量和 persisted generation 都不能成为 production selector；每格记录固定 generation/reason 和零旧副作用。当前自动化覆盖 decision API，真实多参数 launch 矩阵仍待补。 | `Design/Babel2/Project/evidence/phase1a/A2-build-channel-matrix.json` | Gate/Validation owner | 通过（需 root 复审）——2026-09-05，见下方新条目 |
| A3 | Release ignore args | Release 不读取 launch arguments；`-Babel2`、`-GenesisV2`、冲突和未知值不能改变 Babel2 production decision。当前 source boundary 已证明无 production argument selector，`-GenesisV2` 已有 r8 cold evidence；`-Babel2`、冲突和未知值的 Release launch 仍待补。 | `Design/Babel2/Project/evidence/phase1a/A3-release-ignore-args.json` | Gate owner | 通过（需 root 复审）——2026-09-05，见下方新条目 |
| A4 | production persisted generation 边界 | Production 不再接受 persisted generation 作为 runtime selector；唯一 restoration payload 只接受 Babel2 generation。当前代码和 restoration tests 覆盖这一边界，Release 状态恢复实测仍待补。 | `Design/Babel2/Project/evidence/phase1a/A4-release-accepted-persisted.json` | Gate/Persistence owner | 实现进行中/证据待补——2026-09-05：数据模型层（`Babel2NavigationRestoration.isValid`/`validated`）与 root 组装层（`Babel2SceneComposition.makeRoot(restoration:)`）通过（需 root 复审）；真实 `UISceneSession` 端到端仍缺，见下方新条目 |
| A5 | stale generation / corruption fail-closed | 旧 generation、未知 schema、损坏 restoration 均拒绝并采用 Babel2 安全值；不能启动半套旧或 Babel2 root。当前 restoration unit tests 覆盖 stale/corrupt 输入；Release persisted launch 实测仍待补。 | `Design/Babel2/Project/evidence/phase1a/A5-stale-generation-fail-closed.json` | Gate/Persistence owner | 实现进行中/证据待补——2026-09-05：9 种输入（4 种已有 + 5 种本轮新增的真正损坏字节）全部 fail-closed 通过（需 root 复审）；真实 UISceneSession 端到端仍缺 |
| A6 | launch trace 完整性 | trace 记录 origin/session/build、generation、decision reason、build channel、event sequence/uptime、实际 selected/observed scene configuration、root/container/content frame 和 privacy-safe source/detail；legacy lifecycle/bootstrap/storyboard/coordinator/WebKit counters 从事件派生，任一事件使 trace invalid，且不保留可调用旧事件源。 | `/private/tmp/babel2-phase2a-r8-standalone-r10-noargs-events.jsonl` + `/private/tmp/babel2-phase2a-r8-standalone-r10-noargs-results.jsonl`；cold Genesis 对照 `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-events.jsonl` + `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-results.jsonl` | Launch Trace owner | 通过（需 root 复审） |
| A7 | 未识别 URL（unknown URL no-op） | 在 Babel2 已可见且带 route/anchor 的状态下发送未识别 URL；route、root、scroll/anchor 和 generation 保持不变，不创建 legacy root，不调用 fallback，不清空 restoration。必须记录一次 no-op 结果。 | `Design/Babel2/Project/evidence/phase1a/A7-unknown-url-noop.json` | External Action owner | 通过（需 root 复审）——2026-09-05，见下方新条目 |
| A8 | 识别外部动作保持 Babel2 | 对合同登记的 URL/shortcut/notification 执行：解析为 typed action 后交给现有最小 Babel2 handler 或安全 no-op；Babel2 root、restoration 和 generation 保持不变，不关闭 root、不进入旧 handler、不创建旧副作用。未登记输入同样 no-op。 | `Design/Babel2/Project/evidence/phase1a/A8-babel2-external-action-no-legacy.json` | External Action owner | 实现进行中/证据待补——2026-09-05：4 种已注册 URL（showunread/showtoday/showstarred/addFeed）子集通过（需 root 复审）；shortcut item 与 notification response 仍缺运行时证据（`simctl` 无法脚本化触发，见下方新条目） |
| A9 | restoration generation / schema / route 校验 | 合法 Babel2 restoration（当前 schema、首 route 为 home）能恢复；错误 generation、未知 schema、空 routes、首 route 非 home、未知 route 和损坏数据均拒绝并采用安全值。恢复后只生成一套 Babel2 navigation。 | `Design/Babel2/Project/evidence/phase1a/A9-restoration-validation.json` | Restoration owner | 实现进行中/证据待补——2026-09-05：完整输入矩阵（含本轮新增的空 routes/首 route 非 home/未知 route 值）在数据模型与 root 组装层通过（需 root 复审）；真实 UISceneSession 端到端仍缺 |
| A10 | restoration 与 teardown | 冷启动、后台/前台、scene 重连和 disconnect 始终留在 Babel2；每次 teardown 都取消 Babel2 root 的 observer/task/callback，恢复后 route 符合 A9，且不会叠加第二个 window、navigation 或 lifecycle owner。 | `Design/Babel2/Project/evidence/phase1a/A10-restoration-teardown.json` | Root/Restoration owner | 实现进行中/证据待补——2026-09-05：真实后台/前台切换子场景通过（需 root 复审，同 PID、同 session、零新 root/legacy 事件、route 不变）；真正的 scene disconnect（App 切换器划掉）与真机 30-cycle 仍缺，`simctl terminate` 是硬杀进程不经过 `sceneDidDisconnect`，见下方新条目 |
| A11 | 30-cycle re-entry / leak | 在相同测试数据上完成 30 次 create → visible → teardown → re-entry；每轮 route 正确、gesture/observer 不重复、controller 能释放，weak reference 和内存/日志无累计异常。当前 iOS test 已执行 30 次 root/navigation deinit 断言。 | `Design/Babel2/Project/evidence/phase1a/A11-30-cycle-stress.json` | Root/Validation owner | 通过（需 root 复审）——2026-09-05：进程内 30 次（含加载视图+路由校验的新测试）与**30 次真实冷启动**（30 个不同 PID/session，全部 valid+complete+零 legacy）均通过，见下方新条目 |
| A12 | 0.5 / 1 / 2 秒启动截图 | 对 Babel2 cold launch 固定设备、scheme、数据和参数，在进程启动后 0.5s、1.0s、2.0s 各捕获一张并记录时间戳。0.5s 至少只能出现 Babel2 root 或有 trace 支持的 Babel2 准备状态；1.0s 与 2.0s 必须显示同一 Babel2 root。任何时点不得出现 legacy landing page、空白跳变、重复壳；截图只能辅助，必须与 A6 trace 配对。 | `Design/Babel2/Project/evidence/phase1a/A12-0.5-1.0-2.0s-screenshots.json`（含 `A12-t+0.3s.png`/`A12-t+1.1s.png`/`A12-t+2.3s.png`/`A12-launchscreen-before-process-entry.png`） | Visual/Launch owner | 结构性证据通过（需 root 复审）——2026-09-05，见下方新条目；最终视觉验收待用户确认 |
| A13 | Phase 1A 启动路径无 blank.html / WebKit | 对 Babel2 启动路径做变更集静态扫描和 runtime trace：不得加载或生成 `blank.html`，不得初始化 WebKit/WKWebView 作为 root 预热、占位或隐藏 bootstrap；Reader/Browser 的后续专用 WebKit 路径不在本行放宽该启动约束。当前静态 boundary 通过，runtime trace 仍待补。 | `Design/Babel2/Project/evidence/phase1a/A13-no-blank-html-webkit.json` | Root/Web Content boundary owner | 通过（需 root 复审）——2026-09-05，见下方新条目 |
| A14 | no-flag / `-GenesisV2` 单轨回归 | 无参数和 `-GenesisV2` 都不能选择 legacy；production gate 固定 Babel2，AppDelegate/SceneDelegate 不读取 launch arguments，旧兼容字面量只可留在 audit-only 测试边界。r8 已对同一 Release-r10 source/binary 完成两次 cold standalone trace；完整 A2–A5 参数/恢复矩阵仍待补。 | `/private/tmp/babel2-phase2a-r8-standalone-r10-noargs-final-validation.json`、`/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-validation.json` | Gate/External Action owner | 通过（需 root 复审） |
| A15 | single owner + Gate A exact allowlist | **Owner**：generation 只由 gate 决策 owner 写入；Babel2 root/navigation、restoration/teardown、external fallback 各只有一个 owner；AppDelegate/SceneDelegate 不得各自再做一套决策或导航。**Gate A**：只扫描相对基线的变更集新增/修改内容、叶子文件名、类型/方法、resource/test、用户文案、accessibility ID、log category、route；父目录/继承 target 命中不算失败。旧 token 命中必须逐项列出文件、行、精确字面量、理由和 owner；仅允许 build/test harness 的精确 allowlist，persisted/system identity 仅允许唯一 `LegacyIdentityCompatibility` 边界；未登记命中失败，allowlist 不得成为第二 identity 出口。 | `Design/Babel2/Project/evidence/phase1a/A15-owner-and-gate-audit.json` | Phase1A owner / Naming owner | 实现进行中/证据待补——2026-09-05：single-owner 交叉引用与 Gate A 自动化扫描通过（需 root 复审，含本轮发现并修复的扫描范围缺口，见下方新条目）；persisted identity 边界（`LegacyIdentityCompatibility` 仍零实现）与完整 target/resource allowlist 仍缺 |

## 2026-09-01 Phase 2A r8 fresh evidence

结果：**Phase 2A r8 当前实现、自动化/build 和目标 Simulator startup trace 通过对应范围；Phase 1A 总体仍为修复中 / 证据待补。production target/resource allowlist、A10/A12/A13、目标 iPhone 和视觉/性能证据未关闭。**

- 环境：Xcode 27.0 / iOS 27.0 SDK；目标为 iPhone 17 / iOS 27 Simulator，UUID `555E35FA-6BFE-45F0-BCFC-0819FFE48CD2`；当前 branch/HEAD 为未提交工作树 `codex/reeder-classic-rebuild` / `5db240499806bc4cae9be0b82194c838a32229de`。
- Package 层：显式 unset 六个 secret env 后 `swift test --package-path Modules/Babel2UI` exit 0，Swift Testing 30/30；日志 `/private/tmp/babel2-phase2a-r8-package-tests-final.log`，exit `/private/tmp/babel2-phase2a-r8-package-tests-final-exit.txt`。
- 全量 Debug iOS tests：显式 unset 六个 secret env 后 exit 0；console XCTest 34/34（Babel2FeatureGate 26、Babel2MotionDriverRuntime 8）+ Swift Testing 18 = 52；xcresult summary `totalTestCount=52`、`passedTests=52`、`failedTests=0`。日志 `/private/tmp/babel2-phase2a-r8-ios-debug-tests-final.log`，result `/private/tmp/babel2-phase2a-r8-ios-debug-tests-final.xcresult`，summary `/private/tmp/babel2-phase2a-r8-ios-debug-tests-final-xcresult-summary-escalated.json`；sandbox summary 权限失败保留于 `/private/tmp/babel2-phase2a-r8-ios-debug-tests-final-xcresult-summary.json`。
- Debug build：显式 unset 六个 secret env 后 exit 0，`** BUILD SUCCEEDED **`；日志 `/private/tmp/babel2-phase2a-r8-debug-build-final.log`，result `/private/tmp/babel2-phase2a-r8-debug-build-final.xcresult`，DerivedData `/private/tmp/babel2-phase2a-r8-debug-build-final-dd`。
- Release-r10 build：显式 unset 六个 secret env 后 exit 0，`** BUILD SUCCEEDED **`；日志 `/private/tmp/babel2-phase2a-r8-release-r10.log`，result `/private/tmp/babel2-phase2a-r8-release-r10.xcresult`，DerivedData `/private/tmp/babel2-phase2a-r8-release-r10-dd`；app 可执行文件 SHA `aff2619cde1051078bbe58a6727b17138b2f114f18945cd5ea141ee113cda1c2`。
- No-args production startup：r10 fresh uninstall/install 后，metadata/command `/private/tmp/babel2-phase2a-r8-standalone-r10-noargs-metadata.json`、`...noargs-command.txt`；launch exit 0，PID 66644；raw OSLog `/private/tmp/babel2-phase2a-r8-standalone-r10-noargs-final-oslog.ndjson`；events/results `/private/tmp/babel2-phase2a-r8-standalone-r10-noargs-events.jsonl`、`...noargs-results.jsonl`；验证 `/private/tmp/babel2-phase2a-r8-standalone-r10-noargs-final-validation.json`。独立验证通过 8 events seq0–7、单 session、严格 milestone order、uptime 单调、process/decision/result 绑定、selected lookup exact、observed 实际 exact、delegateClassName=SceneDelegate 且 `delegateMatchesExpected=true`、storyboard=false、4 surfaces identity/geometry/visible-key、legacy kinds/counters=0、final valid/complete。
- Warm Genesis 失败尝试：同一安装上 terminate 后直接 `-GenesisV2`，PID 67180；系统复用既有 scene session，只有 7 events，缺 `sceneConfigurationSelected`，final invalid reason 为 `sceneConfigurationSelectionMissing`。原始 raw/events/results 保留于 `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-final-oslog.ndjson`、`...genesis-events.jsonl`、`...genesis-results.jsonl`；这是中间失败证据，不能覆盖或改写成 cold 通过。
- Cold Genesis-v2 production startup：卸载/重装完全相同 r10 source bundle 后，在 launch 前写入 `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-metadata.json`、`...genesis-cold-v2-command.txt`；launch exit 0，PID 67540；raw OSLog `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-oslog.ndjson`；events/results `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-events.jsonl`、`...genesis-cold-v2-results.jsonl`；验证 `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-validation.json`。独立验证同样通过 8 events seq0–7、单 session、上述全部 contract；source/pre/post installed SHA 对比 `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-hash-compare.txt` 三份均为 `aff2619cde1051078bbe58a6727b17138b2f114f18945cd5ea141ee113cda1c2`。
- Launch trace test-host 边界：targeted-v6 26/26 通过，但 test host 缺真实 `sceneConfigurationSelected` 时 trace 会保持 incomplete/invalid；test-host 通过不替代上述 production standalone authenticity。SDK 允许 UIKit returned configuration name 为 nil；本次 production observed name 实际为 exact，selected lookup 仍单独记录真实 lookup input。
- Bundle boundary：r10 Release inventory `/private/tmp/babel2-phase2a-r8-release-r10-bundle-inventory.txt` 仍含 `Base.lproj/Main.storyboardc`、`blank.html`、HTML/theme templates 和 3 个 `.appex`；target 仍编译旧 `PreloadedWebView`、`WebViewProvider`、`RootSplit`、`SceneCoordinator`、`BabelShell` 等痕迹。BoundaryTests 尚无 target-membership/resource allowlist gate；这不是 A13 或 Gate A 通过证据。
- Secrets：每次 scheme pre-action 会随机重写 ignored `SecretKey.swift`；本轮所有 package/xcodebuild/test 命令显式 unset 六个 env，最终已从可信合同快照恢复 `SecretKey.swift` hash `6bd845d77bbc4838bc81495161c2ddf07d5147349c209ee8530213c568db6fba`，`.gyb` hash `46d881c9558f535e57b51c25bc66479c6cf915f1d217ab13c0bc4908f4e22292`；六个 env 状态见 `/private/tmp/babel2-phase2a-r8-final-env-status.txt`。随机盐造成的生成 hash 漂移不等于 secrets 被设置。
- r5 失败记录仍保留（WebView probe 顺序、trace-only token raw scan、wrapper shell 变量）；r6 的历史全量结果为 44 项、r7 为 45 项，均不替代本轮 r8。当前仍无 A12 截图、A10 reconnect/disconnect trace、A13 blank/WebKit runtime、目标 iPhone、性能、视觉和最终 allowlist，因此不能宣称 Phase 1A 总体通过。

## 2026-09-05 A1/A2/A3/A7 fresh evidence（Asia/Tokyo）

本节记录在当前 commit `7b8ff453ec811c59aad857e5884d4cad14946080`（已推送）重新编译并跑出的四行证据；不改写上方 2026-09-01 r8 记录，也不代表 Phase 1A 整体通过——A4/A5/A6 剩余部分/A8–A15 和目标物理 iPhone 仍照旧 open。

- **A1**：静态引用 `iOS/AppDelegate.swift`（`override init()` 的 buildChannel 计算、`startBabel2LifecycleIfNeeded`/`bootstrapBabel2RuntimeIfNeeded` 的调用清单、`configurationForConnecting` 的无分支实现）和 `iOS/Babel2/Babel2FeatureGate.swift`（`decision(buildChannel:)` 函数体完全不读取 `buildChannel` 参数本身或任何 `CommandLine`/`ProcessInfo`/`UserDefaults`），逐条给出文件/行号和可 grep 复核的命令，并交叉引用同批 A2 的真实 runtime trace。证据：[A1-bootstrap-isolation.json](evidence/phase1a/A1-bootstrap-isolation.json)。
- **A2**：在当前 commit 分别重新编译 Debug（可执行文件 SHA `f937ceb3…`）与 Release（`69600fa7…`），对每个 channel 各跑 5 种启动参数组合（无参数、`-GenesisV2`、`-Babel2`、随机未知 flag、`-Babel2`+`-GenesisV2` 冲突组合），每次都完整 `uninstall`→`install`→`launch`→抓真实 OSLog 结构化 trace。10 次里 10 次 `generation=babel-2`、legacy 计数全部为 0；10 个 PID 互不相同（确认是真实冷启动，不是复用旧进程）。`debug-noargs` 第一次因为是全新安装后第一次冷启动，3 秒等待只抓到 6/8 事件，延长等待重跑后拿到完整 8/8——两次结果都保留在证据文件里，不是只留通过的那次。`buildChannel: .test` 只在 `Babel2FeatureGateTests.swift` 里直接构造，没有真实启动路径会用到它，故未纳入本轮 runtime 矩阵，理由写在证据文件的 `note_on_test_channel` 字段。证据：[A2-build-channel-matrix.json](evidence/phase1a/A2-build-channel-matrix.json)。
- **A3**：A2 里 Release 那 5 行的子集加上一句源码级理由（同一份 `decision(buildChannel:)` 对 Debug/Release 一视同仁，没有额外的 Release 专属参数读取分支）。这次比 2026-09-01 r8 多测了 `-Babel2`、未知 flag、冲突组合三种，且是当前 commit 重新编译的 Release 二进制，不是复用旧 SHA。证据：[A3-release-ignore-args.json](evidence/phase1a/A3-release-ignore-args.json)。
- **A7**：用 `SIMCTL_CHILD_BABEL2_OPEN_FIRST_FEED=1`（仅用于取证的环境变量开关，见 `Babel2RootViewController.swift` 注释）让 Debug app 冷启动后自动进入一个真实 feed 的文章列表（Daring Fireball），确认 8/8 事件 valid trace 后截图，再用 `xcrun simctl openurl` 发一个**已注册 scheme 但未知 host** 的 URL（`nnw://unrecognized-action-xyz`；第一次用了一个完全没注册的 scheme，被 iOS 在系统层拦下报 `LSApplicationWorkspaceErrorDomain` 115，根本没送到 App，已如实记录为废弃尝试再换用注册过的 scheme）。结果：日志只多了一行 `Babel2 external action ignored unknown external action`；launch trace 没有任何新事件；前后两张截图 SHA-256 完全一致（同一张图）。证据（含隐私裁剪过的头部截图，不含文章标题/日期/正文）：[A7-unknown-url-noop.json](evidence/phase1a/A7-unknown-url-noop.json)。

以上四行均标记"通过（需 root 复审）"——即实现代理已完成自证，但按本文件第 2 条规则仍需 root 复审后才终审通过；在 root 复审前不得引用为"Phase 1A 该行已终审关闭"。

## 2026-09-05 A8/A10/A13 fresh evidence（Asia/Tokyo，同日第二批）

在 A1/A2/A3/A7 之后，同一 commit `fb0a43f14`（已推送）继续补了三行：

- **A13**：静态确认 `blank.html` 只出现在旧共享渲染层 `ArticleRenderer.swift` 里，Babel2 当前的文章展示（`Babel2PassthroughArticleRenderer`/`Babel2LiveArticleRenderer`）完全不用 `WKWebView`；`recordLegacyWebViewBootstrap` 等探针只埋在旧类里，AppDelegate/SceneDelegate 不会调用它们。交叉复用 A2 那 10 次真实启动，`legacyWebViewBootstrapCalls` 全部为 0。证据：[A13-no-blank-html-webkit.json](evidence/phase1a/A13-no-blank-html-webkit.json)，标记通过（需 root 复审）。
- **A8（部分）**：让 App 停在 Daring Fireball 的文章列表后，依次发 `nnw://showunread`、`nnw://showtoday`、`nnw://showstarred`、`feed:https://daringfireball.net/feeds/main` 四个**已注册**的 URL。全部被 `Babel2ExternalActionParser` 正确识别（日志逐条打出 showUnread/showToday/showStarred/addFeed），但除了打一行"ignored … while Babel2 root remains active"之外零副作用——期间没有新的 launch trace 事件，前后两张截图字节级完全相同。**shortcut item 和 notification response 这两条没做**：`xcrun simctl` 没有能模拟"用户长按图标选了某个 shortcut"或"用户点了某条通知"的命令，`simctl push` 只能投递通知、不能模拟点击，所以这两条的运行时证据仍然缺，需要你在真机/模拟器上手动触发一次，我可以在你操作前后配合截图和抓日志核对同样的 no-op 模式。证据：[A8-babel2-external-action-no-legacy.json](evidence/phase1a/A8-babel2-external-action-no-legacy.json)。
- **A10（部分）**：用"启动 Settings App 把 Babel2 挤到后台，再重新 launch Babel2 让它回到前台"这个纯命令行手法（不涉及任何点击操作），验证了后台/前台切换：全程同一个 PID、同一个 launch trace session，没有产生任何新 root/legacy 事件，回到前台后文章列表和滚动位置分毫不差（唯一像素差异是 iOS 系统自己短暂画的"◄ Settings"返回提示条）。但 `xcrun simctl terminate` 只是在进程层面硬杀，不会触发 `sceneDidDisconnect`——真正的 scene disconnect（用户在多任务界面把 App 划掉）目前没有命令行手段能模拟，这半条仍然是 open，需要真机或交互式操作配合。证据：[A10-restoration-teardown.json](evidence/phase1a/A10-restoration-teardown.json)。

A13 标记"通过（需 root 复审）"；A8、A10 标记"实现进行中/证据待补"（各自的已验证子场景可视为通过，但整行还没关闭）。

## 2026-09-05 A4/A5/A9 fresh evidence（Asia/Tokyo，同日第三批）

这三行都是"restoration（状态恢复）"相关，放在一起做。核心发现：`Babel2NavigationRestoration.isValid`/`validated`/`decoded`（`iOS/Babel2/Babel2Restoration.swift`）和 `Babel2SceneComposition.makeRoot(restoration:)`（真正会被 `SceneDelegate` 调用的同一个生产函数）已经有相当扎实的单元测试，本轮在原有基础上补了两个新测试方法（`Babel2FeatureGateTests.swift`）：

- `testRestorationRejectsCorruptAndEmptyData`：覆盖 A5 点名的"损坏数据"这一半——空 Data、随机字节、截断 JSON、顶层是数组、缺必填字段，原来的测试都只覆盖"语义错误但格式合法"的输入（比如编码一个 `generation: .legacy` 的合法对象），没有测过真正的垃圾字节。
- `testRestorationRejectsEmptyRoutesNonHomeFirstRouteAndUnknownRouteValue`：覆盖 A9 点名但原来没有独立测试的三种——空 routes 数组、首 route 不是 home、routes 里出现一个枚举里根本不存在的字符串。

两个新测试连同现有 3 个相关测试（`testRestorationRejectsWrongGenerationSchemaAndRoute`、`testPlaceholderRoutesRestoreAndNavigationOwnerPopsQuickly`、`testBabel2NavigationHasOneGenerationAndRestorationWritesBabel2`）全部通过；同一改动也跑了一次全量 Debug iOS test suite，`xcresulttool` summary 为 `result: Passed`、`failedTests: 0`（比上一批的 62 多了新增的测试数）。

**这三行有一个共同的、诚实记录的缺口**：以上全部证据都是"直接调用生产的校验/root 组装函数"，不是"系统真的通过 `SceneDelegate.scene(_:willConnectTo:options:)` 读取一个真实 `UISceneSession.stateRestorationActivity`"这条端到端路径。原因：`UISceneSession` 没有公开初始化方法，测试代码构造不出一个"待恢复"的假 session；`xcrun simctl` 也没有命令能强制复现"系统把 scene 从内存里回收、但保留磁盘上的 session 记录，下次冷启动时真的走恢复流程"这个场景（`simctl terminate` 是硬杀，`uninstall`/`install` 直接抹掉 session，都不是这条路径）。这个缺口需要真机测试，或者给生产代码加一个可测试的 seam（那是一次代码改动，需要单独讨论，不在本轮"只取证不改产品行为"的范围内）。

证据：[A4-release-accepted-persisted.json](evidence/phase1a/A4-release-accepted-persisted.json)、[A5-stale-generation-fail-closed.json](evidence/phase1a/A5-stale-generation-fail-closed.json)、[A9-restoration-validation.json](evidence/phase1a/A9-restoration-validation.json)，三行均标记"实现进行中/证据待补"。

## 2026-09-05 A11/A15 fresh evidence（Asia/Tokyo，同日第四批）

- **A11**：在已有的"30 次进程内 create/teardown"单元测试之外，新增一个同样跑 30 次、但真正 `loadViewIfNeeded()` 触发 `viewDidLoad`（手势 delegate、NotificationCenter 观察者注册、控件搭建全部真实跑一遍）、每轮都恢复 `[.home, .settings]` 两层路由并断言路由正确的测试；30 轮结束后再 post 一次通知确认不崩溃。**更进一步**，做了一次本轮独有的"真实生产级"证据：30 次完整的 `uninstall`→`install`→`launch` 冷启动循环（不是进程内构造对象），每轮立即单独抓日志（吸取教训，见 LESSONS.md 第 25 条），结果 **30 个不同 PID、30 个不同 session、30/30 次 trace 全部 valid+complete+babel-2+零 legacy 计数**，无一例外。证据：[A11-30-cycle-stress.json](evidence/phase1a/A11-30-cycle-stress.json)，标记通过（需 root 复审）。
- **A15**：先按 A1/A7/A8/A9/A10/A13 已经查证的代码位置，汇总出 generation 决策、root/navigation、restoration/teardown、external fallback 这四类各自只有一个 owner 的交叉引用清单。再独立复核了现有的 Gate A 自动化测试（`Babel2BoundaryTests.sourceBoundaryContainsNoLegacyUIOrWebViewDependencies`），**发现它的扫描范围本身有缺口**：只扫了 `Babel2Core`/`Babel2UI`/`iOS/Babel2` 三个目录，漏了同样是新增 Babel2 内容的 `iOS/Babel2Integration/` 和 `iOS/Babel2ExternalActionParser.swift`。补扫后发现 `Babel2LiveDataAdapters.swift` 里有 6 处 `AccountManager.shared`——这本身是合理的（它是全仓库唯一、集中的真实数据桥接层，符合 ADR-001 的"复用账户服务"），但因为一直没被这项自动化盯着，随时可能在没人注意的情况下扩散到第二个文件。已经把扫描范围扩大并给这一个文件加了精确的、和 `Babel2FeatureGate.swift` 同样写法的文件级白名单条目，现在测试会在这个模式被打破时立刻报红。另外确认了 `LegacyIdentityCompatibility` 边界目前在全仓库零实现（不是本轮回归，是如实记录现状），accessibility identifier/log category/本地化字符串没有发现任何旧品牌/旧命名泄漏。证据：[A15-owner-and-gate-audit.json](evidence/phase1a/A15-owner-and-gate-audit.json)，标记"实现进行中/证据待补"（single-owner 与 Gate A 扫描部分视为通过，persisted identity 边界和完整 target/resource allowlist 仍 open）。

同一改动重新跑过一次全量 Debug iOS test suite：exit 0，`xcresulttool` summary `result: Passed`、`failedTests: 0`、`passedTests: 65`。

## 2026-09-05 A12 fresh evidence（Asia/Tokyo，同日第五批）

第一次尝试假设"调用 `xcrun simctl launch` 那一刻"约等于"进程真正开始跑"，结果三张截图全部拍在真实进程启动**之前**（差了 2-2.5 秒的 simctl 往返与冷启动开销），是无效证据，已如实丢弃不冒充通过。改正做法：冷启动后不设时间假设，连续密集拍 12 张（工具本身开销自然形成约 0.35-0.4 秒的采样间隔），每张都用纳秒级时间戳精确定位，再用同一轮真实 trace 的 processEntry 挂钟时间反推每张截图相对"真实进程启动"的精确偏移，选出最接近 +0.5s/+1.0s/+2.0s 的三张（实测分别为 +0.307s、+1.108s、+2.272s），外加一张"进程启动前一瞬间"（-0.097s，系统启动图）作为对照。

三张截图内容：+0.307s 已经是完整的 Babel2 Feeds 页面结构（顶部工具栏+底部三档切换+"Babel/No feeds"占位水印），+1.108s 显示真实源名称但图标是占位灰圆点，+2.272s 图标基本加载完成、源数量从 7 个增加到 9 个（后台同步补上）。三张都是同一个 Babel2 root，没有一帧出现旧版着陆页、空白跳变或重复壳，只有正常的数据渐进加载。本轮启动的 contentFirstFramePresented 比 processEntry 只晚 0.117 秒——整个首帧流程比 0.5 秒还快，所以三个采样点看到的都已经是"结构就绪、数据陆续到位"的稳定状态，这本身也满足"1.0s 与 2.0s 必须显示同一 root"的要求。

证据（含完整方法论、时间戳反推过程和四张截图路径）：[A12-0.5-1.0-2.0s-screenshots.json](evidence/phase1a/A12-0.5-1.0-2.0s-screenshots.json)。标记"结构性证据通过（需 root 复审）"——我能确认的是"有没有旧元素、有没有空白、是不是同一个 root"这类结构性事实；图标裁切整不整齐、加载观感顺不顺这类主观判断仍需要用户自己看这四张截图确认，不冒充视觉验收。

## 当前静态 P1（修复中）

以下是 Phase 1A 仍要求关闭的静态/结构或证据缺口；其中已由本批自动化覆盖的项目须经 root 复审后才能关闭：

- canonical external parser：当前唯一 parser owner 和 unknown URL typed no-op 已有 iOS tests/static boundary，真实外部回调仍待补。
- trace event order：当前 AppDelegate-owned recorder 的 order/session/uptime/JSON/legacy-event invalidation 在 iOS tests 中通过，r8 no-args/cold Genesis production trace 也逐条验证 8 events；仍需由 root 复审并归档到 A0/A6，测试 direct handler 不冒充 OS callback。
- pending restoration validity：当前 generation/schema/route/corrupt tests 通过；Release/session 恢复矩阵仍待补。
- observer/async teardown：Babel2 navigation/root 30-cycle teardown tests 通过；`recordTeardown` 现在会进入同一短 JSON logger，但真实 scene disconnect/reconnect A10 证据仍待补。
- weak coordinator nil safety：当前 Babel2 callbacks 使用 weak/token guard；旧 coordinator 低层 teardown test 保留作为历史实现保护，production graph 不再引用它。
- 真实 scene coverage：r8 已在目标 Simulator 对同一 Release-r10 binary 完成 no-args 与 cold Genesis standalone startup trace（各 8 events、final valid/complete），但 scene 重连、后台/前台和 teardown 的独立 A10 trace 仍待补。
- Gate A allowlist：当前 boundary test 检查 AppDelegate/SceneDelegate/Info.plist 的旧 production route 缺失，并为 trace identity 保留 file-scoped diagnostic token allowlist；完整逐命中清单、target-membership/resource allowlist 和 root 复审仍待补。

## 证据回填模板

每个 `evidence path` 对应一个 JSON/JSONL 或截图 bundle；最小记录如下（截图需另附原始 PNG 与采集时间）：

```text
id: A?
commit_or_worktree: uncommitted worktree | <exact SHA>
captured_at: <YYYY-MM-DD HH:mm:ss Asia/Tokyo>
environment: <device / OS / SDK / scheme / configuration>
build_channel: debug | test | release
launch_arguments: <complete list>
command_or_steps: <exact command or numbered UI steps>
observed: <actual result, not expectation>
limitations: <missing device, screenshot-only, etc.>
owner: <named accountable owner>
status: 实现进行中/证据待补 | 通过（需 root 复审） | 失败
```

## 停止条件

- A0 或 A1 发现 gate 晚于任何 AppDelegate legacy lifecycle/bootstrap：按 P0 停止扩大页面实现，先修复启动时序并重新跑 A2、A6、A12。
- A3–A5 任一 Release 行不能区分 ignored args、合法 persisted 和 corrupt→legacy：Phase 1A 保持 open。
- A7 未识别 URL 触发 fallback、A8 未识别输入进入 legacy、A10 出现第二 owner、A11 出现 retained controller，均为失败，不得用截图覆盖。
- A13 发现 blank.html/WebKit 进入 Phase 1A root 启动路径，必须移除该副作用并重跑 launch trace。
- A15 出现未登记旧 token、allowlist 越过 build/test harness 或出现第二 persisted/system identity 出口，Gate A 失败；不得以“历史代码”标绿。

## Phase 3 交叉边界（2026-09-01，Asia/Tokyo）

Phase 3 只实现账户限定的 Feed→Article 数据垂直切片，不改变本文件 A0–A15 的验收门槛，也不把页面自动化、Release root 截图或测试 host 结果提升为 Phase 1A 通过。主控复审结论限定为“实现代码 P0/P1=0”；Phase 3 持久 evidence gate 已关闭，入口为 [evidence/phase3/manifest.json](evidence/phase3/manifest.json)；Phase 1A 仍保持“修复中 / 证据待补”。

本切片涉及的实现文件精确为：`Modules/Babel2UI/Sources/Babel2Core/Contracts.swift`、`Modules/Babel2UI/Sources/Babel2Core/Snapshots.swift`、`Modules/Babel2UI/Tests/Babel2UITests/Babel2UITests.swift`、`iOS/Babel2Integration/Babel2LiveDataAdapters.swift`、`iOS/Babel2/Babel2DataAdapters.swift`、`iOS/Babel2/Babel2RootViewController.swift`、`iOS/Babel2/Babel2LibraryViewControllers.swift`、`iOS/Babel2/Babel2SceneComposition.swift`、`Tests/NetNewsWire-iOSTests/Babel2FeedReaderTests.swift`，及 `NetNewsWire.xcodeproj/project.pbxproj` 对该测试的最小 group/Sources membership；本次同步的项目文档为 `STATUS.md`、`HANDOFF.md`、`PHASE1A-ACCEPTANCE.md`、`VALIDATION.md`、`README.md`。

验收解释：typed identity 明确隔离 account/feed/article 三元组；缺 canonical URL 的 cached-body article 不丢弃，Open Original 在缺 URL 时隐藏；root 只载入元数据，不用全库文章或 SmartFeeds union 取得列表/假 count；Feed 使用真实 `feedArticlesSnapshot(for:)` 与已加载 snapshot；异步更新需满足取消、generation 与 identity guard。该实现没有修改 Account/Articles/ArticlesDatabase/SmartFeeds，也没有引入新的 repository/cache/sync/WebKit 或后续产品功能。

Phase 3 证据只关闭自身的 package、targeted、full-test 和 simulator build 层：package 31/31；targeted `Babel2FeedReaderTests` 4/4；full Debug xcresult 56/56；Debug r3、Release r1 build 成功。持久摘要为 [evidence/phase3/manifest.json](evidence/phase3/manifest.json)、[evidence/phase3/test-results-targeted-summary.json](evidence/phase3/test-results-targeted-summary.json)、[evidence/phase3/test-results-full-summary.json](evidence/phase3/test-results-full-summary.json)、[evidence/phase3/build-results.json](evidence/phase3/build-results.json)；`/private/tmp/babel2-phase3-*.log` 与 `.xcresult` 仅为原始临时来源，失败轮次见 [evidence/phase3/validation-iterations.json](evidence/phase3/validation-iterations.json)。目标 Simulator 的 Release r1 no-args cold launch 真实显示 Feeds root，缓存检查为 10 个 FeedSettings、articles/statuses/search 各 424 行且 SQLite integrity `ok`；因没有 tap/accessibility 驱动，单源→文章→正文/Open Original 记为 `INTERACTION BLOCKED`。这不关闭 A10/A12/A13/A15、旧 bundle/resource allowlist、目标物理 iPhone、性能/视觉/手势或完整 scene 恢复。

本切片保留的后续 P2 为 cache 先读后验证/无界和同名标题稳定 tie-break；不得在本轮借机扩展 cache engine 或排序架构。旧 storyboard/nib、3 个 `.appex`、物理真机和产品范围仍按本文件既有停止条件处理。SecretKey 已在最后验证后恢复可信快照，最终 hashes 与六个环境变量 unset 证据在 [evidence/phase3/secret-status.json](evidence/phase3/secret-status.json)。

## Phase 3B 交叉边界：真实 Simulator UI driver（2026-09-01，Asia/Tokyo）

Phase 3B 的 UI driver 证据不改变 A0–A15 的门槛，也不把 XCUITest、root/feed/reader 截图或 SafariViewService handoff 提升为 Phase 1A 通过。主控复审结论仍限定为“实现代码 P0/P1=0”；截图隐私和 bundle digest 的 P1 correction 已应用并通过独立只读复核，manifest 状态为 `phase3b_evidence_gate_closed_after_independent_recheck`，该 gate 仅覆盖 Phase3B implementation + automation + persistent evidence，不暗示 Phase1A 或全产品完成；本文件整体仍为“修复中 / 证据待补”。复核没有重跑 build/test/install/launch。持久入口为 [evidence/phase3b-ui/manifest.json](evidence/phase3b-ui/manifest.json)。

本切片精确修改：`Tests/NetNewsWire-iOSTests/Babel2FeedReaderUITests.swift`；`NetNewsWire.xcodeproj/project.pbxproj` 的独立 UI-testing target 与最小 membership；`NetNewsWire.xcodeproj/xcshareddata/xcschemes/NetNewsWire-iOS UI Driver.xcscheme`；`xcconfig/NetNewsWire_iOSUITests_target.xcconfig`；`iOS/Babel2/Babel2LibraryViewControllers.swift` 的稳定 identifiers；Phase 3 manifest tree hash wording；五份项目文档及 `evidence/phase3b-ui/**`。不涉及 AppDelegate/SceneDelegate、Account/Articles/ArticlesDatabase/SmartFeeds、旧资源清理或后续产品功能。

target/scheme 静态枚举在 escalated 环境成功；Release build-for-testing r1/r2 成功。UI r1 实际执行 1 test 但为修复前 selector 的 `UI_SELECTOR_TIMEOUT`，保留为失败轮次；UI r2 与相同 r2 产物的 r3 均实际执行 1/1 passed。driver 断言了无参启动、10 个真实 root feed rows、当前 UI 顺序的 source→缓存文章→非空正文、Open Original 的 SafariViewService foreground 以及 article back→feed back→root 恢复。feed.png 已确定性裁为只含顶部 status/header/feed name/count 的 1206×390 crop，不含文章标题、日期、正文或 URL；reader/after-browser 截图和 hierarchy 未进入 repository evidence，避免写入正文/URL。

这仍不能关闭 A10/A12/A13/A15、scene reconnect/disconnect、目标物理 iPhone、真实视觉/性能/手势、旧 storyboard/nib 与 3 个 `.appex` allowlist。另有明确数据边界：`articles/statuses/search` 在安装/测试序列观察到 `424→425→426`，伴随 container rotation；r3 同一 r2 artifact 前后稳定为 426，FeedSettings=10，integrity=`ok`。分类为 `UNEXPECTED_DATA_MUTATION`，原因未证实，不得归因后台同步或声称 read-only。cache first-hit/验证/无界、同名 tie-break 和 Open Original 无 URL 语义缺口仍为后续 P2，不在本轮扩架构；enabled URL → SafariViewService 的路径仅保留为已通过运行时断言。
