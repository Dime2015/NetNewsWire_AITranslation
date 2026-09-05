# Babel 2.0 验证记录

本文件只记录可追溯证据。每一行必须绑定提交或明确标记为未提交工作树，注明日期、环境、范围和限制。旧代理报告可以作为线索，但没有在当前环境重新运行时，不能写成当前验证。

## 证据规则

- 静态检查只能证明结构；不能证明运行时行为、性能、动画跟手或视觉接受。
- 模拟器构建只能证明该构建可编译/启动到指定状态；不能替代目标 iPhone 的 safe area、真实网络、字体、手势和性能验收。
- Figma 或静态截图只能锁定设计意图；不能证明当前代码已经接通。
- “未发现错误”不能替代覆盖对应需求的测试；失败或缺证据的项目必须保持未验收。
- 每次提交和推送都要把验证结果回填本文件，并指向精确提交，而不是只写“已测试”。

## 2026-09-01 Phase 2A r8 fresh validation（uncommitted worktree）

环境：Xcode 27.0 / iOS 27.0 SDK；目标 Simulator 为 iPhone 17，UDID `555E35FA-6BFE-45F0-BCFC-0819FFE48CD2`。本轮所有 package/xcodebuild/test 命令均显式 unset `MERCURY_CLIENT_ID`、`MERCURY_CLIENT_SECRET`、`FEEDLY_CLIENT_ID`、`FEEDLY_CLIENT_SECRET`、`INOREADER_APP_ID`、`INOREADER_APP_KEY`；build/test 写入独立 `/private/tmp/babel2-phase2a-r8-*` 路径。scheme pre-action 会随机重写 ignored SecretKey，本轮每次 build/test 后都备份生成文件并从可信合同快照恢复，最终 hash 见下文。当前 Git anchor 为 branch `codex/reeder-classic-rebuild`、HEAD `5db240499806bc4cae9be0b82194c838a32229de`、remote-tracking `1269bb9087d896a7a9e29f174461d60b47134575`；结果绑定未提交工作树，不是新 commit。

| 检查 | 精确命令/配置 | 结果与实际数量 | 证据路径 / 限制 |
|---|---|---|---|
| Babel2UI package tests | `env -u MERCURY_CLIENT_ID -u MERCURY_CLIENT_SECRET -u FEEDLY_CLIENT_ID -u FEEDLY_CLIENT_SECRET -u INOREADER_APP_ID -u INOREADER_APP_KEY swift test --package-path Modules/Babel2UI` | exit 0；Swift Testing 30/30 通过（XCTest compatibility summary 的 0 项不计入） | `/private/tmp/babel2-phase2a-r8-package-tests-final.log`、exit `/private/tmp/babel2-phase2a-r8-package-tests-final-exit.txt`；不证明 iOS scene/真机 |
| 全量 Debug iOS tests | `env -u MERCURY_CLIENT_ID -u MERCURY_CLIENT_SECRET -u FEEDLY_CLIENT_ID -u FEEDLY_CLIENT_SECRET -u INOREADER_APP_ID -u INOREADER_APP_KEY xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS -configuration Debug -destination 'id=555E35FA-6BFE-45F0-BCFC-0819FFE48CD2' -derivedDataPath /private/tmp/babel2-phase2a-r8-ios-debug-tests-final-dd -resultBundlePath /private/tmp/babel2-phase2a-r8-ios-debug-tests-final.xcresult test` | exit 0；console XCTest 34/34（Babel2FeatureGate 26、Babel2MotionDriverRuntime 8）+ Swift Testing 18 = 52； | 日志 `/private/tmp/babel2-phase2a-r8-ios-debug-tests-final.log`、exit `/private/tmp/babel2-phase2a-r8-ios-debug-tests-final-exit.txt`、result `/private/tmp/babel2-phase2a-r8-ios-debug-tests-final.xcresult`；真实 app 在目标 Simulator 测试，但不替代目标 iPhone/截图 |
| Debug build | `env -u MERCURY_CLIENT_ID -u MERCURY_CLIENT_SECRET -u FEEDLY_CLIENT_ID -u FEEDLY_CLIENT_SECRET -u INOREADER_APP_ID -u INOREADER_APP_KEY xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS -configuration Debug -destination 'id=555E35FA-6BFE-45F0-BCFC-0819FFE48CD2' -derivedDataPath /private/tmp/babel2-phase2a-r8-debug-build-final-dd -resultBundlePath /private/tmp/babel2-phase2a-r8-debug-build-final.xcresult build` | exit 0；日志含 `** BUILD SUCCEEDED **` | `/private/tmp/babel2-phase2a-r8-debug-build-final.log`、`/private/tmp/babel2-phase2a-r8-debug-build-final.xcresult`；不证明视觉/真机 |
| Release-r10 build | `env -u MERCURY_CLIENT_ID -u MERCURY_CLIENT_SECRET -u FEEDLY_CLIENT_ID -u FEEDLY_CLIENT_SECRET -u INOREADER_APP_ID -u INOREADER_APP_KEY xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS -configuration Release -destination 'id=555E35FA-6BFE-45F0-BCFC-0819FFE48CD2' -derivedDataPath /private/tmp/babel2-phase2a-r8-release-r10-dd -resultBundlePath /private/tmp/babel2-phase2a-r8-release-r10.xcresult build` | exit 0；日志含 `** BUILD SUCCEEDED **`；app executable SHA `aff2619cde1051078bbe58a6727b17138b2f114f18945cd5ea141ee113cda1c2` | `/private/tmp/babel2-phase2a-r8-release-r10.log`、`/private/tmp/babel2-phase2a-r8-release-r10.xcresult`；可复用于下方两次 standalone launch，不证明视觉/真机 |
| Production lifecycle boundary | `Babel2BoundaryTests.productionLifecycleHasNoLegacyRootOrFallbackRoute`、`repositoryHasExactlyOneCanonicalExternalActionParser`（随上行 iOS test 执行） | 通过当前 test scope；检查 AppDelegate/SceneDelegate/integration/parser/Info.plist、trace-only diagnostic allowlist、parser 唯一 owner 和旧 production route 缺失；不检查 target membership/resource allowlist | 同一 r8 log；磁盘上的旧实现和 `Main.storyboard` 保留，未改 target membership |
| xcresult summary parse | `xcrun xcresulttool get test-results summary --path /private/tmp/babel2-phase2a-r8-ios-debug-tests-final.xcresult` | escalated exit 0；result `Passed`、total 52、passed 52、failed 0、skipped 0；device 为 iPhone 17 / iOS 27.0 / requested UUID；console 口径为 XCTest 34 + Swift Testing 18 | `/private/tmp/babel2-phase2a-r8-ios-debug-tests-final-xcresult-summary-escalated.json`；sandbox 权限失败原始输出 `/private/tmp/babel2-phase2a-r8-ios-debug-tests-final-xcresult-summary.json` |
| Bundle inventory | 对 Release-r10 app 执行 `find` 盘点 | app 仍含 `Base.lproj/Main.storyboardc`、`blank.html`、HTML/theme templates 和 3 个 `.appex`，target 仍编译旧 PreloadedWebView/WebViewProvider/RootSplit/SceneCoordinator/BabelShell；A13/最终 resource allowlist 未关闭 | `/private/tmp/babel2-phase2a-r8-release-r10-bundle-inventory.txt`、关键项 `/private/tmp/babel2-phase2a-r8-release-r10-bundle-inventory-key-items.txt` |

