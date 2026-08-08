我在继续 NetNewsWire iOS fork（Babel）的工作，项目在
`/Users/wenbopan/Downloads/RSS ai translation`

**请先按顺序读，读完再动手：**

1. `CLAUDE.md` —— 项目规则。⚠️ **第 0 节第 7 条 2026-08-08 刚改过，必须读**
2. `NOTES-progress.md` 最前面的「📍 接手须知」
3. `NOTES-lessons.md` 的 **L124 / L125 / L126**（上一轮的新账）
4. `NOTES-todo.md` 的 **T51**（上一轮那 10 件事的完整记录：做法、坑、为什么这么修）

---

# 🔴 开工前先记住这一条（上一轮最贵的教训）

## 界面上的点按与截图验收 —— **交给用户，不要自己去点**

覆盖**一切驱动界面的工具**，包括那个"专门的 iOS 模拟器 MCP"
（`mcp__Claude_Code_iOS_Simulator__control` 的 screenshot / tap / swipe）、
computer-use、claude-in-chrome。**默认一律不用。**

| 事情 | 谁来做 |
|---|---|
| 写代码、编译 `xcodebuild` | **你** |
| 装机 `xcrun simctl install/launch` | **你**（命令行，不费 token） |
| 看日志、查数据库、`curl` 验接口、拉真数据预演 | **你**，而且**一个都不要省** |
| **在界面上点、截图看效果** | **用户**。你说清楚点哪里、看什么、什么算对 |

⚠️ **别重蹈 L126**：2026-08-04 我以"本环境有专门的模拟器工具，又快又便宜"为由绕过了这条规则
（还写进了 L100），2026-08-08 用户当场推翻 —— **那个工具同样费 token，截图是图片，每张都整个进上下文**。
判据：**规则的理由是"太贵"，换个工具不改变成本；理由没变，规则就没变。**

⚠️ **L100 里"自己截图看过"那半句已作废**，但它的内核（**改了界面不能靠猜、不能盲交**）继续有效 ——
只是验收的执行者是用户。交付时给一份**用户能照着做的清单**，不是"应该没问题"。

⚠️ **验收不了就明说**。别把"我觉得没问题"写成"已验证"（L114/L119 的老账）。

---

# ⚠️ 分支与回滚点（先跑 `git branch --show-current`）

```
design/custom-dock   ← 当前工作分支，已 push，最新 e0f99df00
design/soft-dock     稳定版：tag dock-system-glass 在这条上
main                 停在 tag genesis
design/soft-shell    被否决的设计师方案，留档别用
```

**三个回滚点，说哪个回哪个**：
- 「回到创世版本」→ `git checkout genesis`
- 「回到玻璃版」→ `git checkout dock-system-glass`
- **「回到上一轮之前」→ `9b18566dc`**（T51 第二批那 7 件的前一个）

---

# 🔧 手上有什么工具

## ① 两台模拟器

```bash
SIM26=A7B1AE1F-0391-4C3A-B979-FA35653256FF   # iPhone 17 (iOS 26.5)，用户那台，87 个源 + 真 API Key
SIM27=87C9AE05-88C0-44E6-A871-242FF782D949   # iPhone 17 (iOS 27.0)，空数据，随便点
```

⚠️ **仍然用 Xcode 26.6 编译**（`xcode-select` 别动），只把产物装到 27 上跑 ——
这样才和用户手机一致（app 用 26 SDK 编译、跑在 27 上）。

⚠️ **装机脚本认 UDID**（别再用裸 `booted`，两台同时开着会装错设备，L123）：
```bash
SIM_UDID=$SIM26 ./tools/install-to-simulator.sh
```
装 27（那台的 bundle id 是 `com.wenbopan`，不是 `com.ranchero`）：
```bash
BUILT=$(find ~/Library/Developer/Xcode/DerivedData/NetNewsWire-*/Build/Products/Debug-iphonesimulator -maxdepth 1 -name "NetNewsWire.app" -type d | head -1)
xcrun simctl install $SIM27 "$BUILT"
xcrun simctl launch  $SIM27 com.wenbopan.NetNewsWire.iOS-DEBUG
```

## ② 编译

```bash
xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build
```
⚠️ **编译和装机分两步跑，别用 `&&` 串** —— 编译失败会把旧产物装进去。

## ③ 真机（iOS 27）

```bash
DEV=B0E875BF-CAEA-549C-A020-1C01331F0DF3
BID=com.wenbopan.NetNewsWire.iOS-DEBUG      # 与手机上现有 app 同身份 = 覆盖升级，数据不丢
```
⚠️ 手机锁屏时编译和启动都会失败。⚠️ **动用户手机前先问。**

## ④ 看日志（本项目常用，埋探针必备）

```bash
xcrun simctl spawn $SIM26 log show --last 2m --info \
  --predicate 'category == "NNWTimelineExtras"' --style compact
```
⚠️ **必须带 `--info`**（甚至 `--debug`）—— 不带的话 `Logger.info` 根本不落盘，
你会以为"代码没执行"，其实只是没打印（2026-08-08 为此白查了一轮）。

---

# 📌 上一轮（T51 第二批）留下的两件悬案

## 1️⃣ 「点顶栏第二次回原位」没做成

