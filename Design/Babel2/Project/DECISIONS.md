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

## ADR-015：pFilter 保留现有 `UIViewPropertyAnimator` 方案，只补测试与 typed signpost，不迁移到 `Babel2MotionDriver` 类

- 日期：2026-09-08
- 状态：已选择；实现与自动化测试完成，真机/模拟器视觉验收待补。
- 选择：`Babel2RootViewController` 的 Starred/Unread/All 切换继续使用既有的 `UIViewPropertyAnimator` + 手工中断采样（`interruptScopeTransition()` 读取 `layer.presentation()`）机制，不改写成调用 `Babel2UI` 的 `Babel2MotionDriver` 类。新增的是：① 补齐此前完全没有的行为测试（单次切换、途中被打断并二次改道到第三个目标、计数与选中态在这些场景下的正确性）；② 直接调用 `Babel2Core` 已有但从未被使用过的 `Babel2.Library.Filter` typed signpost（`MotionLibraryFilterPayload`），在过渡开始（`.begin`，pFilter=0）、真正打断时（`.event`，采样 `animator.fractionComplete`）、真正结算完成（`.end`，pFilter=1）三个时机各记一次；③ 给 `MotionInteractionID` 补了一个此前遗漏的 `.libraryFilter` case（这个类型早就有 `MotionLibraryFilterPayload.token` 字段要用它，但枚举里从没有对应 case）；④ 顺带修了一个独立发现的真实 bug——底部三档按钮此前用的是写死的 402pt 参考画布绝对像素坐标，真实设备宽度不等于 402pt 时会整体偏左，改成按比例乘真实宽度。
- 理由：现有 `UIViewPropertyAnimator` 机制在结构上已经满足 MOTION-CONTRACT.md §4A 和 §5 的要求（"one interruptible property animator or equivalent time-based driver whose start value is read from the actual presentation state"——这句话本身就没有强制要求用某个特定类）；`Babel2MotionDriver`+`GesturePolicy` 这套引擎主要是为"手指连续拖拽"类手势（导航返回、Reader→Browser、翻页）设计的，pFilter 是"点击触发、时长固定"的过渡，语义上更贴近现成机制而不是拖拽状态机；MOTION-CONTRACT.md 第 3 节的 unified ownership 列表本身也没有给 Library filter 指定一个专门的 owner 类型。把一段已经正确、且从未被测试覆盖过的过渡逻辑推倒重写去套用一个不是为它设计的引擎，风险（可能引入真实回归）明显大于收益（只是"用了同一个类"这一点一致性）。
- 被否决方案：把 `startScopeTransition`/`interruptScopeTransition` 整个改写成调用 `Babel2MotionDriver.begin/interrupt/finish`，让驱动器接管 `UIViewPropertyAnimator` 的创建与中断。这样能自动获得驱动器自带的通用 signpost（begin/track/settle/interrupt），但需要把渲染逻辑从"一次性动画块直接读取闭包捕获的 target/displayedScope"重构成"纯粹从 0-1 进度值反推所有视觉状态"，改动面明显大于当前这批（新增测试 + 补 typed signpost + 修一个独立 bug）。
- 重新评估触发：如果之后决定"pFilter 也需要连续跟手（比如允许横向拖拽预览下一个 filter 而不是纯点击）"，或者产品明确要求所有 motion surface 统一走同一个引擎类以便复用 Instruments 关联，届时重新评估是否迁移到 `Babel2MotionDriver`。

## ADR-014：M1 的第一个页面消费者只接管交互式边缘手势，程序化 pop 保持系统默认动画