### Release-r10 standalone launch trace

这两次运行绑定同一 Release-r10 source app 与安装 executable SHA `aff2619cde1051078bbe58a6727b17138b2f114f18945cd5ea141ee113cda1c2`；两次 launch 之间没有源代码修改或 rebuild。每次 launch 前都先写入 exact command、UDID、bundle ID、完整 args、UTC/local timestamp、source/installed path 与 SHA metadata；launch stdout/stderr、PID、raw OSLog 和 post-launch SHA 单独保存。canonical runtime evidence 是 clean `oslog-records.jsonl` 与 events/results、metadata/SHA 的组合；raw `oslog.ndjson` 保留采集工具头，不能单独作为 canonical records 文件。

| 场景 | 命令/参数 | 实际结果 | 证据 |
|---|---|---|---|
| no-args cold | `xcrun simctl launch 555E35FA-6BFE-45F0-BCFC-0819FFE48CD2 com.wenbopan.NetNewsWire.iOS`；`args=[]`；launch exit 0 | PID 66644；8 event lines，seq `0..7`，单 session `BDB510F4-CCBF-42FF-ACC9-8644322AC290`；final result `isComplete=true`、`isValid=true`、`invalidReasons=[]`。独立 validator 逐项确认 exact lookup、observed actual exact、delegate `SceneDelegate` + metatype bool true、storyboard false、4 surfaces identity/geometry/visible-key、legacy kinds/counters 0、event/result line <900 bytes、OSLog PID 与 launch PID 相同。 | metadata `/private/tmp/babel2-phase2a-r8-standalone-r10-noargs-metadata.json`；command `/private/tmp/babel2-phase2a-r8-standalone-r10-noargs-command.txt`；launch `/private/tmp/babel2-phase2a-r8-standalone-r10-noargs-final-launch.log`；raw `/private/tmp/babel2-phase2a-r8-standalone-r10-noargs-final-oslog.ndjson`；events/results `/private/tmp/babel2-phase2a-r8-standalone-r10-noargs-events.jsonl`、`/private/tmp/babel2-phase2a-r8-standalone-r10-noargs-results.jsonl`；validation `/private/tmp/babel2-phase2a-r8-standalone-r10-noargs-final-validation.json`；pre/post installed SHA `/private/tmp/babel2-phase2a-r8-standalone-r10-installed-prelaunch-binary.sha256`、`/private/tmp/babel2-phase2a-r8-standalone-r10-noargs-postlaunch-installed-binary.sha256` |
| warm `-GenesisV2` intermediate failure | `xcrun simctl launch 555E35FA-6BFE-45F0-BCFC-0819FFE48CD2 com.wenbopan.NetNewsWire.iOS -GenesisV2`；terminate 后未卸载 | PID 67180；系统复用既有 scene session，7 events，缺 `sceneConfigurationSelected`，final invalid `sceneConfigurationSelectionMissing`。这是保留的真实失败，不改写为通过。 | raw `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-final-oslog.ndjson`；events/results `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-events.jsonl`、`/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-results.jsonl`；warm failure hash/terminate logs 同前缀 `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-warm-*` |
| cold `-GenesisV2` | 卸载/重装同一 Release-r10 source app 后：`xcrun simctl launch 555E35FA-6BFE-45F0-BCFC-0819FFE48CD2 com.wenbopan.NetNewsWire.iOS -GenesisV2`；`args=["-GenesisV2"]`；launch exit 0 | PID 67540；8 event lines，seq `0..7`，单 session `0EB8F079-E1A2-4712-85C8-F5896F3CBEC0`；final result `isComplete=true`、`isValid=true`、`invalidReasons=[]`。同一 validator 逐项确认上述全部 contract；source/pre/post installed executable SHA 三份均为 `aff2619cde1051078bbe58a6727b17138b2f114f18945cd5ea141ee113cda1c2`。 | metadata `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-metadata.json`；command `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-command.txt`；launch `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-launch.log`；raw `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-oslog.ndjson`；events/results `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-events.jsonl`、`/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-results.jsonl`；validation `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-validation.json`；SHA compare `/private/tmp/babel2-phase2a-r8-standalone-r10-genesis-cold-v2-hash-compare.txt` |

Validator source used for both cold runs: `/private/tmp/babel2-phase2a-r8-standalone-trace-validator.jq`. It emits and checks event count, unique sequence/session, exact milestone order, uptime monotonicity, process/decision/result binding, lookup/observed name semantics, actual delegate identity, storyboard evidence, root identity/geometry/visibility, legacy kinds/counters, OSLog PID binding and short-line limits. `configurationName` is privacy-filtered: wrong raw names are not serialized, while `configurationNameMatchesExpected=false` remains as intentional evidence. Test-host `Babel2FeatureGateTests` 26/26 is structural evidence only; when UIKit test-host omits `sceneConfigurationSelected`, the trace remains incomplete/invalid and does not substitute for production standalone authenticity.

### Secrets pre-action side effect

scheme pre-action 会扫描 `.gyb` 并随机重写 ignored `Modules/Secrets/Sources/Secrets/SecretKey.swift`。r8 package/build/test 前后均显式 unset 六个 secret env，生成文件每次另存后从可信合同快照恢复；最终 `SecretKey.swift` 为 `6bd845d77bbc4838bc81495161c2ddf07d5147349c209ee8530213c568db6fba`，`.gyb` 为 `46d881c9558f535e57b51c25bc66479c6cf915f1d217ab13c0bc4908f4e22292`。本轮状态见 `/private/tmp/babel2-phase2a-r8-final-secret-hashes.txt` 与 `/private/tmp/babel2-phase2a-r8-final-env-status.txt`；生成文件没有作为本批实现修改提交。随机盐会造成生成后 hash 漂移，不等于 secrets 被设置。

### Correction 失败轮次

- `/private/tmp/babel2-phase2a-correction-debug-tests-r5.log` 与 `/private/tmp/babel2-phase2a-correction-debug-tests-r5.xcresult` 保留为失败证据：XCTest 26 中 5 个 legacy WebView fixture 断言把事件注入在 content first frame 后；生产语义正确地丢弃 launch-window 外 WebView probe。另有 3 个 Swift Testing boundary issues：trace-only source/event 字面量被 raw token scan 误报，及 wrapper 使用 zsh 保留变量。没有将 r5 计入通过。
- 首次 sandbox 轮次的 SwiftPM/Clang cache `Operation not permitted` 日志（包括 `/private/tmp/babel2-phase2a-correction-debug-build.log`）保留，不计入通过；r7 使用明确权限重跑。Debug build 首次 r7 wrapper 直接执行因临时脚本无执行位 exit 126，随后显式 `zsh` 调用成功；一次旧版 `xcresulttool get --format json` 命令 exit 64 因 deprecated syntax，随后用 `get object --legacy` 成功解析；这是工具/包装命令失败，不是源码 build/test 失败。
- r8 targeted-v1 的 21/21 结果保留但不计入最终：测试错误地把 SDK 合同允许的 returned `UISceneConfiguration.name == nil` 判为失败；随后依据 iOS 27 SDK 声明修正为“真实 lookup request 必须 exact，returned name 允许 nil，非 nil 必须 exact”，并增加 privacy-safe tri-state mismatch 与 actual delegate metatype 检查。targeted-v6 最终为 26/26。
- r8 warm Genesis attempt 保留为真实运行失败：terminate 后不卸载直接 `-GenesisV2`，系统复用 scene session，7 events 缺 `sceneConfigurationSelected`，final invalid `sceneConfigurationSelectionMissing`；卸载/重装同一 r10 app 后 cold Genesis-v2 才获得 8 events/final valid。不得把 warm failure 的日志覆盖成 cold 通过。
- r6 的历史全量 iOS 结果为 44 项、r7 为 45 项；两者都不是当前 r8 source state 的数量。r8 重新执行后以 package 30/30、targeted gate 26/26、full iOS 52/52（console XCTest 34 + Swift Testing 18）和 Release-r10 standalone cold traces 为准。

