# Babel 2.0 经验教训

每条记录都采用“症状 / 根因 / 以后 gate”格式。它们是工程约束，不是对当前完成度的替代声明。

## 1. 组件复用会把旧状态和旧视觉一起带进来

- 症状：相同底栏控件尺寸、颜色、选中态和 loading 状态在不同页面不一致；某些页面出现旧功能或重复控件。
- 根因：复用的是带隐式状态、生命周期和样式的 controller/view，而不是经过合同约束的数据/行为接口；多个页面各自改外观，产生派生分支。
- 以后 gate：每个跨页面控件只有一个 Babel2 token、渲染规格和状态 owner；复用前做依赖审计，确认不带入历史 UI、旧颜色、旧手势或隐式 WebView 状态；同一控件在 Feeds、Timeline、Reader 必须有统一尺寸测试和设备截图。

## 2. 历史 UI 会通过启动链或 coordinator 隐式混入

- 症状：新页面点击后回到旧壳、出现旧 landing page、旧 toolbar 或旧 WebView pool；退出再进入时重复壳。
- 根因：启动、外部 action、状态恢复和 deep-link 仍由历史 coordinator 直接接管；没有 generation-aware route mapper 和单一 Babel2 root。
- 以后 gate：feature gate 优先级、root count、generation/schema、进入/退出/re-entry 必须有自动测试；Babel2 route 不能直接调用历史 controller；fallback 只能是明确且可观测的边界。

## 3. WebView 脚本与文章状态必须隔离

- 症状：标题/作者先消失后在顶栏出现，翻译标题滚动时重影、闪屏，某些源最终闪退；Reader 返回后位置或状态不稳。
- 根因：复用的 WebView/configuration/script message handler 保留了旧文章、翻译或滚动状态；异步重建 DOM 与 UIKit header 同时写布局；加载 owner 不唯一。
- 以后 gate：每个 Reader/Browser route 使用明确的 session token 和独立 WebView state；脚本注入、内容高度、scroll offset、翻译 DOM 更新必须可取消并按 token 丢弃过期回调；复用池只能在合同允许且状态完全重置时使用；重复进入、切换翻译和快速返回必须跑 Instruments 与设备测试。

## 4. 动画必须只有一个 motion owner

- 症状：翻页、返回、收缩标题、hero 和底栏互相抢写 frame，出现跳变、不能反向跟手、手势偶尔失效。
- 根因：多个 gesture recognizer、UIView 动画、scroll callback 和 controller 同时修改同一 surface；没有 token、采样进度和中断结算。
- 以后 gate：一个 surface 只有一个 Babel2 motion owner；所有 tracking/settle/interruption 通过统一 driver，带 route generation 和 interaction token；在单元测试和设备上验证 start/track/finish/cancel/interruption、边缘 24–32pt 和非边缘不触发。

## 5. 系统菊花和同步箭头不能重复出现

- 症状：加载场景同时看到自绘旋转箭头和系统菊花；同步结束后箭头仍常驻。
- 根因：同步状态、文章加载状态和系统默认控件没有统一 ownership/visibility 状态机；各层把“正在等待”都当成自己的职责。
- 以后 gate：sync arrow 只绑定真实 syncing；文章/翻译使用 skeleton/passive state；同一 surface 同时最多一个可见 loading owner；完成、失败、取消都有明确终态和 retry，不以永恒 spinner 代替错误。

## 6. 翻译重建会造成重影和性能退化

- 症状：选择翻译标题后滚动重影、屏幕闪烁、标题翻译慢，甚至内存压力导致闪退。
- 根因：翻译结果到达时整棵文章视图或列表 cell 重建，旧层未及时移除；主线程做网络/解析/布局；翻译回调没有绑定文章和 generation。
- 以后 gate：翻译按文章/段落增量更新稳定节点；网络、解析和图片解码离开主线程；结果按 article ID、translation generation 和 cancellation token 校验；在真实大源上测首屏时间、峰值内存、滚动帧率和快速切换。

## 7. 视觉反馈必须优先于静态结构通过

- 症状：代码结构、静态截图或 Figma 对齐，但用户仍指出空白、颜色、尺寸和手感明显不对。
- 根因：把“存在控件/通过编译”误当“视觉合同成立”；没有在真实 safe area、字体、数据和手势下观察最终画面。
- 以后 gate：每个关键 Slice 都要有结构检查、模拟器截图和目标 iPhone 人工验收；用户最新反馈覆盖旧草稿；被否决的方向保留为 rejected 记录但不得重新接入。

