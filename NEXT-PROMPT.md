我在继续 NetNewsWire iOS fork（Babel）的工作，项目在
`/Users/wenbopan/Downloads/RSS ai translation`

**请先按顺序读，读完再动手：**

1. `CLAUDE.md` —— 项目规则。**但第 0 节第 7 条已被下面的「工作方式更正」推翻**
2. `NOTES-progress.md` 最前面的「📍 接手须知」
3. `NOTES-todo.md` 的 **T51**（这一整轮要做的 7 件事，方案已和我逐条谈定）
   —— 顺带扫一眼 **T49 / T50**（iOS 27 模拟器怎么用、底栏控件那场仗的结论）
4. `NOTES-lessons.md` 的 **L118–L123**

---

## ⚠️ 分支与回滚点（先跑 `git branch --show-current`）

```
design/custom-dock   ← 当前工作分支，已 push，最新 commit 7cd77dcbb
design/soft-dock     稳定版：tag dock-system-glass 在这条上
main                 停在 tag genesis（这一整轮设计改动一行没进）
design/soft-shell    被否决的设计师方案，留档别用
```

**三个回滚点，说哪个回哪个**：
- 「回到创世版本」→ `git checkout genesis`
- 「回到玻璃版」→ `git checkout dock-system-glass`
- 当前 → `design/custom-dock`

---

# 🔧 这一轮开始前，先知道你手里有什么工具

## ① iOS 27 模拟器（2026-08-05 新装，这是最大的变化）

```bash
SIM27=87C9AE05-88C0-44E6-A871-242FF782D949   # iPhone 17 (iOS 27.0)，空数据，随便点
SIM26=A7B1AE1F-0391-4C3A-B979-FA35653256FF   # iPhone 17 (iOS 26.5)，有 87 个源的那台
```

⚠️ **仍然用 Xcode 26.6 编译**（`xcode-select` 别动），只是把产物装到 27 的模拟器上跑 ——
这样才和用户手机上的情况一致（app 用 26 SDK 编译、跑在 27 上）。
换成 Xcode 27 编译会改变系统控件外观，那是另一件事，要单独评估。

⚠️ **装机脚本认 UDID**（2026-08-05 加的闸门，别再用裸 `booted`）：
```bash
SIM_UDID=$SIM26 ./tools/install-to-simulator.sh          # 装 26（用户数据那台）
# 装 27（那台的 bundle id 是 com.wenbopan，不是 com.ranchero）：
BUILT=$(find ~/Library/Developer/Xcode/DerivedData/NetNewsWire-*/Build/Products/Debug-iphonesimulator -maxdepth 1 -name "NetNewsWire.app" -type d | head -1)
xcrun simctl install $SIM27 "$BUILT"
xcrun simctl launch  $SIM27 com.wenbopan.NetNewsWire.iOS-DEBUG
```
（两台同时开着时脚本会拦下并提示 —— 那是有意的，L123。）

## ② 真机（iOS 27）

```bash
DEV=B0E875BF-CAEA-549C-A020-1C01331F0DF3
BID=com.wenbopan.NetNewsWire.iOS-DEBUG      # 与手机上现有 app 同身份 = 覆盖升级，数据不丢

xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS -configuration Debug \
  -destination "platform=iOS,id=$DEV" build
xcrun devicectl device install app --device $DEV <产物路径>/NetNewsWire.app
xcrun devicectl device process launch --device $DEV --terminate-existing $BID
```
⚠️ **手机锁屏时编译和启动都会失败**（报 `Locked` / `device was not unlocked`）——要用户解锁。
⚠️ **动用户手机前先问。** 现在有 iOS 27 模拟器了，多数事情不必再上真机。

## ③ 工作方式（这个项目最贵的几条）

1. **视觉改动交付前必须自己截图看过**（L100）。本环境有模拟器工具，又快又便宜。
2. **深色模式是验收面积的另一半**（L112）。"做完"的定义里必须包含深色截一张。
3. **别目测，要采样**（L101/L104/L107/L109）。量圆要**横扫取最宽处**，别竖扫（量到的是弦）。
4. ⚠️ **"我量到了" ≠ "我量的是它"**（L123，当晚栽了两次）：
   - 量之前先确认**装的是不是你刚编的那份、在不在你以为的那台设备上**
   - 报告"修好了"之前先问：**我这个指标是不是直接测量了那个症状**？
     （那次用"外接框宽度"去回答"那块多余的东西还在不在"，被数字骗了）
5. **别猜，先埋日志**（L94）。而且要做**反向实验** + **回读确认真写进去了**（L115）。

---

# 🔴 这一轮要做的（7 件，方案已全部谈定，细节在 T51）

用户的原话：**「动手后一口气全部完成」**。上一轮已经把 #1 #8 #2 做完并验收，
剩下这 7 件是新功能 / 改交互，量大，请一次做完再交付。

