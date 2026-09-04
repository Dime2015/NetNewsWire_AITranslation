# Babel 2.0 决策日志

记录格式：日期、状态、选择、理由、被否决方案、重新评估触发。历史决定只有在最新用户反馈或已批准合同明确覆盖后才失效。

## ADR-001：在现有 iOS target 内用 feature gate，暂不创建第二个正式 App target

- 日期：2026-08-31
- 状态：已选择，production legacy fallback 部分已由 ADR-012 覆盖，待 Slice 0 运行时验证。
- 选择：在现有 App target 内建立明确的 Babel 2.0 feature gate、独立 root composition 和 route adapters；production lifecycle 不提供可运行的 legacy fallback，旧实现仅保留为磁盘审计/低层 fixture 材料。
- 理由：可以复用账户、文章、同步、缓存和持久化服务，同时避免复制 bundle、extension、scene、entitlement、App Group 和状态恢复配置；合同也要求 first implementation slice 是隔离导航层和 adapters，而不是第二个正式 App target。
- 被否决方案：现在复制一个完整的第二 App target。它隔离更强，但会扩大工程接线和数据 identity 风险，且当前没有可安全复制的 target 模板。
- 重新评估触发：Babel 2.0 已通过目标 iPhone 的稳定性、数据迁移和状态恢复验收，且产品明确需要第二个可独立安装的 bundle；届时另立迁移项目并取得授权。任何兼容 identity 迁移仍须经过唯一 `LegacyIdentityCompatibility` 边界；该边界当前尚未实现。

## ADR-002：根代理只思考和指挥，Luna 执行实现

- 日期：2026-08-31
- 状态：已选择。
- 选择：根代理负责分析、范围、验证标准、拆分和复审；Luna 代理负责实际代码、资源、测试、构建和提交。
- 理由：保持职责边界清楚，让实现能够被独立审查；每项工作仍必须遵守当前 Slice 的文件范围和验证 gate。
- 被否决方案：根代理直接在共享工作树中边分析边修改代码。这样容易与并行 Slice 冲突，也会让“谁执行、谁验证”不可追踪。
- 重新评估触发：并行代理不可用，或用户明确改变执行授权；即使改变，也要先更新本决策和交接协议。

## ADR-003：路线 A，用户可见和新增内容先统一 Babel 命名，存量技术改名延后

- 日期：2026-08-31
- 状态：已选择；技术改名尚未开始。
- 选择：新产品表面、代码、资源、测试、日志、路由和文档采用 Babel/Babel2 命名；暂存的系统 identity 只经唯一 `LegacyIdentityCompatibility` 边界；稳定可用并完成真机验收后，再分阶段迁移存量类型、target、工程路径和内部映射。该边界属于 PRODUCT-CONTRACT/A15/Phase6 requirement，当前没有实现或空 facade。
- 理由：用户要的新 App 统一叫 Babel，同时全局替换 bundle、App Group、Keychain、Core Data 或外部仓库身份会造成数据断裂和回滚困难。
- 被否决方案：现在一次性删除或替换所有存量技术名称。风险大，且会把 UI 重建与不可逆 identity 迁移混在一起。
- 重新评估触发：Babel 2.0 通过完整冷/热启动、数据、同步、Reader、浏览器、翻译和状态恢复真机矩阵；随后建立备份、schema/version、回滚和断裂检测。

## ADR-004：AppIcon 使用 Light/Dark/Mono 三态，当前以俯拍木桌杂志 B 为方向

