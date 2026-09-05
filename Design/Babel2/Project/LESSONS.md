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

## 22. `simctl` 取证的三个流程性坑（2026-09-05，做 A2/A3/A7 时踩到）

- 症状一：用 `xcrun simctl terminate` 结束进程后直接用同一 bundle id 再 `launch`（不 uninstall/install），有一半左右的启动只拿到 7 个事件、缺 `sceneConfigurationSelected`，`isValid=false`、`invalidReasons=["sceneConfigurationSelectionMissing"]`。
  根因：UIKit 复用了上一次启动留下的 `UISceneSession`，这次不会再调用 `configurationForConnecting`，AppDelegate 也就没机会记录这一事件——这是 2026-09-01 记录过的"warm Genesis"现象，但当时只当成一次性观察，没有写成通用 gate。
  以后 gate：**做启动参数矩阵时，每个场景之间都要 `uninstall` 再 `install`，不能只 `terminate`**；判断一次启动是不是"冷启动"看 PID 变没变不够，还要看 trace 是不是 8/8 事件、`isValid=true`。
- 症状二：全新 `install` 后的**第一次**冷启动，等 3 秒抓 log 只拿到 6/8 事件（缺 `containerAppeared`/`contentFirstFramePresented`）；同一个 build 后续的冷启动等 3 秒都是 8/8。
  根因：`bootstrapBabel2RuntimeIfNeeded()` 在真正意义上的首次运行会同步做 `AppDefaults.registerDefaults()` + `DefaultFeedsImporter.importDefaultFeeds(...)`（导入默认订阅源），比后续启动多一截同步工作，把 content-first-frame 推迟到 3 秒窗口之外。
  以后 gate：**"全新 install 后的第一次启动"要单独多等几秒**（本轮用了 8 秒），不能和同一 build 后续的冷启动用同一个等待时间；6/8 的中间结果要保留在证据里，不能直接删掉重跑当作没发生过。
- 症状三：`xcrun simctl openurl` 传一个应用没有在 `CFBundleURLTypes` 里注册的自造 scheme（如 `babel2test://…`），系统直接报 `LSApplicationWorkspaceErrorDomain` 115，URL 根本没送到 App，`SceneDelegate` 完全没被调用。
  根因：`simctl openurl` 走的是系统的 URL 路由（`LSApplicationWorkspace`），跟 App 内部"识别/不识别"的判断是两层——不注册 scheme 连路由这一层都过不去，测的是 iOS 的行为，不是 `Babel2ExternalActionParser` 的行为。
  以后 gate：**测"App 内部把某个 URL 判定为未识别"，必须用一个真实注册过的 scheme（`grep CFBundleURLSchemes` 或 `PlistBuddy -c 'Print :CFBundleURLTypes' Info.plist` 查)，配一个解析器一定会拒绝的 host/path**，而不是随手编一个新 scheme；系统层拒绝要如实记成"废弃尝试"，不能悄悄换个 URL 就当没发生过。

## 23. `simctl` 能测到"后台/前台"，但测不到"真正的 scene disconnect"和"shortcut/通知被点击"（2026-09-05，做 A8/A10 时确认）

- 症状一：`xcrun simctl terminate` 之后抓日志，只看到进程被硬杀时的系统/网络清理日志，完全没有 `SceneDelegate.sceneDidDisconnect(_:)` 应该打的 teardown 行。
  根因：`simctl terminate` 是在进程层面发 kill，不经过 UIKit 正常的 scene 生命周期——真正触发 `sceneDidDisconnect` 的是用户在 App 切换器里把 App 划掉，或者系统在后台回收 scene，这两种都不是"进程退出"，命令行没有等价物。
  以后 gate：**验收 A10 这类"scene disconnect/teardown"要求时，`simctl terminate` 只能证明"进程被杀不会遗留问题"，不能当成"scene disconnect 路径被测过"**；这部分证据只能来自现有直接调用 `sceneDidDisconnect()`/`tearDown()` 的单元测试，或者真机/交互操作，两者要分开记录，不能互相顶替。
- 症状二：想验证"App 被切到后台又切回来"，一开始想不到该发什么 `simctl` 命令。
  做法（记下来供下次直接用）：**`xcrun simctl launch <udid> <另一个已装 App 的 bundle id>`（比如 `com.apple.Preferences`）能把目标 App 挤到后台而不杀死它**；之后再 `xcrun simctl launch <udid> <目标 bundle id>` 一次，就能把它拉回前台——全程不需要任何点击，PID 不变，能验证 `sceneDidEnterBackground`/`sceneWillEnterForeground` 这一对真实回调有没有被触发（看日志里有没有 `applicationWillResignActive`、`Application processing resumed.` 这类真实字符串，不能只看"没报错"）。