「点顶栏第一次回顶 + 记原位」是好的，**第二次回原位**三条路全部实测失败：

| 试过什么 | 结果 |
|---|---|
| `scrollViewShouldScrollToTop` | ❌ 列表已在顶上时**系统压根不问** |
| 给 `navigationBar` 加点击手势 | ❌ 一次都没触发 |
| 给列表加点击手势 + 只收顶栏那一带 | ❌ 一次都没触发 |

病根：本 fork 的**头图浮层**（`TimelineFeedHeaderController` 的 overlay）铺满整页、
盖在列表之上，顶栏那一带的触摸先落到它身上就没了。
要做得从那一层下手（给 overlay 加手势 / 让它对那一带放行）——
**那是动"会飞的标题"那套机制，风险不小**。详见 **L125**。

## 2️⃣ `grok-build-0.1` 占了精选里 xAI 那一席

它比 `grok-4.5` 便宜（¥0.086 vs ¥0.23），所以按"该家最便宜的合格档"被选中。
名字看着像编程 / agent 专用线，但**没有数据能证实**，所以没擅自加规则。
要排掉的话：往 `OpenRouterCatalog.featuredSpecialistTokens` 里加 `"build"` 即可。

---

# 📋 更早还悬着的（都在 NOTES-todo 里，按需捡）

| 编号 | 事情 | 状态 |
|---|---|---|
| T43 | 陀螺仪驱动的边缘反光（dock 亮边跟手机倾斜转） | 🔵 用户提过，未做 |
| T46 | 深色下 dock 底板"有点过于透明" | 🔵 用户观察，未动 |
| T50 尾巴 | 齿轮左边那块圆角矩形残留（**iOS 27 独有**） | 🔴 未解决。下一步是**把 `toolbarItems` 整个打出来**，别再猜（已误判过一次，L123） |
| T45 | 切回 app 时选中胶囊变深色 | 🟡 已按机制修，等用户在 27 上确认 |
| T41 | `nnwEnableSoftBottomEdgeFade()` 是死代码 | 🟡 留着，别当成"渐隐的修法" |
| T13 | ACX 连续多图之间空隙偏大 | 未诊断 |

---

# 硬约束（最容易忘的）

- **一律中文回复，代码注释也用中文**（写给读不懂代码的用户看）
- **最高优先级是保持可 merge**：优先新增文件；改上游要最小化并带
  `[翻译]/[外观]/[管理]/[发现]/[链接]/[长图]/[品牌]/[阅读档]/[编辑]/[阅读位置]/[外文]` 标记
- **每次改完自己编译**（scheme `NetNewsWire-iOS`）
- ⚠️ **`Shared/` 会被扩展目标单独编译**，那里看不到 `iOS/` 的类型（L103）。
  尤其 **`Shared/Assets.swift` 被 Share Extension 点名单编**，别在里面引用 `iOS/` 下的东西
- ⚠️ **`Shared/SmartFeeds/`、`Modules/Account/` 是 A 级禁区**，一行都别改
  （要加智能源？看 `iOS/ForeignFeed/` 是怎么绕开的）
- ⚠️ **底部工具栏的 `toolbarItems` 结构不能动**：`expectedItemCount == 3` 的守卫 +
  `addNewItemButton` 是 IBOutlet 且上游往它身上挂 menu
- ⚠️ **改 `translation.js` 之后跑 `swift tools/check-js-syntax.swift`**
- ⚠️ **改翻译提示词要把 `TranslationCache.promptGeneration` +1**，否则旧译文一直从缓存跳出来
- ⚠️ **给 `OpenRouterCatalogModel` 加字段 → 缓存文件名要 +1**（现在是 v3），
  否则旧缓存整份解不出来、目录变空
- **commit / push 我说了才做**；记录文件和代码在**同一个 commit** 里（第 9 节）

---

# 反复咬人的判据

- **规则的"理由"和"当时的手段"要分开；理由没变，换工具不算解法**（L126）
- **钩子加完先埋一行日志确认它真的被调用了**；同一轮里两处改动都能解释同一个好结果时，必须分开验（L124）
- **系统"顺手给"的回调不一定每次都给**（L125/L118）
- **要么全归系统，要么全归我们，半分最贵**（L121）
- **结论要连着适用范围一起记；改了架构要回头查哪些旧决定的前提被作废了**（L122）
- **"我量到了" ≠ "我量的是它"**（L123）
- **排查"点不动"，第一问不是"我在不在最前"，而是"我的 `hitTest` 被调用了没有"**（L120）
- **解析成 CGColor 的颜色是隐性状态，谁负责在它过期时叫它重来？**（L119）
- **同一个地方反复出问题，先假设是同一个原因**（L117）
- **给已有函数加观察者/通知之前，先确认它幂等**（L113）
- **给浅色打的补丁，先问它在深色下是不是反的**（L112）
- ⚠️ **本 fork 已经把上游的标题机制整个换掉了（头图 + 会飞的标题）。
  凡是和"文章列表页标题"有关的活，第一站是 `TimelineFeedHeader.swift`，不是 `navigationItem`**

---

# 这一轮我想做的

（在这里写你要做的事。如果只是想让它先熟悉项目，就写「先读完上面那几份，然后告诉我你打算怎么做」。）