- 日期：2026-09-05
- 状态：已选择；实现与自动化测试完成；2026-09-08 用户真机确认核心手感（跟手、中途取消可正确弹回）；深栈/根路由/旋转/非边缘误触发/120Hz 帧率与 OSLogStore consumer integration 验收待补。
- 选择：`Babel2NavigationPopMotion` 只在"手指从左边缘拖拽"这一条路径上接管 `UINavigationControllerDelegate` 的转场方法（`animationControllerFor`/`interactionControllerFor` 仅在 `isInteractivelyPopping == true` 时返回非 nil）；点击返回按钮触发的 `popBabel2(animated:)` 完全不经过这层，继续用系统默认的 push/pop 动画。系统自带的 `interactivePopGestureRecognizer` 被禁用（`isEnabled = false`），避免它和新装的 `UIScreenEdgePanGestureRecognizer` 同时响应同一个边缘手势。
- 理由：这是 M1 的第一次真实页面接入，风险面要尽量小——把改动限制在"仅替换交互式边缘手势的转场"，能保证除了边缘滑动这一条路径之外，App 里所有其它导航行为（点按钮返回、push 新页面、Settings/AddSubscription 弹出）完全不变，不需要重新验证整个导航系统。等真机确认这条路径手感没问题、且以后要给"程序化 pop 也用同一套动效"时，可以再单独评估。
- 被否决方案：直接整体替换 `UINavigationControllerDelegate`（让所有 pop，不管是不是手势触发，都走自定义转场）——这样风险面更大，一次改动同时影响手势和按钮两条路径，出问题时也更难定位是手势逻辑的问题还是转场逻辑的问题。
- 证据：`iOS/Babel2/Babel2NavigationPopMotion.swift`（新文件）+ `Babel2NavigationController.swift` 的 3 行改动；12 个新单元测试（`Babel2FeatureGateTests.swift`）覆盖手势状态机、finish/cancel 投影判定、强制取消、装卸干净，12/12 通过；全量 Debug iOS suite 77/77 通过。已知边界：无窗口的测试环境下 UIKit 不调用转场代理（见 LESSONS.md 第 27 条），所以真实 `transitionContext` 生命周期和视觉观感没有被自动化覆盖，需要真机/模拟器交互确认。
- 重新评估触发：真机测试发现边缘手势和系统预期冲突（例如与 App 切换器的边缘手势区域重叠），或者产品决定程序化 pop 也需要同一套连续动效；届时重新设计转场代理的接管范围。

## ADR-016：Slice 5 拆分顺序、长图位置与「下一篇」交互

- 日期：2026-09-25
- 状态：已选择（用户回复“都按建议来”）。
- 选择：① Slice 5 按 翻译 → 阅读模式 → 内置浏览器与右缘左滑 → 下一篇 → 长图 顺序分步，每步停下等真机验收；翻译动手前单独出书面方案。② 长图位置：Reader 底栏改为 已读 / 星标 / 下一篇 / **长图** / 翻译（长图只在底栏、点按触发）；「阅读模式」移入顶栏正中（402pt 画布 x=201，Figma 预留的 More 槽位）新加的「更多」菜单。③ 下一篇：先只做**点底栏按钮翻到下一篇**，原地换内容、不 push 新 Reader；「到底继续上拉跟手翻篇」手势继续封存（沿用 Babel 1.x 用户决定），以后想要再加。
- 理由：翻译是产品核心价值且最难，先做；阅读模式与翻译相互依赖（译文应能作用在全文上），紧随其后；长图依赖翻译要搭的页面宿主桥，放最后。底栏五格与“长图 tap-only 在底栏”的新规则冲突，用顶栏空槽安置阅读模式是改动最小、两条规则都满足的方案。
- 与合同的偏离：MOTION-CONTRACT §8 要求三面板纵向跟手 pager；本决定暂不做手势，只做按钮触发的原地换文，仍遵守“不为下一篇 push 新 Reader”。
- 重新评估触发：用户要求上拉翻篇手势，或真机上发现按钮翻篇效率不足。

## ADR-017：Reader 翻译复用既有引擎，阅读页经集成层取回原始 Article 对象