## 8. 静态结构不等于运行时行为

- 症状：asset catalog、类型、测试或 Figma 节点存在，但启动、外观切换、图标、手势或真实内容不工作。
- 根因：静态文件没有 target membership、runtime wiring、真实数据、safe-area 和设备状态恢复验证；单元测试覆盖范围过窄。
- 以后 gate：每个需求在 REQUIREMENTS 中分别列自动化、模拟器和真机证据；没有对应运行时记录就保持 pending；构建成功不能关闭 UI/性能/设备项。

## 9. 生成图像必须按用户反馈迭代，不能把草稿当品牌资产

- 症状：玻璃 B、杂志海、凸印和早期 Light 黑蒙版/焦化感等方向虽能生成，但用户逐轮否决；随后 Light 按“亮木桌+逐本独立暗色封面+干净页边”重生成并完成静态 QA。
- 根因：生成模型容易把“暗色”实现成全局压暗、烧焦或统一滤镜；小尺寸识别、桌面/封面层次和品牌语义没有分开验收。
- 以后 gate：每轮写清参考图角色、禁止项、输出母版和用户接受状态；分别检查原图、128/64/32px、三种外观和无圆角/无水印；用户拒绝后停止沿旧方向微调，重新锁定新的构图约束。

## 10. 命名迁移可能破坏数据 identity

- 症状：全局替换名称看似整洁，却可能改变 bundle、App Group、Keychain、Core Data store、UserDefaults 或深链 identity，导致数据消失或无法回滚。
- 根因：把用户可见品牌命名和系统持久化身份当成同一类字符串；没有备份、schema/version、兼容层和断裂检测。
- 以后 gate：新内容先用 Babel/Babel2；存量 identity 只经唯一兼容边界；稳定和真机验收前不做全量技术改名，之后每批迁移必须有授权、备份、回滚和数据回读证据。

## 11. Dirty worktree 必须被当作输入边界

- 症状：代理误覆盖其他人的图标、合同、工程或比较图，或者把未提交产物混进不相关提交。
- 根因：没有在任务开始记录 Git 快照和允许路径；把共享工作树当成自己的干净分支。
- 以后 gate：任务开始和提交前都记录 `git status`、允许文件范围和未提交清单；只修改授权路径；提交前按路径审查 diff；生成物、旧草稿和当前用户修改不得擅自删除。

## 12. 测试全绿不等于合同语义通过（第 1 轮 QA 教训）

- 症状：第 1 轮实现代理报告 25 项 package tests、5 项真实 iOS UIKit runtime tests、8 项 Boundary/Shell tests 和 Debug build 全部通过，但独立 QA 仍判定 M1 FAIL；修复后第 5 轮独立 QA 才 PASS。
- 根因：测试数量和编译结果覆盖了已有样例，却没有完整证明合同语义：缺少 `Loading.Owner`/settle 的真实区间与 typed payload+OSLog 测试；`mustYield` 没有参与 gesture arena，defer owner 会错误锁住 owner；driver 对 non-finite 输入静默归一化为合法值；还有幂等命名和旧 completion 测试缺口。
- 以后 gate：把每个合同不变量映射到可失败的语义测试，而不是只统计通过数量；对 loading ownership/settle 区间、typed diagnostic payload、OSLog、mustYield/defer ownership、non-finite 拒绝或显式错误、幂等重复调用和旧 completion 均设置独立测试；实现测试全绿后仍必须经过独立 QA 才能关闭 Slice。第 5 轮的 PASS 只关闭 M1 contract layer，不能替代页面 consumer、真机 120Hz 和 OSLogStore consumer integration 验收。

## 13. Feed/Timeline header 不能留下独立透明空带

- 症状：源标题/hero 与日期 header 之间出现无意义的透明或空白 spacer；滚动过程中空带仍可见，且 expanded、compact 与中间位置的 surface 不连续。
- 根因：header 高度、hero 收缩、section inset 由多个布局 owner 分别计算，旧的占位视图或安全区补偿没有随状态移除；透明 surface 让状态栏和内容背景产生错误的层次。
- 以后 gate：只允许标准 section inset，不允许独立 spacer；对 expanded、compact 和中间滚动位置做 geometry/snapshot 与 surface-opacity assertions，再用模拟器截图和真机连续滚动验收，确认 safe area、日期和标题之间没有透明空带。