- 症状三：想给 A8 补 shortcut item 和 notification response 两条，找不到对应的 `simctl` 子命令。
  结论：**`xcrun simctl` 没有"模拟长按图标选 shortcut"或"模拟点击一条通知"的命令**；`simctl push` 只能把通知投递到通知中心，测的是"通知能不能弹出来"，不是"用户点了它之后 App 怎么反应"（那要经过 `UNUserNotificationCenter` 的 `didReceive response:` 回调，只有真实点击或全套 XCUITest 手势才能触发）。
  以后 gate：**这两条外部动作路径的运行时证据，要么等一次真机/交互操作配合截图和抓日志，要么用 XCUITest 走 UI 手势去点**，不要在 `simctl` 里硬找一个不存在的等价命令浪费时间；静态引用（读代码确认处理函数是不是无副作用的 no-op）可以先写，但不能当成运行时通过。

## 24. `UISceneSession` 造不出来，"真实状态恢复"这条链天生测不到最后一环（2026-09-05，做 A4/A5/A9 时确认）

- 症状：想给 A4/A5/A9（restoration 相关）补"真的经过 `SceneDelegate.scene(_:willConnectTo:options:)` 读取 `session.stateRestorationActivity`"这条端到端证据，翻遍 `xcrun simctl` 的子命令、也试过在测试里直接构造，都做不到。
  根因：`UISceneSession` 是系统托管对象，没有公开的初始化方法，测试代码没法自己造一个"待恢复"的假 session；而现实中触发真实恢复流程的条件是"系统已经把这个 scene 从内存里彻底回收、但磁盘上还留着这个 session 的记录"——`xcrun simctl terminate` 是直接在进程层面 kill（不走保存流程，见第 23 条），`uninstall`/重装会直接把 session 本身抹掉（不是"回收又恢复"，是"从来没有过"），两者都不是这个中间态，命令行也没有更细的旋钮能强制系统进入这个中间态。
  以后 gate：**"restoration/状态恢复"这类需求，能测到的证据天然分两层，要分开说清楚，不能含糊成一句"通过"**——① 数据校验层（`isValid`/`decoded`/`validated`）和 root 组装层（`makeRoot(restoration:)`）可以直接调用生产函数测，能覆盖到"输入什么、应该出什么结果"的完整矩阵；② 真正"系统触发"这一环，要么等真机上真实发生一次（背景很久、系统内存紧张时自然回收），要么给生产代码加一个可测试的 seam（比如把"从 session 读 restoration"抽成一个可注入的协议）——但这是一次产品代码改动，需要先问、不能在"只取证"的任务里顺手做了。写证据文件时，这两层要分开写清楚覆盖到哪一层，不要用①的通过掩盖②还没做。

## 25. 高频真实启动会把 OSLog 自己的缓冲区挤爆，"最后统一抓日志"这套手法在大批量场景下会丢证据（2026-09-05，做 A11 30 次真实冷启动时确认）

- 症状：先跑完 30 次真实 uninstall/install/launch，最后才用一条 `log show --last 5m`（后来加大到 `--last 30m`）去抓全部日志，结果只捞到最后 11-12 轮的 trace，前 18-19 轮"NO TRACE FOUND"——不是因为没发生，是日志已经没了。
  根因：每次冷启动光是系统噪音（网络、UIKit lifecycle、XPC 各种连接日志）就有两千多行，30 次乘起来接近 10 万行；OSLog 的进程内缓冲区是按**体积**淘汰旧数据的，不是纯按查询窗口的时间保证一定能查到——查询窗口再放大，如果数据已经被挤出缓冲区，一样查不到。之前小批量（10 次左右）从没撞到这个上限，掩盖了这个问题。
  以后 gate：**批量做真实启动取证（数量超过一二十次）时，日志必须"每轮做完立刻抓、立刻存盘"，不能攒到最后一次性抓**——哪怕这样脚本要多跑几次 `log show`、慢一点。这条本轮已经改过来了（`a11_30_cycles_v2.sh` 每轮 launch 后立刻 `--last 15s` 单独存一个文件），30/30 轮全部拿到完整证据。以后写类似脚本，默认就按"每轮抓"设计，不要图省事先攒后抓。

## 26. "调用 launch 的那一刻"不等于"进程真正开始跑"，中间能差 2 秒以上（2026-09-05，做 A12 启动截图时踩到）