## 已有提交与证据快照

| 日期 | 提交/范围 | 已记录证据 | 当前可得结论 | 限制 |
|---|---|---|---|---|
| 历史记录 | `649f85fd50e5fff21e75818193011250baf08d50`，v0.5 | Git 版本锚点 | 历史 v0.5 基线存在 | 未在本轮重跑，不证明 Babel 2.0 |
| 历史记录 | `d1679c7f253d37eda557970fca0827c096132a05`，v1.0 | Git 版本锚点 | 历史 v1.0 基线存在 | 未在本轮重跑，不证明 Babel 2.0 |
| 历史记录 | `a94c00626edf13bb3e869c35924bfd6ece7e6165`，v1.1 | Git 版本锚点；当前 HEAD 是其后代 | Babel 2.0 的迁移起点可定位 | 未在本轮重跑；不是当前完整工作树 |
| 2026-08-31 前序记录 | `e72ee768fa70b0cff9dbbd75c1f3eb59a910669c` | 产品/运动合同初版提交 | 合同初版已提交 | 后续合同同步已由 `ce7c0ea38da3cb8bcab9a01dd6bd712b215ae6d9` 覆盖 |
| 2026-08-31 合同 amendment 提交/已推送 | `1269bb9087d896a7a9e29f174461d60b47134575` | 规范版本 QA PASS；已明确授权并完成非 force push | 产品/运动合同 amendment 状态为 `completed/committed` | 当前合同不是动态工作树状态源；产品实现仍未完成 |
| 2026-08-31 前序记录 | `dbcc276549c7f573a98668ef1b38721b8747adb3` | 前序代理报告：Babel2 package tests 2/2、边界测试 2/2、配置测试 6/6、iOS Debug simulator build 成功 | Phase 0 隔离基础曾有通过报告 | 本轮未重新运行；不能推广为 M1、runtime 或真机通过 |
| 2026-08-31 前序记录 | `9fda5c5650d06ff5155ead466adbe1b084ccdd44` | Light/Dark/Mono 静态资源、独立 catalog；root 逐图检查、独立 QA、actool 和小尺寸结构 QA 已通过 | 图标设计/静态资产已完成并提交 | 用户先选定 Dark，并授权生成后直接作为 Babel 2.0 图标；早期“烧焦/全局黑蒙版”Light 被否决，之后按亮木桌、独立暗色封面、干净页边重生成当前 Final；Round 4 草稿不构成回退。runtime appearance、模拟器解析和 Home Screen 仍未验收；不声称用户逐像素口头确认最终 Light。Dark 可复现 master：`Design/Babel2/Icon Concepts/Final/Babel2AppIcon-Dark.png`；用户临时附件仅作 provenance |
| 2026-08-31 M1 本地提交 | `5db240499806bc4cae9be0b82194c838a32229de`，`Babel 2.0 M1: add interruptible motion foundation` | 此前绑定该 M1 commit 的第 5 轮独立 QA PASS；30 项 package tests、8 项真实 iOS UIKit runtime tests、8 项 Boundary/Shell tests、Debug build 均通过 | 仅证明 M1 contract layer completed / local committed；不是本次 Phase 1A final QA；remote push pending | 14 files / 2618 insertions；iPhone 17 / iOS 27 Simulator；真机 120Hz 手感和 OSLogStore consumer integration pending；等待用户对具体 commit 授权 |

## M1 已收到的命令、环境和结果范围

以下记录的是第 5 轮独立 QA 重新执行的结果范围；它们绑定本地 M1 commit `5db240499806bc4cae9be0b82194c838a32229de`，不是对远端已推送的声明。所有结果均在 iPhone 17 / iOS 27 Simulator 环境下获得；真机 120Hz 手感和 OSLogStore consumer integration 仍未完成。

| 检查 | 报告命令/配置 | 环境与结果 bundle | 退出结果 | 证据边界 |
|---|---|---|---|---|
| Package tests | `swift test --package-path Modules/Babel2UI` | Swift Package Debug；Babel2UI test / xcresult bundle，30 项通过 | exit 0（第 5 轮独立 QA） | 不证明真机手感或 consumer integration |
| UIKit runtime tests | `xcodebuild test`，目标 `platform=iOS Simulator,name=iPhone 17,OS=27.0` | iPhone 17 / iOS 27 Simulator；真实 UIKit runtime test / xcresult bundle，8 项通过 | exit 0（第 5 轮独立 QA） | 真机 120Hz 手感仍 pending |
| Boundary/Shell tests | 同一 iOS Debug test configuration，目标 `platform=iOS Simulator,name=iPhone 17,OS=27.0` | iPhone 17 / iOS 27 Simulator；Boundary/Shell / xcresult bundle，8 项通过 | exit 0（第 5 轮独立 QA） | 不证明完整页面 consumer 接入 |
| Debug build | `xcodebuild build`，configuration `Debug`，目标 `platform=iOS Simulator,name=iPhone 17,OS=27.0` | iPhone 17 / iOS 27 Simulator；Debug build / xcresult bundle | exit 0（第 5 轮独立 QA） | 编译通过不等于真机/视觉通过 |

第 5 轮独立 QA 已确认上述 M1 contract layer 通过；后续仍需在页面 consumer 和目标设备层重验统一 motion owner、120Hz 真机手感与 OSLogStore consumer integration。该结果不能推出 Babel 2.0 页面已完成或远端已经包含 M1 commit。

## Phase 1A 当前证据状态

截至 2026-09-01，Phase 2A r8 fresh validation 已修复前序源码编译/root 约束/test-host 断言/r5 fixture 顺序/token 误报问题：package 30/30、全量 Debug iOS results 52/52、Debug build 和 Release-r10 build 均通过；同一 Release-r10 app 的 no-args 与 cold `-GenesisV2` standalone trace 各为 8 events/final valid。Phase 1A 总体仍为 **修复中 / 证据待补**，因为 A0/A1/A6/A8/A12/A13 还缺逐项归档、A10 scene reconnect/disconnect、0.5/1/2 秒截图、完整参数/恢复矩阵、目标 iPhone、最终 target/resource allowlist 和视觉/性能证据。当前工作树实现未提交，不能由代码存在、52 项自动化结果或 simulator startup trace 升级为 Phase 1A 总体/production package 通过。

独立审查的 P0 根因是 generation gate 晚于 `AppDelegate` legacy lifecycle/bootstrap；本批把 decision 固定在 AppDelegate 初始化边界，SceneDelegate 只创建 Babel2 root，外部动作不再切 legacy。后续仍须用 A0/A1/A6 trace 证明 gate 在所有旧副作用之前，并用 A2–A5 覆盖单轨输入边界；A7–A15 的 no-op、恢复/销毁、30-cycle、截图、no blank.html/WebKit、single owner 和 Gate A exact allowlist 也要分别留证。

