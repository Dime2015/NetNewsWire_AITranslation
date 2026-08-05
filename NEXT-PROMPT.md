我在继续 NetNewsWire iOS fork（Babel）的工作，项目在
`/Users/wenbopan/Downloads/RSS ai translation`

**请先按顺序读，读完再动手：**

1. `CLAUDE.md` —— 项目规则。**但第 0 节第 7 条已被下面的「工作方式更正」推翻**
2. `NOTES-progress.md` 最前面的「📍 接手须知」
3. `NOTES-todo.md` 的 **T40 / T42 / T43**（底栏那场仗的来龙去脉 + 这一轮要做的事）
4. `NOTES-lessons.md` 的 **L100–L117**

---

## ⚠️ 分支与回滚点（先跑 `git branch --show-current`）

```
design/custom-dock   ← 当前工作分支（文章页 dock 已搬出工具栏），已 push
design/soft-dock     稳定版：tag dock-system-glass 就在这条上，已 push
main                 停在 tag genesis（这一整轮设计改动一行没进）
design/soft-shell    被否决的设计师方案，留档别用
```

**三个回滚点，说哪个回哪个**：
- 「回到创世版本」→ `git checkout genesis`
- 「回到玻璃版」→ `git checkout dock-system-glass`（系统胶囊版，iOS 27 上验过是好的）
- 当前实验 → `design/custom-dock`

## ⚠️ 工作方式（这个项目最贵的四条教训）

1. **视觉改动交付前必须自己用 iOS 模拟器截图看过**（L100）。本环境有专门的模拟器工具，
   又快又便宜。CLAUDE.md 里"别用操作电脑验收"那条针对的是通用 computer-use，不适用。
2. **深色模式是验收面积的另一半**（L112）。"做完"的定义里必须包含深色截一张。
3. **"我复现不了"是关于工具的判断，不是关于问题的判断**（L115）——见下面「真机通道」。
4. **别目测，要采样**（L101/L104/L107/L109）。视觉的事逐像素量，用户说"好像好了"不算数。

---

# 🔧 已打通：**能直接在用户的 iOS 27 真机上做实验**

开发机 SDK / 模拟器是 **iOS 26**，用户真机是 **iOS 27**。以前"只在真机上出现"的问题只能猜
（L94/L95/L114 都栽过），**现在不用了**。前提是用户把 iPhone 用数据线连着（开发者模式已开）。

```bash
DEV=B0E875BF-CAEA-549C-A020-1C01331F0DF3   # 用户的 iPhone 17 (iOS 27)
BID=com.wenbopan.NetNewsWire.iOS-DEBUG      # 与手机上现有 app 同身份 = 覆盖升级，数据不丢

# 1. 真机编译（签名自动过，不需要用户在 Xcode 里点任何东西）
xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS -configuration Debug \
  -destination "platform=iOS,id=$DEV" build

# 2. 装（⚠️ 编译和装机分两步跑，别用 && 串）
xcrun devicectl device install app --device $DEV <产物路径>/NetNewsWire.app

# 3. 带环境变量启动 + 读控制台（DEVICECTL_CHILD_ 前缀会传给 app）
DEVICECTL_CHILD_NNW_EXP=probe xcrun devicectl device process launch \
  --device $DEV --terminate-existing --console $BID

# 4. 把 app 沙盒里的文件拉回电脑（我们自己写的截图/日志）
xcrun devicectl device copy from --device $DEV \
  --domain-type appDataContainer --domain-identifier $BID \
  --source Documents --destination ./本地目录
```

⚠️ **`log stream --device` 在这台 Mac 上不可用**，读真机日志走 `devicectl ... --console`。
⚠️ **手机锁屏时启动会失败**（报 `device was not unlocked`），要让用户解锁。
⚠️ **动用户手机前先问**——那是他的日常用机。

**配套套路（L115）**：加环境变量开关，同一个二进制切多种条件；让 app **自己截图**
（`window.drawHierarchy(afterScreenUpdates: true)`）写进 `Documents` 再拉回来。
⚠️ **仪器先在 iOS 26 上校准**（上次 130 点、平均差 0.12 级才敢用）——
**没校准的仪器给出的"没有信号"，和"信号真的不存在"长得一模一样。**
⚠️ **做反向实验**：不光"关掉它看有没有变化"，还要"强制它做相反的事"并**打日志回读**确认
真写进去了 —— 否则"两组数据相同"可能只是那行代码压根没跑。

---

# 🔴 待办（按建议顺序，前三条是"坏没坏"，优先于"好不好看"）

## 1. 浮动 dock 的三项功能验证（**最优先，我没验完就交了**）

文章页 dock 已从工具栏搬出来当浮层（`iOS/Article/NNWFloatingDock.swift`）。
**以下三件只在模拟器上看过静态截图，没有实际操作验证**：