- 症状：想拍"进程启动后 0.5/1.0/2.0 秒"的截图，第一版脚本以`调用 xcrun simctl launch 那一刻`的时间戳为 t=0 开始计时、按目标秒数睡眠后拍照。事后拿真实 trace 一比对，三张截图全部拍在 `AppDelegate.init()`（真正的 processEntry）之前 0.5~1.7 秒——也就是说三张截图都拍在"App 还没开始跑"的时候，是废证据。
  根因：`xcrun simctl launch` 命令本身要经过"和 CoreSimulator 守护进程握手→请求启动→等待确认"这一整套往返，加上冷启动（尤其是刚 install 完）的动态链接、Swift 运行时初始化，从"我发出 launch 命令"到"App 的 `AppDelegate.init()` 真正开始执行"之间，实测差了 2~2.5 秒——这段时间完全花在"进程还没起来"上，不是应用代码的锅，但会让任何"从 launch 调用开始计时"的截图脚本全部对不上号。
  以后 gate：**任何要求"进程启动后 N 秒"的取证，不能以"我调用 launch 的时刻"为 t=0，必须以 trace 里真实的 `processEntry` 事件时间戳为 t=0**——而这个时间戳只有等这一轮启动跑完、日志抓下来之后才知道。正确做法是反过来做：先不设时间假设，冷启动后**立刻连续密集拍一批截图**（不用人为 sleep，让工具调用本身的开销自然形成采样间隔），每张都用 `date +%s.%N` 记纳秒级时间戳；事后从真实 trace 拿到 processEntry 的精确挂钟时间，反推每张截图相对它的真实偏移，再从这批里挑最接近目标秒数的几张。汇报时如实写"实测偏移 +0.307s"而不是假装踩中了"0.5s"，比伪造精度更可信。

## 21. 改默认值/去掉安全余量必须重跑全量测试，不能只跑受影响的单测（2026-09-05）

- 症状：Feeds/Timeline 卡片打磨的工作树改动（文件夹层级、缩略图卡片、`filterDisplayOrder` 固定 Figma 像素坐标、默认 scope 从 `.all` 改为 `.unread`）在包测试 30/30 通过、Debug 编译成功的情况下被当作"已验证"，但从未跑过全量 iOS Debug 测试；补跑后暴露 2 个真实回归：①`layoutScopeControlsIfNeeded()` 把旧版 `max(44, …)` 的保底宽度换成纯 Figma 绝对坐标，且新增 `scopeStack.bounds.width > 0` 才布局的 guard——任何还没被真实 window 赋予宽度的宿主（测试 host、或极端情况下的过早布局回调）会让筛选按钮永远停在初始的零尺寸 frame 上，`XCTAssertGreaterThanOrEqual(scope.frame.width, 44)` 直接失败；②`testStaleScopeResultCannotPublishAfterLatestIntentChanges` 被手改成 `after: 2`，但默认 scope 改为 `.unread` 后 `viewDidAppear` 已经预加载过 `.unread`，`scopeTapped` 对"已加载过的 scope"不会重新发请求（只是切换显示），导致测试里布下的 delayed 请求永远不会被消费，等到超时。
- 根因：①去掉一个"保底"分支时没有反问"这个保底原本在防什么场景"——它防的正是"容器还没测出真实宽度"，删掉后没有留退路；②改一个全局默认值（`.all` → `.unread`）会连带改变哪个 scope 处于"页面刚打开就已经加载过"的特权位置，凡是靠"这个 scope 还没加载过"来构造竞态的测试，都要跟着把角色互换，而不是简单把等待的次数 +1 掩盖过去。两处都只跑了 `swift test --package-path Modules/Babel2UI`（不触达真实 UIKit 视图层）和 `xcodebuild … build`（不跑测试），没有跑会真正实例化 `Babel2RootViewController` 并驱动交互的全量 Debug test。
- 以后 gate：任何触及 `Babel2RootViewController`/`Babel2FeedViewController` 交互、默认状态或布局常量的改动，落地前必须跑一次全量 `xcodebuild … test`（不是只跑 package tests 或只 `build`），并且要看 `xcresulttool get test-results summary` 的 `failedTests` 精确数字，不能只看 `** BUILD SUCCEEDED **`。删除任何 `max(minimum, …)` 式的保底计算前，先想清楚它在防哪个"测不到真实尺寸"的场景，删掉后要么证明该场景不再存在，要么补一个不依赖真实尺寸的等价保底。改动任何"谁是默认/预加载 scope"的产品决定时，同一 commit 里要重新审视所有依赖"某 scope 尚未加载"来构造时序/竞态的测试，把角色换成新的未预加载 scope，而不是调大等待次数。