- 日期：2026-08-31
- 状态：设计/静态资产已完成并提交；runtime pending。
- 选择：保留俯拍木桌上由真实杂志排列成大写 B 的构图。Dark 使用深色木桌方向；Light 使用明亮木桌、每本封面独立偏暗但不套统一黑色蒙版；Mono 从获选构图派生。用户先选定 Dark，并明确授权“生成好直接作为 Babel 2.0 图标”；早期“烧焦/全局黑蒙版”Light 被否决，随后按亮木桌、独立暗色封面、干净页边重生成当前 Final。最终三态设计/静态资产已在 `9fda5c565` 提交，并完成逐图检查、独立 QA、actool 和小尺寸结构检查。Round 4 草稿不构成回退。Dark 可复现 master 是仓库内 `Design/Babel2/Icon Concepts/Final/Babel2AppIcon-Dark.png`，临时用户附件仅作 provenance。
- 理由：保留 B 与杂志的识别，同时让三种系统外观有明确语义；用户最新反馈明确否决“像被火烧过”或统一黑蒙版的 Light 处理，当前 Final 满足后续亮桌面和独立暗色封面的约束。
- 被否决方案：玻璃字母、平面字标、杂志海中间凸印、统一黑色滤镜，以及早期“烧焦/全局蒙版”Light；这些草稿不作为当前母版或回退目标。
- 重新评估触发：runtime appearance 接入、模拟器资源解析或目标 iPhone Home Screen 检查发现问题，或用户提出新的具体视觉反馈；届时只更新受影响的派生资产和证据，不把早期被否决的 Light 草稿或 Round 4 草稿恢复为母版。

## ADR-005：Feed hero 自身 full-bleed 延伸到状态栏和动态岛

- 日期：2026-08-31
- 状态：合同已记录，代码和设备未验收。
- 选择：expanded hero 图像/背景覆盖安全区到状态栏/动态岛，使用自身不透明底图和 scrim；收缩到 compact/list 后使用完全不透明 chrome，并用同一连续 motion surface 过渡。
- 理由：用户要求整体感，同时禁止状态栏下透日期、文章或 WebView；连续 surface 可避免滚动时跳变和重影。
- 被否决方案：透明状态栏、系统 blur 叠加、把 hero 当独立卡片或把 expanded/compact 做成两个离散页面。
- 重新评估触发：Figma 几何或目标设备 safe-area 测量证明当前高度/对比不足；必须以测量更新 token，不凭感觉改常数。

## ADR-006：普通分享在顶部，生成长图只在底栏 tap

- 日期：2026-08-31
- 状态：合同已记录，代码和设备未验收。
- 选择：文章页原顶部长图位置恢复普通系统分享；生成长图移动到底栏，只有点击触发，不使用长按分享。
- 理由：两个动作语义不同，避免一个控件同时承担分享和长图；底栏动作位置稳定、可发现。
- 被否决方案：顶部按钮长按分享/短按生成长图，或在底栏复用同一个多义控件。
- 重新评估触发：可访问性测试、长图生成失败恢复或目标设备命中率显示槽位需要调整；不得悄悄恢复长按语义。

## ADR-007：横向正文图片 100vw、直角；文字和 caption 保持 inset

- 日期：2026-08-31
- 状态：合同已记录，代码和设备未验收。
- 选择：横向正文图贴齐屏幕两端且不加圆角；正文文字、caption 和 portrait/inline 媒体保持阅读 inset，wrapper 不得重新加圆角。
- 理由：这是用户明确要求的高级感和版式层次，且避免把列表缩略图的圆角规格误套到正文媒体。
- 被否决方案：所有图片统一 inset、统一圆角，或让 `figure`/link/wrapper 再次包圆角。
- 重新评估触发：真实文章中图片方向、safe area、WebView viewport 或 caption 可读性出现问题；按媒体类型修正，不回到全局圆角。

## ADR-008：neutral 是默认强调；主题 accent 只控制开关和阅读进度环

- 日期：2026-08-31
- 状态：合同已记录，代码和设备未验收。
- 选择：普通 icon、star、selection、阅读模式、链接使用 neutral gray/black；链接用加粗与中性下划线；用户主题色只进入 Settings switch 和 Reader progress ring。
- 理由：用户明确否决全局绿色，要求颜色语义收窄且整个 App 协调。
- 被否决方案：把主题色扩散到所有选中态、链接、star、阅读模式或 toolbar icon。
- 重新评估触发：用户新增明确语义或无障碍对比测试要求；任何扩散都要更新合同、token 和验收矩阵。