### 前序独立 QA（历史记录）

前序 `/private/tmp/babel2-phase1a-final-*` 记录中的 `SceneDelegate` `private(set) launchTrace` 编译错误和 iOS tests 0 项均为已修复前的历史尝试，不代表当前工作树；旧安装包、旧截图和先前代理报告不能替代本次 fresh evidence。

### 当前结构缺口

canonical parser、trace order、restoration validity、Babel2 observer/async teardown、weak/token callback safety 和生产 lifecycle boundary 已由当前代码及 iOS tests/static boundary 覆盖，待 root 复审；真实 scene 重连/后台恢复/teardown、完整参数矩阵、0.5/1/2 秒截图、目标 iPhone、性能/视觉和 Gate A target-membership/resource 逐命中清单仍待补。r10 startup trace PASS 不等于 production package PASS：target 仍编译旧 PreloadedWebView/WebViewProvider/RootSplit/SceneCoordinator/BabelShell，bundle 仍含 Main.storyboardc、blank.html、themes 和 3 个 appex。

Phase 1A 证据索引（待生成）：

`Design/Babel2/Project/evidence/phase1a/A0-generation-order.json`
`Design/Babel2/Project/evidence/phase1a/A1-bootstrap-isolation.json`
`Design/Babel2/Project/evidence/phase1a/A2-build-channel-matrix.json`
`Design/Babel2/Project/evidence/phase1a/A3-release-ignore-args.json`
`Design/Babel2/Project/evidence/phase1a/A4-release-accepted-persisted.json`
`Design/Babel2/Project/evidence/phase1a/A5-stale-generation-fail-closed.json`
`Design/Babel2/Project/evidence/phase1a/A6-launch-trace.jsonl`
`Design/Babel2/Project/evidence/phase1a/A7-unknown-url-noop.json`
`Design/Babel2/Project/evidence/phase1a/A8-babel2-external-action-no-legacy.json`
`Design/Babel2/Project/evidence/phase1a/A9-restoration-validation.json`
`Design/Babel2/Project/evidence/phase1a/A10-restoration-teardown.json`
`Design/Babel2/Project/evidence/phase1a/A11-30-cycle-stress.json`
`Design/Babel2/Project/evidence/phase1a/A12-0.5s.png`、`A12-1.0s.png`、`A12-2.0s.png`
`Design/Babel2/Project/evidence/phase1a/A13-no-blank-html-webkit.json`
`Design/Babel2/Project/evidence/phase1a/A14-babel2-only-regression.json`
`Design/Babel2/Project/evidence/phase1a/A15-owner-and-gate-audit.json`

## 当前缺口矩阵

| 能力 | 自动化证据 | 模拟器证据 | 目标 iPhone 证据 | 当前状态 |
|---|---|---|---|---|
| feature gate/root/re-entry | r8 全量 iOS results 52/52 通过（console XCTest 34 + Swift Testing 18），含 launch trace order/session/uptime/JSON、legacy event derivation/invalidation、restoration、external-action no-op、30-cycle 和 production boundary；targeted Babel2FeatureGate 26/26 | Debug/Release build 与 Release-r10 no-args/cold Genesis startup trace 在 iPhone 17 / iOS 27 Simulator exit 0；UUID `555E35FA-6BFE-45F0-BCFC-0819FFE48CD2`；trace validation 两次各 8 events/final valid | 尚无 A10 reconnect/disconnect、A12 0.5/1/2 秒截图、A13 blank/WebKit runtime、最终 target/resource allowlist、目标 iPhone、性能/视觉和完整 scene 恢复矩阵；test-host 不替代 production standalone | 修复中 / 证据待补 |
| M1 motion/edge pop contract layer | 第 5 轮独立 QA：30 package、8 真实 iOS UIKit runtime、8 Boundary/Shell 通过 | iPhone 17 / iOS 27 Simulator Debug build 通过 | 真机 120Hz 手感、页面 consumer 和 OSLogStore consumer integration 尚无 | completed locally; remote push pending; consumer/device pending |
| Feeds filter/count 与 hero | 尚无覆盖当前实现的测试 | 尚无当前截图 | 尚无 | 未开始 |
| Reader 标题/作者/收缩/进度环 | 尚无覆盖当前实现的测试 | 尚无 | 尚无 | 未开始 |
| Reader 性能/预加载/翻译重影 | 单元测试不足以证明 | 尚无 Instruments/重复进入结果 | 必须测真实文章和翻译源 | 未开始 |
| 正文媒体与内置浏览器手势 | 尚无完整测试 | 尚无 | 尚无 | 未开始 |
| Settings/订阅管理/发现/i18n | 尚无 | 尚无 | 尚无 | 未开始 |
| Light/Dark/Mono runtime AppIcon | 静态设计/资源、独立 QA 和 actool 已绑定 `9fda5c565` | 运行时外观解析尚无当前证据 | Home Screen 未验收 | structural done; runtime pending |
| 全局颜色/loading/toolbar | 尚无源代码 gate 覆盖完整语义 | 尚无 | 尚无 | 未开始 |
| 历史 UI/死代码/技术命名清理 | 尚无 Slice 7 依赖与迁移证据 | 不适用 | 稳定前禁止执行 | 延后 |

## 必须补的验证顺序

1. 由 root 复审当前单轨 diff、A8/A14 新语义、static boundary 和 r8 52 项 iOS/standalone evidence；不要把 r5、warm Genesis 7-event failure 或旧 `phase1a-final` 失败日志当作当前 cold 结果。
2. 生成 A0–A15 对应 trace/manifest 文件，补齐实际 launch-argument、scene 重连/后台恢复、no blank.html/WebKit 和 Gate A exact allowlist 证据；缺证据的行保持 open。
3. 在目标 iPhone 执行冷热启动、真实网络、滚动、边缘手势、状态栏、图片、翻译、浏览器返回、AppIcon 外观、性能和状态恢复矩阵；没有当前 runtime 证据的行保留 open。
4. Phase 1A 完整复审后，由统一导航壳消费 M1，继续按 REQUIREMENTS.md 的 Slice 顺序推进 Feeds/Reader/Settings 等页面；最后才做真机稳定后的技术改名和旧代码清理。

## 环境限制

前序记录指出，某次 `xcodebuild -list` 受到 CoreSimulator 服务断开、用户目录缓存权限和包解析权限影响。该信息只说明验证风险，不证明项目失败或通过；下一次执行必须记录当时实际环境，不能复用旧环境描述。

## Phase 3 验证台账（2026-09-01，Asia/Tokyo）

本节是本轮 Phase 3 的 append-only 证据索引；上方 Phase 2A 记录和数字不改写。持久 evidence gate 入口为 [evidence/phase3/manifest.json](evidence/phase3/manifest.json)；下方 `/private/tmp` 路径仅表示原始临时来源，持久精简 JSON、PNG 和 hashes 均在该目录。所有 package/build/test 命令均显式 unset 以下六个变量：`MERCURY_CLIENT_ID`、`MERCURY_CLIENT_SECRET`、`FEEDLY_CLIENT_ID`、`FEEDLY_CLIENT_SECRET`、`INOREADER_APP_ID`、`INOREADER_APP_KEY`。目标 Simulator 为 iPhone 17 / iOS 27，UDID `555E35FA-6BFE-45F0-BCFC-0819FFE48CD2`。

### 实现范围与语义

本切片的精确实现文件为：