| # | 事情 | 已定的关键决定 |
|---|---|---|
| 3 | 记住每个 feed 的滚动位置 | 按 feed 存**文章 ID**（不是像素）；点顶栏第一次回顶+记原位，第二次回原位 |
| 4 | 右滑回列表、左滑下一篇未读 | 前一页返回 nil；后一页=下一篇**未读**；没有时给彩蛋页「**没有下一篇啦！**」 |
| 5 | 智能 Feed 加「外文」 | **不改上游一行**（`smartFeeds` 是 var、`SmartFeedDelegate` 是协议，运行时追加）；**按源**判定语言 + 源设置里手动开关 |
| 6 | 长按菜单加「订阅源设置」 | 复用上游 `showFeedInspector(for:)`，改上游 3 行 |
| 7 | 模型菜单重做 | 精选=**按价格从低到高前 10**（排除 `:free`）+ 按厂商分组 + 搜索框 + 顶部余额 |
| 9 | 开关/控件接入主题色 | `window.tintColor` + `UISwitch.appearance().onTintColor`，换色重刷 |
| 10 | 文章列表页齿轮挡标题 | 齿轮+搜索合成**一个自绘双图标胶囊**（别退回让系统合并） |

**每一条的做法、已排除的路、以及要当心的坑，全写在 `NOTES-todo.md` 的 T51 里。**
下面只挑几条最容易踩的重复一遍：

- **#5 的禁区问题**：`Shared/SmartFeeds/` 是 **A 级禁区（绝对不碰）**。
  已找到不碰它的路（见 T51）。**别去改那些文件。**
- **#7 的余额接口**：`/api/v1/credits` 和 `/api/v1/auth/key` **都存在**（无 key 时 401 不是 404），
  但**没有用真 key 验过成功时的返回结构**。两个都试、解析不出来就**不显示余额**，
  **不要瞎猜一个数显示出来**。
- **#7 的价格**：OpenRouter `/api/v1/models` 有 400 个模型 / 58 个厂商，
  给的是 `pricing.prompt` / `pricing.completion`（**美元/token**）。
  用户要「≈¥X/篇」，按**真实翻译量**估（约 4000 token 进 + 4000 出），汇率写死在代码里并标明"估算"。
- **#9 的两个病根**（T40 早就记过的判据）：**(a) 用了 `Assets.Colors.*` 静态色板；
  (b) 上色写在只跑一次的地方**。设置页那些开关的 `onTintColor` 是**写死在 storyboard 里**的，
  源设置卡片那个绿的是**从没上过色**。全仓静态色板引用 33 处。
- **#10 和上一轮的改动方向相反**：上一轮为修「首页右上角变连体」加了 `sharesBackground = false`。
  #10 要的是**文章列表页**把两颗合成一个 —— 两个页面，范围不同，不冲突。
  ⚠️ 但**别退回让系统去合并**（系统材质在 26/27 上又是两副样子，上一轮绕了一整轮才统一），
  应当自己画一颗双图标胶囊。

---

# 硬约束（最容易忘的）

- **一律中文回复，代码注释也用中文**（写给读不懂代码的用户看）
- **最高优先级是保持可 merge**：优先新增文件；改上游要最小化并带
  `[翻译]/[外观]/[管理]/[发现]/[链接]/[长图]/[品牌]/[阅读档]/[编辑]` 标记
- **每次改完自己编译**（scheme `NetNewsWire-iOS`）
- ⚠️ **编译和装机分两步跑，别用 `&&` 串** —— 编译失败会把旧产物装进去
- ⚠️ **`Shared/` 会被扩展目标编译，那里看不到 `iOS/` 的类型**（L103）
- ⚠️ **底部工具栏的 `toolbarItems` 结构不能动**：`expectedItemCount == 3` 的守卫 +
  `addNewItemButton` 是 IBOutlet 且上游往它身上挂 menu
- ⚠️ **改 `translation.js` 之后跑 `swift tools/check-js-syntax.swift`**
- ⚠️ **改翻译提示词要把 `TranslationCache.promptGeneration` +1**，否则旧译文一直从缓存跳出来
- **commit / push 我说了才做**

# 反复咬人的判据

- **要么全归系统，要么全归我们，半分最贵**（L121）
- **结论要连着适用范围一起记；改了架构要回头查哪些旧决定的前提被作废了**（L122）
- **"我量到了" ≠ "我量的是它"**（L123）
- **排查"点不动"，第一问不是"我在不在最前"，而是"我的 `hitTest` 被调用了没有"**（L120）
- **借 X 的回调去读 Y 的状态：先量 (1) Y 变时 X 会不会响、(2) X 响时 Y 落定没**（L118）
- **解析成 CGColor 的颜色是隐性状态，谁负责在它过期时叫它重来？**（L119）
- **同一个地方反复出问题，先假设是同一个原因**（L117）
- **"让某个系统外壳消失"时，先想清楚那层外壳还顺带提供了什么**（L114/L116）
- **给已有函数加观察者/通知之前，先确认它幂等**（L113）
- **给浅色打的补丁，先问它在深色下是不是反的**（L112）