## ADR-009：单一 loading owner；同步箭头与文章加载分离

- 日期：2026-08-31
- 状态：合同已记录，代码和设备未验收。
- 选择：sync arrow 只在真实同步期间出现、旋转并在完成后隐藏；文章/翻译/普通加载使用 skeleton 或 passive state；同一表面不得同时显示系统菊花和同步箭头。
- 理由：用户观察到两个重复控件和文章中间加载页；单一 owner 才能避免重复、永恒 spinner 和布局跳变。
- 被否决方案：全局常驻同步箭头、每个 controller 自己加 spinner，或让系统菊花和自绘箭头同时出现。
- 重新评估触发：网络/解析/翻译失败需要恢复动作，或真实同步阶段需要额外可读状态；必须扩展状态模型，不新增第二个无主 loading 控件。

## ADR-010：稳定后再清理历史 UI、死代码和技术名称

- 日期：2026-08-31
- 状态：已选择；清理尚未开始。
- 选择：先完成 Babel 2.0 可运行、稳定和真机验收，再按依赖图、备份、迁移版本、回滚和用户授权分批清理历史 UI/死代码与存量技术名称。
- 理由：当前首要风险是运行时稳定、数据连续性和视觉正确性；过早删除会把可回退路径、兼容 identity 和诊断证据一起破坏。
- 被否决方案：在新 UI 尚未稳定时全量删除历史代码和全局替换名称。
- 重新评估触发：Slice 7 完成、依赖搜索和行为回归通过，且每批删除有明确 owner、回滚点和用户批准；外部 identity 仍需单独授权。

## ADR-011：M1 以独立 QA 通过的本地提交作为 contract layer 基线，推送单独授权

- 日期：2026-08-31
- 状态：contract layer completed；local committed；remote push pending；页面 consumer 与设备手感未完成。
- 选择：将 `5db240499806bc4cae9be0b82194c838a32229de`（`Babel 2.0 M1: add interruptible motion foundation`）作为 M1 本地基线。第 5 轮独立 QA 在 iPhone 17 / iOS 27 Simulator 通过后，先等待用户对该具体 commit 的推送授权；推送前后分别核对本地 HEAD、remote-tracking 和 hosted remote。
- 理由：独立 QA 已证明 M1 contract layer 的当前实现，而远端推送是外部状态变更，必须与本地提交和页面 consumer/真机验收分开记录；这样不会把本地通过错误宣传为远端已发布或 App 已完成。
- 被否决方案：直接把本地 commit 写成已推送，或在页面 consumer、120Hz 真机手感和 OSLogStore consumer integration 未完成前把 M1 宣传为 Babel 2.0 完成。
- 重新评估触发：获得明确推送授权并成功核对远端，或页面 consumer/真机验证发现 contract layer 需要回滚或修订；任何新提交都要更新 STATUS、VALIDATION 和 HANDOFF 的 SHA/证据。

## ADR-012：Phase 2A 生产生命周期固定为单一 Babel2 root