- `Modules/Babel2UI/Sources/Babel2Core/Contracts.swift`
- `Modules/Babel2UI/Sources/Babel2Core/Snapshots.swift`
- `Modules/Babel2UI/Tests/Babel2UITests/Babel2UITests.swift`
- `iOS/Babel2Integration/Babel2LiveDataAdapters.swift`
- `iOS/Babel2/Babel2DataAdapters.swift`
- `iOS/Babel2/Babel2RootViewController.swift`
- `iOS/Babel2/Babel2LibraryViewControllers.swift`
- `iOS/Babel2/Babel2SceneComposition.swift`
- `Tests/NetNewsWire-iOSTests/Babel2FeedReaderTests.swift`
- `NetNewsWire.xcodeproj/project.pbxproj`（仅上述新测试的既有 group/Sources membership）

账户限定 identity 为显式 `FeedSnapshot.ID(accountID, feedID)` 与 `ArticleSnapshot.ID(accountID, feedID, articleID)`；`ArticleSnapshot.url` 可选，缺 canonical URL 但有缓存正文的文章不丢弃，Open Original 隐藏。新增窄的 `feedArticlesSnapshot(for:)`；root 只取 metadata，不加载全库文章、不合并 Today/Unread/Starred SmartFeeds，也不把账户聚合 count 冒充 per-feed count。不可用 root count 隐藏，Feed header 在列表加载后用真实数量；Feed 已加载 snapshot 直接传给 reader。cache/lookup/action 复核三元 identity；Root/Feed/Article 的 await 回写受 cancellation、generation、identity guard 保护。Account、Articles、ArticlesDatabase、SmartFeeds 未改；没有新增 repository/cache/sync engine、WebKit 或后续筛选/Folder 功能。

### Package、targeted 与 full tests

| 项目 | 精确命令（六个 secret env 均以 `env -u` 显式解除） | 结果 | 证据 |
|---|---|---|---|
| Babel2UI package fresh | `env -u MERCURY_CLIENT_ID -u MERCURY_CLIENT_SECRET -u FEEDLY_CLIENT_ID -u FEEDLY_CLIENT_SECRET -u INOREADER_APP_ID -u INOREADER_APP_KEY swift test --package-path Modules/Babel2UI` | exit 0；`31 tests in 5 suites passed` | [package-summary.json](evidence/phase3/package-summary.json)；原始临时 log `/private/tmp/babel2-phase3-package-tests-r2.log` |
| targeted final | `env -u MERCURY_CLIENT_ID -u MERCURY_CLIENT_SECRET -u FEEDLY_CLIENT_ID -u FEEDLY_CLIENT_SECRET -u INOREADER_APP_ID -u INOREADER_APP_KEY xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS -configuration Debug -destination id=555E35FA-6BFE-45F0-BCFC-0819FFE48CD2 -derivedDataPath /private/tmp/babel2-phase3-targeted-feed-r5-dd -resultBundlePath /private/tmp/babel2-phase3-targeted-feed-r5.xcresult "-only-testing:NetNewsWire-iOSTests/Babel2FeedReaderTests" test` | exit 0；4/4 passed，0 failed；四个测试均实际执行 | [test-results-targeted-summary.json](evidence/phase3/test-results-targeted-summary.json)；原始临时 log/xcresult `/private/tmp/babel2-phase3-targeted-feed-r5.*` |
| full Debug iOS | `env -u MERCURY_CLIENT_ID -u MERCURY_CLIENT_SECRET -u FEEDLY_CLIENT_ID -u FEEDLY_CLIENT_SECRET -u INOREADER_APP_ID -u INOREADER_APP_KEY xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS -configuration Debug -destination id=555E35FA-6BFE-45F0-BCFC-0819FFE48CD2 -derivedDataPath /private/tmp/babel2-phase3-full-debug-tests-dd -resultBundlePath /private/tmp/babel2-phase3-full-debug-tests.xcresult test` | exit 0；xcresult logical total 56、passed 56、failed 0、skipped 0；console XCTest 38 + Swift Testing 18 | [test-results-full-summary.json](evidence/phase3/test-results-full-summary.json)；原始临时 log/xcresult `/private/tmp/babel2-phase3-full-debug-tests.*` |

targeted 的失败/无效迭代全部保留：完整精简索引为 [validation-iterations.json](evidence/phase3/validation-iterations.json)；其中 r1 `/private/tmp/babel2-phase3-targeted-feed-r1.log` + `.xcresult` 的 xcodebuild footer 为 success，但 console 明确 `Executed 0 tests` 且未编译新测试，故不计为通过；r2 `/private/tmp/babel2-phase3-targeted-feed-r2.log` + `.xcresult` 是 sandbox/CoreSimulator 与 GitHub DNS 依赖解析失败；r2-escalated `/private/tmp/babel2-phase3-targeted-feed-r2-escalated.log` + `.xcresult` 暴露 Swift 6 isolation 编译错误；r3、r4 `/private/tmp/babel2-phase3-targeted-feed-r3.log`、`/private/tmp/babel2-phase3-targeted-feed-r3.xcresult`、`/private/tmp/babel2-phase3-targeted-feed-r4.log`、`/private/tmp/babel2-phase3-targeted-feed-r4.xcresult` 暴露可选 ObjC delegate 调用编译错误。r5 才是有效 targeted pass。测试覆盖 typed feed/account isolation、snapshot 传递、缓存正文、无 URL 按钮、迟到 mismatch 拒绝和 suspended renderer 取消；renderer continuation 恢复后观测到 `Task.isCancelled == true`，controller 可释放且 late result 不写回 retained text view。

### Simulator builds

| 项目 | 命令/结果 | 证据 |
|---|---|---|
| Debug build r1 | exit 非 0；3 个唯一 `defer` 内 `guard return` Swift 编译错误（xcodebuild footer `(4 failures)`） | [build-results.json](evidence/phase3/build-results.json)；原始临时 log/xcresult `/private/tmp/babel2-phase3-debug-build-r1.*` |
| Debug build r2 | exit 0；中间 build succeeded | [build-results.json](evidence/phase3/build-results.json)；原始临时 log/xcresult `/private/tmp/babel2-phase3-debug-build-r2.*` |
| Debug build r3 | 使用同一 Debug `xcodebuild ... build` 命令，derived data `/private/tmp/babel2-phase3-debug-build-r3-dd`；exit 0，`BUILD SUCCEEDED` | [build-results.json](evidence/phase3/build-results.json)；原始临时 log/xcresult `/private/tmp/babel2-phase3-debug-build-r3.*` |
| Release build r1 | `xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS -configuration Release -destination id=555E35FA-6BFE-45F0-BCFC-0819FFE48CD2 -derivedDataPath /private/tmp/babel2-phase3-release-build-r1-dd -resultBundlePath /private/tmp/babel2-phase3-release-build-r1.xcresult build`；exit 0，`BUILD SUCCEEDED` | [build-results.json](evidence/phase3/build-results.json)；原始临时 log/xcresult `/private/tmp/babel2-phase3-release-build-r1.*` |
| Release build r2（保留） | exit 0，`BUILD SUCCEEDED` | [build-results.json](evidence/phase3/build-results.json)；原始临时 log/xcresult `/private/tmp/babel2-phase3-release-build-r2.*` |

