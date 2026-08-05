我在继续 NetNewsWire iOS fork（Babel）的工作，项目在
`/Users/wenbopan/Downloads/RSS ai translation`

**请先按顺序读，读完再动手：**

1. `CLAUDE.md` —— 项目规则。**但第 0 节第 7 条已被下面的「工作方式更正」推翻**
2. `NOTES-progress.md` 最前面的「📍 接手须知」
3. `NOTES-todo.md` 的 **T40**（这一整轮设计换血的来龙去脉、已完成、已知未做）+ **T41**
4. `NOTES-lessons.md` 的 **L100–L116** —— 全是这一轮踩出来的，和接下来的活直接相关

---

## ⚠️ 开工前先确认分支

```
main                停在 649f85fd5 = tag genesis（回滚点，这一轮一行没进）
design/soft-dock    ← 当前工作分支，已 push 到 origin
design/soft-shell   被否决的设计师方案，留档别用
```

`git branch --show-current` 应该是 `design/soft-dock`。

## ⚠️ 工作方式（这一轮最贵的三条教训）

1. **视觉改动交付前必须自己用 iOS 模拟器截图看过**（L100）。本环境有专门的模拟器工具
   （截图 + 按坐标点按），又快又便宜。CLAUDE.md 里"别用操作电脑验收"那条针对的是
   通用 computer-use，不适用。
2. **深色模式是验收面积的另一半，不是"配色的另一档"**（L112）。
   **"做完"的定义里必须包含深色截一张。**
3. 🆕 **"我复现不了"是关于工具的判断，不是关于问题的判断**（**L115**，见下）。

---

# 🟢 上一轮（2026-08-05 深夜）已经修好的事：底栏「边缘渐隐」

**别再碰这件事，它已经查清并修好了。** 完整记录在 T40 的「2026-08-05 深夜」一节 + L115/L116。

一句话结论：**病根是 `hidesSharedBackground`，不是"拍平工具栏"；
症状的描述本身也是错的 —— 不是"渐隐丢了"，是内容压根没滚到栏底下去。**
修法是 `nnwHideSystemGlassCapsule()` 按系统版本分道（iOS 27+ 不拆，iOS 26 照旧拆）。

**⚠️ 以下三条已实测排除，别再走**（都有日志确认代码执行了，画面逐行不变）：
- 「拍平工具栏拿掉了渐隐」这套因果 —— 拍平与不拍平**逐字节完全相同**
- `UIScrollView.bottomEdgeEffect`（style / isHidden）—— 对 WKWebView **完全无效**
- `UIScrollEdgeElementContainerInteraction` —— **无效**（这是上一版 NEXT-PROMPT 力荐的那条）

---

# 🔧 这一轮打通的新能力：**能直接在用户的 iOS 27 真机上做实验**

用户的开发机 SDK / 模拟器是 **iOS 26**，真机是 **iOS 27 beta**。
以前遇到"只在真机上出现"的问题只能猜（L94/L95/L114 都栽在这），**现在不用了**。

**前提**：用户把 iPhone 用数据线连着电脑（开发者模式已开，签名已配好，`xcodebuild` 真机编译能直接过）。

```bash
DEV=B0E875BF-CAEA-549C-A020-1C01331F0DF3   # 用户的 iPhone 17 (iOS 27)
BID=com.wenbopan.NetNewsWire.iOS-DEBUG      # 与手机上现有的 app 同身份 = 覆盖升级，数据不丢

# 1. 真机编译（签名自动过）
xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS -configuration Debug \
  -destination "platform=iOS,id=$DEV" build

# 2. 装（⚠️ 编译和装机分两步跑，别用 && 串）
xcrun devicectl device install app --device $DEV <构建产物路径>/NetNewsWire.app

# 3. 带环境变量启动 + 读控制台（DEVICECTL_CHILD_ 前缀会传给 app）
DEVICECTL_CHILD_NNW_EXP=xxx xcrun devicectl device process launch \
  --device $DEV --terminate-existing --console $BID

# 4. 把 app 沙盒里的文件拉回电脑（截图、日志、任何我们自己写的文件）
xcrun devicectl device copy from --device $DEV \
  --domain-type appDataContainer --domain-identifier $BID \
  --source Documents --destination ./本地目录
```

⚠️ **`log stream --device` 在这台 Mac 上不可用**（新版 macOS 拿掉了），
读真机日志走 `devicectl ... --console`。

**配套套路（L115，这一轮就是靠它一轮命中的）**：
1. 加一个环境变量开关，**同一个二进制**切多种条件 —— 避免"不同构建 / 不同滚动位置"混进来
2. 让 **app 自己给自己截图**（`window.drawHierarchy(afterScreenUpdates: true)`）、
   **就地采样把数字打进日志**、并把原图写进 `Documents` 供拉回
3. ⚠️ **仪器先在 iOS 26 上校准**：和 Mac 侧 `xcrun simctl io booted screenshot` 直接量的
   数字逐点比对（上次 130 点、平均差 0.12 级才敢用）。
   **没校准的仪器给出的"没有信号"，和"信号真的不存在"长得一模一样。**