- 日期：2026-09-01
- 状态：已选择；Phase2A correction fresh Debug/Release build、package 和 iOS tests 通过；完整 Phase1A runtime、真机和视觉验收仍待完成。
- 选择：AppDelegate、SceneDelegate 和 Babel2 scene lifecycle 只创建并维护 Babel2 root。URL、shortcut、notification、NSUserActivity、restoration、旧启动参数和旧 gate 不得选择或切换到 legacy generation；外部动作在 Babel2 root 上交给现有最小 handler 或安全 no-op。旧实现保留在磁盘上，仅作为历史/低层测试材料，不进入 production lifecycle。
- 理由：此前根因不是 Babel2 root 缺少局部页面，而是入口仍保留 legacy bootstrap、scene coordinator/storyboard 和 external-action fallback 的可达路径；这些路径会在不同启动输入下重新实例化旧 generation。单一 root 能在不改 bundle identity、App Group、Core Data、CloudKit、扩展或 target membership 的前提下切断该分叉。
- 被否决方案：静态返回 Babel2 但继续保留可执行的旧 gate/启动参数选择器、把外部动作 fallback 到 legacy、或仅把 scene storyboard 置空而不移除 root/coordinator/WebView bootstrap。这些方案无法证明 production legacy side effect 为零。
- 证据：`Babel2BoundaryTests.productionLifecycleHasNoLegacyRootOrFallbackRoute` 与唯一 parser boundary 对 AppDelegate、SceneDelegate、Babel2Integration、独立 external-action parser、Info.plist 和 trace-only diagnostic allowlist 的断言通过；fresh package tests 为 30 个 Swift Testing tests，Debug iOS tests 为 XCTest 27 + Swift Testing 18（总计 45，0 failures），Debug/Release build 均通过。legacy counters 由事件流派生，WebView probe 在 content first frame 后关闭，测试 fixture 使用隔离 recorder sink。真实启动 trace、A0/A1/A6/A8/A12/A13 runtime、最终 bundle allowlist、目标 iPhone、完整 A0–A15 与视觉证据不在本批结论内；当前 bundle 仍含 Main.storyboardc、HTML-JS、8 themes、3 extensions。
- 重新评估触发：runtime trace 或真机验收发现 Babel2 root 未覆盖某个输入，或产品明确批准 legacy 兼容迁移；届时先更新合同、路由 owner 和回滚证据，不恢复隐式 fallback。

## ADR-013：Phase 2A trace 以真实事件流和单一 recorder 为证据源

- 日期：2026-09-01
- 状态：已选择；Phase2A correction 实现与自动化验证通过，production runtime evidence 仍待补。
- 选择：AppDelegate 在 process-entry/gate 边界拥有唯一 `Babel2LaunchTraceRecorder`；RootSplit、SceneCoordinator、BabelShell、WebViewProvider 和 PreloadedWebView 只通过已有初始化边界发出窄 probe。legacy counters、validity 和 JSON 均从同一事件流推导，任一旧事件、错序、session/uptime/sequence/configuration/storyboard 缺证据都 fail-closed；WebView/blank probe 只在 Babel2 content first frame 前接收。
- 理由：硬编码 `false/0` 没有事件源，既不能证明旧路径不可达，也不能区分 clean runtime 与测试主动绕过；第二套 recorder/lifecycle 又会产生无法关联的 session。单一 recorder 同时绑定 origin/session/build/event sequence/uptime，才能把静态不可达断言和动态观测分开。
- 被否决方案：用硬编码零冒充 clean runtime、让 `Babel2FeatureGateTests` 构造旧 coordinator fixture、用 XCTest bundle/launch arguments/调用栈 suppression 排除测试事件、以 content first frame 后的 WebView activity 反推启动失败，或用 OSLog/dyld/bundle 静态 absence 单独替代动态事件。
- 证据：fresh Debug iOS tests 45/45 通过，其中覆盖 legacy event injection、counter/source/session/JSON、order/uptime/config fail-closed、WebView frame cutoff、BabelShell isolated sink、single-generation API 与 parser uniqueness；r5 的 fixture-order/token-scan 失败保留为历史证据。Debug/Release build 成功，但目标 iPhone、A0/A1/A6/A8/A12/A13 runtime trace 与最终 bundle allowlist 仍 pending；当前 bundle 仍含 Main.storyboardc、HTML-JS、8 themes、3 extensions。
- 重新评估触发：保存真实 AppDelegate/SceneDelegate launch JSONL、完成 scene reconnect/background/foreground/teardown 和目标设备证据，并将 bundle 逐项 allowlist 后，再决定是否关闭 A0/A1/A6/A8/A12/A13；`LegacyIdentityCompatibility` 仍按 ADR-003 留待 PRODUCT-CONTRACT/A15/Phase6。