最终 Release r1 app 的精简 hash/metadata 见 [build-results.json](evidence/phase3/build-results.json) 与 [manifest.json](evidence/phase3/manifest.json)；原始 artifact 路径为 `/private/tmp/babel2-phase3-release-build-r1-dd/Build/Products/Release-iphonesimulator/NetNewsWire-iOS.app`，bundle identifier `com.wenbopan.NetNewsWire.iOS`，version `7.1.1`，build `7108`；可执行文件 SHA-256 `6be10d30fbfa7581c667557bf93456d0761801cd965c64a6beb48151954ee286`，bundle 内文件聚合 SHA-256 `4d5ee0759d97de068ba7e3669a045185c15392fa97179e6a152fb921112986a2`。

### Release Simulator runtime

持久化 runtime 入口为 [runtime-summary.json](evidence/phase3/runtime-summary.json)、[runtime-probe.json](evidence/phase3/runtime-probe.json)、[live-trace-summary.json](evidence/phase3/live-trace-summary.json) 和 [cold-launch-final.png](evidence/phase3/cold-launch-final.png)；原始临时证据目录为 `/private/tmp/babel2-phase3-runtime-r1/`。已在目标 Simulator bootstatus 确认为 Booted，使用 Release r1 app 安装（没有 uninstall/erase），terminate 后无参数 cold launch；首次 PID 94949，随后为捕获 live application trace 的 terminate→launch PID 95376。没有显式添加订阅或伪造数据；没有复制原始 install/terminate 日志。

真实数据仅作只读检查：active `OnMyMac` account 目录、10 个 `FeedSettings` 行、SQLite `articles/statuses/search` 各 424 行，`integrity_check` 为 `ok`；脱敏摘要详见 [runtime-probe.json](evidence/phase3/runtime-probe.json)。无参数 root 截图显示 Feeds 页面和 10 个 source/feed rows，持久截图为 `cold-launch-final.png`。当前 Simulator 没有可用 tap/accessibility 驱动，故真实 Feeds→单一 source→article→body/Open Original 操作是 `INTERACTION BLOCKED`；没有 deep-link、预置假数据或将 unit test 冒充 runtime。隐私安全的结构化 live trace 见 [live-trace-summary.json](evidence/phase3/live-trace-summary.json)：记录到 root/content frame 共 7 个事件，但 final result 含既有 `sceneConfigurationSelectionMissing`、`isValid=false`，所以不作为 Phase 1A 完整 runtime trace 通过。

### Open、secret 与交接边界

本 slice 不关闭以下后续事项：cache 先读后验证/无界、同名标题稳定 tie-break、Starred/Unread/All、Folder IA、HTML/WebKit 完整 reader、translation/media/share/long image、sync engine、icon/Figma 视觉润色、旧 storyboard/nib 与 3 个 `.appex` 的 bundle/allowlist、物理 iPhone、完整 scene reconnect/恢复、性能/视觉/手势。主控复审结论限定为“实现代码 P0/P1=0”；不把上述 P2 扩展为本轮架构工作。

最后一次 build/test 和 runtime 完成后，SecretKey hash、`.gyb` hash、byte-identical 与六个环境变量状态已保存于 [secret-status.json](evidence/phase3/secret-status.json)；恢复后没有再运行 build/test。无 commit、无 push。最终 Git/status/ref/diff-check 只读核对在本轮 evidence 与文档修改完成后执行。

## Phase 3B UI driver 验证（2026-09-01，Asia/Tokyo）

本节追加 Phase 3B 的真实 UI driver 证据，不改写上方 Phase 2A/Phase 3 结论。截图隐私与 bundle digest 的 P1 correction 已应用并通过独立只读复核，manifest 状态为 `phase3b_evidence_gate_closed_after_independent_recheck`；该 gate 仅覆盖 Phase3B implementation + automation + persistent evidence，不暗示 Phase1A 或全产品完成，且复核没有重跑 build/test/install/launch。可复核入口为 [evidence/phase3b-ui/manifest.json](evidence/phase3b-ui/manifest.json)、[build-summary.json](evidence/phase3b-ui/build-summary.json)、[runtime-probe.json](evidence/phase3b-ui/runtime-probe.json) 和 [screenshot-inventory.json](evidence/phase3b-ui/screenshot-inventory.json)。

精确改动为独立 `Tests/NetNewsWire-iOSTests/Babel2FeedReaderUITests.swift`、`NetNewsWire.xcodeproj/project.pbxproj` 的 UI target/membership、`NetNewsWire.xcodeproj/xcshareddata/xcschemes/NetNewsWire-iOS UI Driver.xcscheme`、`xcconfig/NetNewsWire_iOSUITests_target.xcconfig`、`iOS/Babel2/Babel2LibraryViewControllers.swift` 的稳定 identifiers、Phase 3 manifest tree hash wording，以及五份文档和本证据目录。sandbox `xcodebuild -list` 权限失败与 escalated 成功结果均保留在 build summary；没有修改旧 scheme/test plan，也没有加入 updateSecrets preaction。

Release build-for-testing r1/r2 均成功。UI r1 实际执行 1 test、失败分类 `UI_SELECTOR_TIMEOUT`（修复前把第二张 table 当作通用层级）；稳定 identifier 后 UI r2 与同一产物重复的 r3 都是实际 1/1 passed。通过项是无参数/无环境启动、root `babel2.feeds.table` 的 10 行、当前顺序的单 source、article table/cached row、正文非空且非 loading/纯标签、Open Original 的 `SafariViewService` foreground、article back→feed back→root 恢复。该 Open Original 断言只证明系统 surface handoff，不证明网络/页面内容。feed.png 现为从 r2 原始附件确定性裁出的 1206×390 顶部 status/header/feed name/count crop，不含文章标题、日期、正文或 URL；BFT r2 与 installed r3 的 bundle-root-relative 245-file tree digest 均为 `64ef2ec5…`。

证据隐私边界：root/back PNG 与 counts 可安全持久化；feed.png 只保留上述 header/count crop；reader/after-browser PNG、hierarchy、文章正文、标题和 URL 仅保留在临时 xcresult，不复制到仓库。测试未使用 deep link、未清数据、未添加订阅。

数据验收不能写成只读：安装/测试序列观察到 `articles/statuses/search` `424→425→426` 与 data-container UUID rotation；r3 使用相同 r2 artifact，前后保持 426。FeedSettings=10、SQLite integrity=`ok`。分类为 `UNEXPECTED_DATA_MUTATION`，原因未证实；不归因 background sync，也不把它标作测试代码必然造成的写入。该切片仍不关闭 Phase 1A、物理 iPhone、旧 storyboard/nib/3 appex allowlist、scene 完整恢复、视觉/性能人工验收，以及 cache 和同名 tie-break P2。

P0/P1 表述仅限“实现代码 P0/P1=0”；本轮 evidence correction 已通过独立复核并关闭 Phase3B evidence gate，完整 Phase 1A 仍需按本文件既有 A0–A15 证据协议复核。Open Original enabled URL → SafariViewService 的通过仍保留；无 URL 行为的语义缺口是后续 P2。旧 storyboard/nib、3 个 `.appex` allowlist、物理 iPhone、scene/perf/visual acceptance、data mutation 原因、cache first-hit/validation/unbounded 和 same-title tie-break 仍 OPEN。SecretKey/.gyb 目标 hash 与六 env unset 见 [evidence/phase3/secret-status.json](evidence/phase3/secret-status.json)。原始 `/private/tmp/babel2-phase3b-ui-*` 路径只作来源索引；无 commit、无 push。

## Feeds/Timeline 卡片打磨 checkpoint（2026-09-05，Asia/Tokyo）