4. **做反向实验**：不光"关掉它看有没有变化"，还要"强制它做相反的事"并**打日志回读**确认
   真写进去了 —— 否则"两组数据相同"可能只是那行代码压根没跑

⚠️ **动用户的手机前要先问**（这是他的日常用机）。

---

# 接下来的待办（按建议顺序）

## 1. 🔴 先让用户在 iOS 27 上验一眼：**首页那几颗圆钮会不会露出双层**

这是上一轮那个修法**唯一没验到的地方**，我够不着（没法自己导航到那些页面）。

`nnwHideSystemGlassCapsule()` 被四处使用：文章页 dock、三档控件、
首页（齿轮/加号/搜索/编辑）、文章列表页。iOS 27 上现在**不拆系统胶囊**了 ——
文章页 dock 是一整块 customView，系统胶囊和它重合、不显套娃（已截图确认）；
但**首页那几颗圆钮是烘焙进图片的小图标**，系统胶囊套在外面**可能**露出双层。

如果真露出来了：那就是"26 要拆、27 也要拆，但 27 一拆就丢可视区域"的两难，
需要换思路（例如首页那几处改成 customView，让系统胶囊和我们的圆钮重合）。

## 2. 底部控件进/回页面时慢 0.5–1s 才出现

用户 2026-08-05 报，**一直没做**。⚠️ **别猜，先埋日志**（L94）：
在 `viewWillAppear` / 装配完成 / 图片画完各打一条时间戳，先证明时间花在哪一段。

我的怀疑（**不是结论**）：
- `NNWSoftMaterial.roundButtonImage` **每次调用都现画位图**（`UIGraphicsImageRenderer`
  × 2 颗圆钮 × 每次 `viewWillAppear`），**没有缓存** —— 这条最可疑
- 三档控件是在 `viewWillAppear → nnwUpdateReadingMode` 里装的，不是 `viewDidLoad`
- ★ 档要等 `NNWStarredIndex` 异步查库（L53）

## 3. 深色模式还没走过的页面

这一轮在深色下验过：首页底栏、文章列表页、文章页 dock、文件夹行。
**没验过**：自绘选单、设置页、发现页、试读页、编辑模式。
⚠️ 选单也吃那层"提亮补丁"，按 L112 的经验大概率有同类问题。

## 4. 四颗底栏圆钮仍不透明

中间三档那条是真磨砂、两侧圆钮是烘焙的不透明图片，并排看得出来。
改成 customView 就能解决，但要自己转发 `menu`（首页的 `+` 是 IBOutlet 且上游挂了 menu）
和 `isEnabled`（三处上游在写）—— 换掉会**静默**丢功能，风险在这里。
📌 **和待办 1 可能是同一件事**：如果首页圆钮在 27 上露出双层，
改 customView 正好一并解决。

## 5. `nnwEnableSoftBottomEdgeFade()` 死代码清理

见 **T41**。正文页那处已证实是空操作；首页/列表页那两处（普通 UICollectionView）没验过，
所以暂时留着。清理方法 T41 里写了。**优先级低，不影响任何功能。**

## 6. 选单图标还是 SF Symbols

参考图那套是手绘的圆头粗笔画（笔画占比 11.6%），SF Symbols 顶到 `.bold` 也只有 10.5%。
要对上得整套手绘 15–18 个图标。**用户没催，优先级最低。**

---

# 硬约束（CLAUDE.md 里都有，这里只列最容易忘的）

- **一律中文回复，代码注释也用中文**（写给读不懂代码的用户看）
- **最高优先级是保持可 merge**：优先新增文件；改上游要最小化并带
  `[翻译]/[外观]/[管理]/[发现]/[链接]/[长图]/[品牌]/[阅读档]/[编辑]` 标记
- **每次改完自己编译**：
  `xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build`
- **装模拟器只用 `./tools/install-to-simulator.sh`**
- ⚠️ **编译和装机分两步跑，别用 `&&` 串**（编译失败会把旧产物装进去 —— 上一轮又犯了一次）
- ⚠️ **`Shared/` 会被扩展目标编译，那里看不到 `iOS/` 的类型**（L103）
- ⚠️ **底部工具栏的 `toolbarItems` 结构不能动**：有 `expectedItemCount == 3` 的守卫，
  且 `addNewItemButton` 是 storyboard 的 IBOutlet。只能换 `image` 和 `tintColor`
- **push 我说了才做**

# 反复咬人的判据

- **改一个显示值之前，先数清楚它有几个写入点**（L74）
- **给已有函数加观察者/通知之前，先确认它幂等**（L113）
- **给浅色打的补丁，先问它在深色下是不是反的**（L112）
- **"让某个系统外壳消失"时，先想清楚那层外壳还顺带提供了什么**（L114 + **L116**
  —— 这条连着咬了两次：以为丢的是渐隐，其实丢的是"内容能从栏底下穿过去"）
- **两个系统版本要的相反时，只能按版本分道，但两边都要有实测证据**（L116）
- **量圆的直径要横扫取最宽处**（L109）
- **"换主题色跟不上"到目前为止只有两种原因**：(a) 用了 `Assets.Colors.*` 静态色板；
  (b) 上色写在只跑一次的地方