- 日期：2026-09-25
- 状态：已选择；实现与自动化完成，真机待验收。
- 选择：Babel2 阅读页实现 `NNWArticlePageHost`，直接驱动未修改的 `TranslationController`。引擎要的原始 `Article` 由 `Babel2LiveArticleLookup`（唯一可触达账户单例的集成文件内）按快照编号取回，以不透明 `AnyObject?` 传入阅读页，只在网页控件专用目录的宿主扩展里还原成 `Article`。
- 偏离：Babel2 原则是“页面只持有值快照、不持有 Account/Article 对象”（Babel2LiveDataAdapters 头注释）。此处为翻译引擎的缓存键、标题、原文链接破例，范围限定在阅读页生命周期内、只读。
- 被否决：重写一套 Babel2 翻译编排（丢失已验收的流式、骨架、断点续翻、对冲与缓存兼容，且重复实现风险高）；把 Article 字段加进 Babel2Core 快照并改写引擎（要改已稳定的共享翻译代码）。
- 重新评估触发：翻译引擎需要重构、或 Babel2 要彻底移除对 Articles 模块的依赖时。

## ADR-018：阅读页按 Figma 04A/04B/04D3 对齐（2026-09-25，用户“都按建议来”）

- 背景：本会话前期无 Figma 连接，阅读页按 BATCH-01-SPEC 文字数值与系统图标实现，与设计稿差距大；接上 Figma 后逐项对照（节点 22:38、117:263、143:444、43:19、18:15、21:5、143:73）。
- 选择：① 所有阅读页图标换为设计稿矢量资产（24pt）；正文色、标题行高/字距、日期、引用块、分隔线等照稿。② 翻译按钮改为 Figma「Translation Toggle」文字开关：原文「原 翻译」、翻译中「译 生成中」、已译「译 原文」、失败「原 重试」；取消 1.x 的缓存实心点/未完成空心圈角标（缓存功能保留，只是不显示提示）。③ 返回按钮用 ✕（Figma Close）。④ 顶栏不放「标签」（无此功能）；「打开原文」移入顶栏正中「•••更多」菜单（本步建立菜单，阅读模式下一步加入）。⑤ **推翻 Slice 4 第 3 步的方案 A**：栏隐藏时顶部按钮行整行收起，紧凑栏随之上移贴到状态栏下（Figma 04D3 实际画法）；MOTION-CONTRACT §10“隐藏栏不得移动固定标识”一句与设计稿矛盾，以设计稿为准并待修订合同文字。⑥ 署名两行：作者 / 订阅源；为此在 Babel2Core `ArticleSnapshot` 增加可选 `author` 字段（集成层映射）。
- 顶栏右上仍为普通系统分享（合同最新决定优先于 Figma 的“分享长图”图标）；底栏第 4 格本步仍按 Figma 显示阅读模式图标，按 ADR-016 在后续步骤改为长图。

## ADR-019：阅读模式（全文）交互（2026-09-25，用户“都按建议来”）

- 入口：顶栏 ••• 菜单「阅读模式」（带勾表示开着），无原文地址时不显示；底栏第 4 格改为「长图」占位（ADR-016）。
- 提取：原样复用 `ReaderViewExtractor`（本地 Readability，20s 超时），经 `Babel2FullTextFetcher` 包成可取消的 async 调用。
- 加载表现：署名下方一行浅灰状态字「正在获取全文…」，正文照常可读；失败显示「无法获取全文」3 秒后消失，正文不变（不用系统转圈、不挡内容）。
- 记忆：按单篇文章记在既有 `ArticleReadingStateStore`（与译文记忆同一键 `accountID|articleID`），再次打开自动取全文；只在成功时记为开。
- 切换阅读模式后回到顶部（沿用 1.x 用户决定：两版正文无法按位置对应）。
- 限制：同一篇的摘要版与全文版译文共用一个缓存条目，来回切换时另一版需重新翻译。按订阅源「总是阅读模式」开关留待 Slice 6 设置页。