本节记录一次独立于 Phase 2A/M1 主线的工作树打磨：接手时 7 个已跟踪文件（`Modules/Babel2UI/Sources/Babel2Core/Snapshots.swift`、`Tests/NetNewsWire-iOSTests/Babel2FeedReaderTests.swift`、`Tests/NetNewsWire-iOSTests/Babel2FeedReaderUITests.swift`、`iOS/Babel2/Babel2LibraryViewControllers.swift`、`iOS/Babel2/Babel2RootViewController.swift`、`iOS/Babel2/Resources/Babel2Localizable.xcstrings`、`iOS/Babel2Integration/Babel2LiveDataAdapters.swift`）已处于未提交状态，另有 9 张 `Design/Babel2/Project/evidence/stabilize/feeds-v1*.png`/`timeline-v1*.png` 未跟踪截图；本节只对这批已存在的改动做验证、修复回归并提交，不代表新的产品需求或 Slice。

实现内容（供 STATUS 引用）：Feeds 根页支持文件夹层级（`LibraryRow` 区分 folder/feed，可展开折叠）；Unread/All 两档改为列出全部已订阅源（不再按 `count > 0` 过滤，只在视觉上隐藏零计数），Starred 档维持只列有星标的源；Feeds/Feed 页统一切到 `BabelPalette`；默认档从 `.all` 改为 `.unread`；Starred/Unread/All 三个按钮改为 Figma 校准的固定像素坐标（centers `[104, 201, 290.5]`，宽 90pt）；Timeline 卡片新增缩略图异步加载、"英文 → 简体中文"翻译标题副标题行（仅在缓存命中时显示，不触发 AI 请求）、HTML 标签剥离后的摘要、今天用时间/更早用日期的日期格式化、已读/未读标题字重；`ArticleSnapshot` 新增 `translatedTitle`、`FolderSnapshot` 新增 `articleCount`；新增两个仅供 `simctl` 取证使用的环境变量开关 `BABEL2_FEEDS_SCOPE`、`BABEL2_OPEN_FIRST_FEED`。

发现并修复的 2 个真实回归（详见 [LESSONS.md](LESSONS.md) 第 21 条）：

| 回归 | 修复 |
|---|---|
| `layoutScopeControlsIfNeeded()` 在 `scopeStack.bounds.width <= 0` 时整体跳过布局，筛选按钮永远停在初始零尺寸 frame（`testRootHasFeedsTitleAndTwoReachableActions` 断言 `frame.width >= 44` 失败） | 保留 Figma 绝对坐标作为有真实宽度时的分支；新增 `bounds.width <= 0` 的保底分支，用 `max(44, …)` 均分宽度，保证任何宿主下按钮都至少是 44×44 的可点区域 |
| 默认档改为 `.unread` 后，`viewDidAppear` 已预加载 `.unread`；`testStaleScopeResultCannotPublishAfterLatestIntentChanges` 沿用旧写法把 `.unread` 当"尚未加载"的一方来布置竞态，但已加载过的 scope 被再次点击时不会重新发请求，测试永远等不到第二次 `librarySnapshot(for: .unread)`，`waitForLibraryStart(..., after: 2)` 超时 | 把测试里"尚未加载、用来布置延迟竞态"的角色从 `.unread` 换成 `.all`（现在真正未被预加载的一方），其余断言结构保持与改动前一致，只是围绕新默认值把两个角色对调 |

修复前后均用同一组命令重新验证，环境与既有 Phase 2A/3 记录一致：Xcode 27.0 / iOS 27.0 SDK，目标 Simulator 为 iPhone 17，UDID `555E35FA-6BFE-45F0-BCFC-0819FFE48CD2`；`swift test`/`xcodebuild` 均在显式 unset `MERCURY_CLIENT_ID`、`MERCURY_CLIENT_SECRET`、`FEEDLY_CLIENT_ID`、`FEEDLY_CLIENT_SECRET`、`INOREADER_APP_ID`、`INOREADER_APP_KEY`（逐一用 `printenv` 确认本轮 shell 里六项均为 unset）的前提下执行。

| 检查 | 精确命令 | 修复前 | 修复后 |
|---|---|---|---|
| Babel2UI package tests | `env -u MERCURY_CLIENT_ID -u MERCURY_CLIENT_SECRET -u FEEDLY_CLIENT_ID -u FEEDLY_CLIENT_SECRET -u INOREADER_APP_ID -u INOREADER_APP_KEY swift test --package-path Modules/Babel2UI` | exit 0，32/32（未受这两个回归影响） | exit 0，32/32 |
| 全量 Debug iOS tests | `xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS -configuration Debug -destination 'id=555E35FA-6BFE-45F0-BCFC-0819FFE48CD2' -derivedDataPath <dd> -resultBundlePath <xcresult> test` | `** TEST FAILED **`；`xcresulttool get test-results summary` 报 `failedTests:2`、`passedTests:60`、`totalTestCount:62`，失败为 `Babel2FeatureGateTests.testRootHasFeedsTitleAndTwoReachableActions` 与 `Babel2FeedReaderTests.testStaleScopeResultCannotPublishAfterLatestIntentChanges` | `** TEST SUCCEEDED **`；summary 报 `failedTests:0`、`passedTests:62`（console XCTest 44 + Swift Testing 18）|
| Debug build | 同上 test 调用内含编译步骤 | 编译本身成功（回归是运行期断言失败，非编译失败） | 同左，`BUILD SUCCEEDED` |

日志与 result bundle：修复前 `/private/tmp/babel2-feeds-polish-checkpoint.log`、`/private/tmp/babel2-feeds-polish-checkpoint.xcresult`（DerivedData `/private/tmp/babel2-feeds-polish-checkpoint-dd`）；修复后 `/private/tmp/babel2-feeds-polish-checkpoint-r2.log`、`/private/tmp/babel2-feeds-polish-checkpoint-r2.xcresult`（DerivedData `/private/tmp/babel2-feeds-polish-checkpoint-r2-dd`）。这些临时路径不随 commit 保留，仅作本节数字的原始来源索引。

范围与限制：本节证据只覆盖自动化测试与 Debug 编译；`evidence/stabilize/` 下的截图是此前会话在同一 Simulator 上取的静态画面，未附带独立复核，不构成模拟器验收或真机验收证据；REQUIREMENTS 中 "Feed/Timeline header 无空带"、"pFilter 的 selection pill/列表/计数同 progress" 两行要求的是动效同步语义，本次改动只涉及静态几何与数据，**不得据此把这两行标记为完成**。M1（`5db240499806bc4cae9be0b82194c838a32229de`）与 Phase 1A 剩余证据缺口与本节无关，状态维持 HANDOFF.md 既有记录。SecretKey.swift 在本轮 build/test 后 hash 为 `3e2ee2886f5f2f923c93d36116e33b18dd118c0e0adc8c7bd6a8bfc0bffa6e09`（与 2026-09-01 记录的可信快照 `6bd845d7…` 不同，属预期的 scheme pre-action 重写，本轮六个 secret env 全程 unset，未验证是否与可信快照恢复一致，因为该文件被 `.gitignore` 排除、不进入本次 commit）。

提交后回填：本节改动连同上述文档更新一并提交，commit SHA、提交前后 `git status`、以及是否推送见 STATUS.md 对应章节。

## Phase 1A：A1/A2/A3/A7 fresh evidence（2026-09-05，Asia/Tokyo）