## 14. Filter 的 pill、列表和计数必须共享同一 motion progress

- 症状：Starred/Unread/All 点击后 pill、文章列表和计数不同步，计数仍显示旧 filter；快速连续点击时过渡不能中断或反向。
- 根因：过滤语义、计数查询和视觉动画由不同状态 owner 驱动，异步结果在旧 transition 完成后才落地；没有统一 progress、interaction token 和 interrupt/reverse 结算。
- 以后 gate：selection pill、内容列表和计数绑定同一 transition progress，rapid tap 必须可中断、反向并最终收敛；计数每次按当前 filter 语义计算。设置 motion progress、interrupt/reverse、filter count 自动测试，并覆盖模拟器快速点击与真机跟手/真实数据验收。

## 15. Phase 1A 的 P0 是 gate 时序，不只是 storyboard

- 症状：Babel2 scene 可以配置为不使用 storyboard，但 legacy lifecycle/bootstrap 可能已在 `AppDelegate` 的更早阶段启动；此时只检查 storyboard 为 nil 会漏掉旧账户、同步、coordinator 或 WebKit 等副作用。
- 根因：generation gate 晚于 `AppDelegate` legacy bootstrap；启动决策、生命周期初始化和 scene/root 组装没有以同一条最早时序证据约束。
- 以后 gate：A0/A1 必须证明 generation decision 在所有 legacy side effect 之前；A6 launch trace 记录每个 bootstrap/lifecycle/storyboard/coordinator/WebKit 事件，counters 必须从事件流派生，任一 legacy event 使 trace invalid；clean fixture 的零只能是事件流结果，不能是硬编码或 suppression。A2–A15 继续覆盖 Release 持久化、未知 URL no-op、识别的外部动作保持 Babel2（最小 handler 或安全 no-op，零 legacy side effect）、恢复/销毁、30-cycle、截图、回归、single owner 和 Gate A exact allowlist。Phase 1A 在这些证据补齐前只写“实现进行中/证据待补”。

## 16. Package 全绿不能抵消真实 App 编译失败（历史记录）

- 症状：2026-08-31 前序独立 QA 中 Babel2 package tests 为 30/30 通过，Simulator 本身可用（iPhone 17 / iOS 27，UUID `555E35FA-6BFE-45F0-BCFC-0819FFE48CD2`），但 full Debug build 因 `SceneDelegate` 对 `private(set) launchTrace` 调用 mutating member 失败；指定 iOS tests 随 build cancelled，实际执行 0 项。该失败已由后续 correction build/test 修复，不是当前状态。
- 根因：package 层和真实 iOS target 的编译边界不同；只看 package log 或旧安装包/截图，会掩盖真实 scene/runtime target 的编译错误。
- 以后 gate：package 结果、full Debug build、指定 iOS tests、Simulator runtime 和目标设备必须分栏记录，不能相互替代。先修复编译错误再重跑 iOS tests；同时关闭 canonical external parser、trace event order、pending restoration validity、observer/async teardown、weak coordinator nil safety、真实 scene coverage 和 Gate A allowlist 等静态 P1。Phase 1A 保持“修复中 / 证据待补”，不得因 30/30 package 通过而标绿。

## 17. Launch trace 必须由真实事件构成

- 症状：`legacyLifecycleStarted`、`legacyBootstrapStarted` 和旧 storyboard/coordinator/WebView counters 若直接写成 `false/0`，任何启动都看起来“干净”，但没有办法知道旧初始化是否发生过。
- 根因：值快照脱离了初始化边界，没有统一 session、sequence、uptime 和 source；静态未调用旧类也不能替代动态观测。
- 以后 gate：AppDelegate 只拥有一个 recorder；旧 RootSplit/SceneCoordinator/BabelShell/WebViewProvider/PreloadedWebView 通过窄 probe 发真实事件，所有 counters 从事件派生；任一 legacy event、session/sequence/uptime/order/configuration/storyboard 缺证据都 fail-closed。结构扫描只证明不可达边界，不能伪装成 runtime trace。

## 18. 测试 fixture 不能污染 production trace