- **沉浸阅读**：下滑藏栏时 dock 有没有跟着淡出、上滑有没有回来
  （钩子接在 `viewSafeAreaInsetsDidChange` → `nnwSyncFloatingDockVisibility`）
- **翻页**：上一篇/下一篇之后 dock 还在不在最上层
  （⚠️ 装它的代码比 `pageViewController.view` 早，被盖过一次，见文件头）
- **滚到文章最底部**：最后一行能不能真的露到 dock 之上（补了 `additionalSafeAreaInsets.bottom`）

## 2. iOS 27 真机上装一次浮动 dock 版

`design/custom-dock` 还没在真机上跑过。用上面那套通道装 + 拉截图。

## 3. 🔵 T43：陀螺仪驱动的边缘反光（**用户主动提出的新想法**）

用户原话：「利用上 iPhone 的陀螺仪，手机动的时候，按钮的边缘反光也会跟着动」。

**⚠️ 用户拍板的范围（别做大）**：
> 「**只在订阅源页（首页）用**，那个是进入 app 的首页，能够抓人眼球，
> 之后的页面可以低调点。」

**⚠️ 有一个前置障碍，别一头撞上去**：陀螺仪反光要求**那圈亮边归我们画**。而现在
文章页 dock 归我们（但用户不要在这页做），**首页的控件还在系统栏里**——
iOS 27 上它们的底是系统的液态玻璃，我们碰不到那圈边（见 T42）。

**所以顺序是：先把首页要发光的那个控件搬出栏，再谈陀螺仪。**
建议**只搬「三档控件」**（`NNWReadingModeBar`）——它本来就是 customView、
在首页最显眼居中，而且绕开了首页那两个雷（`+` 是 IBOutlet 且挂着 menu；
底部工具栏有 `expectedItemCount == 3` 的守卫）。齿轮/加号/搜索/编辑**先别动**。

技术路线、必须一起做的三件事（无障碍开关 / 离页停更新 / 30Hz）、
以及"模拟器没陀螺仪所以只能在真机上验"的验证办法，**全写在 T43 里**。

## 4. 材质定案（用户说不着急）

四版对比用户的反馈是「**都不怎么能看出太多区别**，第三版（阴影拉开）还不错，
但**不着急纳入正式版**」。⚠️ **临时开关 `NNW_DOCK=v1/v2/v3` 先留着别删**，
等陀螺仪效果做出来一起定。（v1「窄版」那次没测到——当时模拟器停在文章列表页。）

## 5. 底部控件进/回页面时慢 0.5–1s 才出现

用户 2026-08-05 报，一直没做。⚠️ **别猜，先埋日志**（L94）：
`viewWillAppear` / 装配完成 / 图片画完各打一条时间戳。
最可疑：`roundButtonImage` 每次调用都现画位图，没有缓存。

## 6. 深色模式还没走过的页面

验过：首页底栏、文章列表页、文章页 dock、文件夹行。
**没验过**：自绘选单、设置页、发现页、试读页、编辑模式。

## 7. `nnwEnableSoftBottomEdgeFade()` 死代码清理

见 T41。正文页那处已证实是空操作；首页/列表页那两处没验过所以留着。**优先级低。**

---

# 硬约束（最容易忘的）

- **一律中文回复，代码注释也用中文**（写给读不懂代码的用户看）
- **最高优先级是保持可 merge**：优先新增文件；改上游要最小化并带
  `[翻译]/[外观]/[管理]/[发现]/[链接]/[长图]/[品牌]/[阅读档]/[编辑]` 标记
- **每次改完自己编译**（scheme `NetNewsWire-iOS`，模拟器 `iPhone 17`）
- **装模拟器只用 `./tools/install-to-simulator.sh`**
- ⚠️ **编译和装机分两步跑，别用 `&&` 串** —— 编译失败会把旧产物装进去（上一轮又犯了一次）
- ⚠️ **`Shared/` 会被扩展目标编译，那里看不到 `iOS/` 的类型**（L103）
- ⚠️ **底部工具栏的 `toolbarItems` 结构不能动**：`expectedItemCount == 3` 的守卫 +
  `addNewItemButton` 是 IBOutlet
- **commit / push 我说了才做**

# 反复咬人的判据

- **"让某个系统外壳消失"时，先想清楚那层外壳还顺带提供了什么**（L114 + L116
  —— 连着咬两次：以为丢的是渐隐，其实丢的是"内容能从栏底下穿过去"）
- **同一个地方反复出问题，先假设是同一个原因**，哪怕用户两次描述听起来毫不相干（L117）
- **两个系统版本要的相反时，只能按版本分道，但两边都要有实测证据**（L116）
- **改一个显示值之前，先数清楚它有几个写入点**（L74）
- **给已有函数加观察者/通知之前，先确认它幂等**（L113）
- **给浅色打的补丁，先问它在深色下是不是反的**（L112）
- **调了三次细节还差一层，就该怀疑自己在调错的变量**（L108）