环境：Xcode 27.0 / iOS 27.0 SDK；目标 Simulator 为 iPhone 17，UDID `555E35FA-6BFE-45F0-BCFC-0819FFE48CD2`。Git anchor：分支 `codex/reeder-classic-rebuild`，HEAD `7b8ff453ec811c59aad857e5884d4cad14946080`（已推送，`git fetch` 核实过，见 STATUS.md）；本节新增的证据文件即为随后提交的内容，不是未提交工作树。

| 检查 | 精确命令 | 结果 | 证据路径 |
|---|---|---|---|
| Debug 重新编译（当前 commit） | `env -u MERCURY_CLIENT_ID -u MERCURY_CLIENT_SECRET -u FEEDLY_CLIENT_ID -u FEEDLY_CLIENT_SECRET -u INOREADER_APP_ID -u INOREADER_APP_KEY xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS -configuration Debug -destination 'id=555E35FA-6BFE-45F0-BCFC-0819FFE48CD2' build` | exit 0，`BUILD SUCCEEDED`；executable SHA-256 `f937ceb39b8579565a7efa17e0044099046ce29e36ab640e34a89c6a7f4f642a` | `/private/tmp/babel2-phase1a-a123a7/debug-build.log`（临时来源，不进仓库） |
| Release 重新编译（当前 commit） | 同上，`-configuration Release` | exit 0，`BUILD SUCCEEDED`；executable SHA-256 `69600fa7f493020ab902aae8bb594496318e5f458a723a07bd408d6c10a1aed8` | `/private/tmp/babel2-phase1a-a123a7/release-build.log` |
| A2/A3 启动参数矩阵 | 对 Debug/Release 各 5 组参数（无参数、`-GenesisV2`、`-Babel2`、`-UnknownFlagXYZ`、`-Babel2 -GenesisV2`）依次 `xcrun simctl uninstall` → `install` → `launch <bundle> [args]` → `xcrun simctl spawn ... log show --info --style compact --predicate 'process == "NetNewsWire-iOS"'`，解析 `Babel2 launch trace event/result` 结构化 JSON 行 | 10/10 次 `generation=babel-2`，legacy 计数全为 0；9/10 首次即拿到 8/8 事件 `isValid=true`；`debug-noargs` 首次（全新 install 后第一次冷启动）3 秒等待只拿到 6/8，延长到 8 秒重跑拿到 8/8（两次结果均保留） | [A2-build-channel-matrix.json](evidence/phase1a/A2-build-channel-matrix.json)、[A3-release-ignore-args.json](evidence/phase1a/A3-release-ignore-args.json) |
| A7 未识别 URL no-op | `SIMCTL_CHILD_BABEL2_OPEN_FIRST_FEED=1 xcrun simctl launch ...`（无 launch arguments）建立 feed 内文章列表路由 → 截图 → `xcrun simctl openurl ... "nnw://unrecognized-action-xyz"` → 等 2 秒 → 再截图 → `log show --last 30s --info` | 截图前后 SHA-256 完全一致（`8682e484…`）；期间日志只多一行 `Babel2 external action ignored unknown external action`；launch trace 无新事件、session/PID 不变 | [A7-unknown-url-noop.json](evidence/phase1a/A7-unknown-url-noop.json)，截图裁剪版 `A7-before-daring-fireball-header-crop.png`/`A7-after-unknown-url-header-crop.png` |
| A1 静态引用 | 对 `iOS/AppDelegate.swift`、`iOS/Babel2/Babel2FeatureGate.swift` 做逐行引用核对（非自动化命令，人工/grep 核对文件行号与内容） | 未发现任何读取 `CommandLine`/`ProcessInfo.processInfo.arguments`/`UserDefaults` 来决定 generation 的代码路径；未发现旧生命周期/storyboard/coordinator/WebView 类型出现在 `startBabel2LifecycleIfNeeded`/`bootstrapBabel2RuntimeIfNeeded`/`configurationForConnecting` 里 | [A1-bootstrap-isolation.json](evidence/phase1a/A1-bootstrap-isolation.json) |

限制：以上全部在 Simulator 完成，不替代目标物理 iPhone；A4/A5（persisted generation/restoration）、A6 剩余子项、A8–A15 与视觉/性能验收均不在本轮范围内。SIMCTL_CHILD_BABEL2_OPEN_FIRST_FEED 与 BABEL2_FEEDS_SCOPE 是仅供取证使用的环境变量开关，不是 production selector，与 A1–A3 检查的 launch-argument 边界无关，已在证据文件里注明。四行证据均标记"通过（需 root 复审）"，尚未经过独立 root 复审终审。

## Phase 1A：A8/A10/A13 fresh evidence（2026-09-05，Asia/Tokyo，同日第二批）

同一 commit `fb0a43f14`（已推送）、同一 Simulator 环境，延续上一批的方法继续跑。

| 检查 | 精确命令 | 结果 | 证据路径 |
|---|---|---|---|
| A13 | 静态 grep（`blank\.html`、`WKWebView`、`recordLegacyWebViewBootstrap` 等）+ 复用 A2 的 10 次 trace 的 `legacyWebViewBootstrapCalls` 字段 | 静态：blank.html 只在旧 `ArticleRenderer.swift` 出现；Babel2 当前展示路径零 WKWebView 引用。Runtime：10/10 次 `legacyWebViewBootstrapCalls=0` | [A13-no-blank-html-webkit.json](evidence/phase1a/A13-no-blank-html-webkit.json) |
| A8（URL 子集） | 冷启动 + `SIMCTL_CHILD_BABEL2_OPEN_FIRST_FEED=1` 建立 route → 截图 → 依次 `xcrun simctl openurl` 四个已注册 URL（`nnw://showunread`/`showtoday`/`showstarred`、`feed:https://daringfireball.net/feeds/main`）→ 再截图 → `log show --last 30s --info` | 4/4 被正确识别（日志打出对应 action 名）；期间零新增 launch trace 事件；前后截图 SHA-256 完全一致（`6155638f…`） | [A8-babel2-external-action-no-legacy.json](evidence/phase1a/A8-babel2-external-action-no-legacy.json) |
| A10（后台/前台子场景） | 同一 PID 上：`xcrun simctl launch <udid> com.apple.Preferences` 挤到后台 → 截图 → `xcrun simctl launch <udid> <bundle>` 再拉回前台 → 截图 → 两段各 `log show --last 15s --info` | 全程 PID 60005 不变；`Application processing resumed.` 真实触发；零新增 root/legacy 事件；前后截图内容除系统临时"◄ Settings"提示条外完全一致 | [A10-restoration-teardown.json](evidence/phase1a/A10-restoration-teardown.json) |
| A10（disconnect 尝试，未成功复现） | `xcrun simctl terminate <udid> <bundle>` → `log show --last 10s --info` | 只看到进程被硬杀的系统/网络日志，没有 `sceneDidDisconnect.babel2` teardown 行——确认 `simctl terminate` 不经过 UIKit scene 生命周期，不能替代真实 App 切换器划掉的场景 | 同上，"part_2" 字段 |

限制：A8 的 shortcut item / notification response 两条、A10 的真实 scene disconnect 和真机 30-cycle，`xcrun simctl` 均无法脚本化触发，仍待你配合一次交互操作或改用真机。A13 标记"通过（需 root 复审）"；A8/A10 标记"实现进行中/证据待补"（已验证的子场景视为通过）。