## ADR-020：阅读模式回到底栏第 4 格 + 按订阅源「总是用阅读模式」（2026-09-25，用户“A 和 B 都做”）

- 背景：阅读模式放在 ••• 菜单每篇要点 2 下，对常用阅读模式的源成本过高（用户反馈）。另发现数据库既有按订阅源开关 `Feed.readerViewAlwaysEnabled`（1.x 订阅源设置页使用），新版阅读页此前未读取——属遗漏。
- 选择：A）••• 菜单新增「此订阅源总是用阅读模式」（勾选态），经集成层 `Babel2LiveFeedReaderSetting` 读写该公开属性；开着的源打开文章即取全文，且**不**写入单篇记忆（关掉源开关后不留残余）；1.x 里设过的直接生效。B）底栏第 4 格恢复为 Figma 原样的「阅读模式」按钮（开时用既有加粗图标 `BabelReaderReadingModeActive`、主墨色），「生成长图」移入 ••• 菜单（第 5 步前灰色）。
- 推翻：ADR-016 中「长图只在底栏、阅读模式进 ••• 菜单」；产品合同“长图入口只在底栏”一句随之失效，待合同修订。
- 手动在全文状态点底栏按钮关闭：仅本篇回到原正文并清除本篇记忆；若订阅源开关仍开，下次打开该源文章仍自动全文。

## ADR-021：内置浏览器与右缘左滑进入（2026-09-25，用户“都按建议来”）

- 进入：正文右边缘起手往左滑，阅读页与浏览器按 MOTION-CONTRACT §7 公式同步跟手（readerX = −W·p，browserX = W·(1−p)）；松手按「进度 + 速度×0.15 s」投影，> 0.5 补完，否则弹回并丢弃浏览器、阅读页原样。起手时先建浏览器页面并在后台开始加载（网络不参与跟手）。实现为 `Babel2ReaderBrowserMotion`：跟手期间浏览器视图叠在导航容器上，补完后以无动画方式推入导航栈，返回沿用统一左边缘返回手势。右边缘宽度用系统边缘手势默认值（合同 24–32pt 可调，未单独调）。
- 另三个入口：••• 菜单「打开原文」、正文里的网页链接（mailto 等非网页链接仍交系统）、紧凑栏副标题末尾「↗」（紧凑栏基本出现后才可点），均在内置浏览器打开。
- 浏览器版式（Figma 无浏览器画面，沿用阅读页版式）：顶栏 ✕ + 网页标题/域名；2pt 中性灰加载进度线；失败原因 + 重试；底栏五格与阅读页同位：后退 / 前进 / 刷新 / 分享 / 在 Safari 中打开（系统符号、次要灰）。关闭网页自带左滑后退（与左边缘返回冲突），后退用底栏。浏览器历史不影响阅读页。
- 边界：浏览器页在网页控件专用目录；未引用旧版浏览器代码；避开含禁用字样的「新建窗口」回调（LESSONS 30）。

## ADR-022：「下一篇」按钮原地换页（2026-09-25，用户“都按建议来”）

- 底栏 ∨：用全新的阅读页原地替换当前页（`Babel2NavigationController.replaceTopBabel2`），导航层数不变；看多少篇都只需一次返回。每篇都是干净的阅读页（自动已读、订阅源总是阅读模式、译文自动恢复照常生效），不在同一阅读页里改内容以免残留上一篇状态。仍遵守合同“不为下一篇 push 新阅读页”（替换不 push）；手势翻页继续封存（ADR-016）。
- 顺序：文章列表显示顺序；「未读」档跳过已读（留在列表里变细的那些），「全部」「星标」档不跳过。
- 最后一篇：∨ 变灰不可点（页面建好即判断，出现后再刷新）。
- 过渡：旧页向上滑走、新页从下方滑上，约 0.3 秒（淡入淡出为备选）。
- 返回列表：列表已最小滚动到最后读的那一篇，保证它在屏幕上。