- 症状：测试为了覆盖旧类而主动实例化 coordinator/shell/WebView，随后 production recorder 记录到测试副作用，或者用 bundle、launch argument、调用栈和 suppression 排除它，二者都会使结果失真。
- 根因：fixture 与 live AppDelegate session 共用事件 sink，且没有明确 launch-window cutoff；WebView 在 content first frame 后也被错误当成启动证据。
- 以后 gate：直接 handler 测试只验证 typed event；需要 UI fixture 时注入独立 recorder sink，不依赖环境或调用栈判断；WebView/blank probe 在 content first frame 后关闭；禁止为测试增加第二套 lifecycle/root/recorder。

## 19. Trace 诊断命名与旧 UI 依赖要分开

- 症状：raw token boundary scan 把 `SceneDelegate`/`SceneCoordinator` 诊断 source/event 名称误报为 Babel2 对旧 UI 的依赖，导致修复代理要么删除证据，要么放宽整个扫描器。
- 根因：静态扫描只按字符串判断，没有区分 trace-only schema 与可执行引用。
- 以后 gate：优先使用中性 source IDs；保留必要 event schema 时只登记精确、文件级 trace-only allowlist，同时继续对所有 caller/production route 做全量禁止扫描；allowlist 不能提供新的 identity 或运行时出口。

## 20. 忽略文件的 scheme pre-action 也属于验证副作用

- 症状：build/test 的 pre-action 随机改写 ignored `SecretKey.swift`，若不记录前后 hash，dirty status 看似干净但生成状态已漂移。
- 根因：生成文件不在 Git diff 中，常规检查无法发现随机改写。
- 以后 gate：每轮 package/build/test 显式 unset 六个 secret env，记录 before/after hash，退出前恢复精确基线；`.gyb` 自身 hash 也必须保持不变，恢复失败时不报告通过。

## 21. 改默认值/去掉安全余量必须重跑全量测试，不能只跑受影响的单测（2026-09-05）

- 症状：Feeds/Timeline 卡片打磨的工作树改动（文件夹层级、缩略图卡片、`filterDisplayOrder` 固定 Figma 像素坐标、默认 scope 从 `.all` 改为 `.unread`）在包测试 30/30 通过、Debug 编译成功的情况下被当作"已验证"，但从未跑过全量 iOS Debug 测试；补跑后暴露 2 个真实回归：①`layoutScopeControlsIfNeeded()` 把旧版 `max(44, …)` 的保底宽度换成纯 Figma 绝对坐标，且新增 `scopeStack.bounds.width > 0` 才布局的 guard——任何还没被真实 window 赋予宽度的宿主（测试 host、或极端情况下的过早布局回调）会让筛选按钮永远停在初始的零尺寸 frame 上，`XCTAssertGreaterThanOrEqual(scope.frame.width, 44)` 直接失败；②`testStaleScopeResultCannotPublishAfterLatestIntentChanges` 被手改成 `after: 2`，但默认 scope 改为 `.unread` 后 `viewDidAppear` 已经预加载过 `.unread`，`scopeTapped` 对"已加载过的 scope"不会重新发请求（只是切换显示），导致测试里布下的 delayed 请求永远不会被消费，等到超时。
- 根因：①去掉一个"保底"分支时没有反问"这个保底原本在防什么场景"——它防的正是"容器还没测出真实宽度"，删掉后没有留退路；②改一个全局默认值（`.all` → `.unread`）会连带改变哪个 scope 处于"页面刚打开就已经加载过"的特权位置，凡是靠"这个 scope 还没加载过"来构造竞态的测试，都要跟着把角色互换，而不是简单把等待的次数 +1 掩盖过去。两处都只跑了 `swift test --package-path Modules/Babel2UI`（不触达真实 UIKit 视图层）和 `xcodebuild … build`（不跑测试），没有跑会真正实例化 `Babel2RootViewController` 并驱动交互的全量 Debug test。
- 以后 gate：任何触及 `Babel2RootViewController`/`Babel2FeedViewController` 交互、默认状态或布局常量的改动，落地前必须跑一次全量 `xcodebuild … test`（不是只跑 package tests 或只 `build`），并且要看 `xcresulttool get test-results summary` 的 `failedTests` 精确数字，不能只看 `** BUILD SUCCEEDED **`。删除任何 `max(minimum, …)` 式的保底计算前，先想清楚它在防哪个"测不到真实尺寸"的场景，删掉后要么证明该场景不再存在，要么补一个不依赖真实尺寸的等价保底。改动任何"谁是默认/预加载 scope"的产品决定时，同一 commit 里要重新审视所有依赖"某 scope 尚未加载"来构造时序/竞态的测试，把角色换成新的未预加载 scope，而不是调大等待次数。
