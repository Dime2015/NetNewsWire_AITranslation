我在继续 NetNewsWire iOS fork（Babel）的工作，项目在
`/Users/wenbopan/Downloads/RSS ai translation`

**请先按顺序读，读完再动手：**

1. `CLAUDE.md` —— 项目规则。**但第 0 节第 7 条已被下面的「工作方式更正」推翻**
2. `NOTES-progress.md` 最前面的「📍 接手须知」
3. `NOTES-todo.md` 的 **T40**（这一整轮设计换血的来龙去脉、已完成、已知未做）
4. `NOTES-lessons.md` 的 **L100–L114** —— 这 15 条全是这一轮踩出来的，和接下来的活直接相关

---

## ⚠️ 开工前先确认分支

```
main                停在 649f85fd5 = tag genesis（回滚点，这一轮一行没进）
design/soft-dock    ← 当前工作分支，40 个提交，已 push 到 origin
design/soft-shell   被否决的设计师方案，留档别用
```

`git branch --show-current` 应该是 `design/soft-dock`。

## ⚠️ 工作方式（这一轮最贵的两条教训）

1. **视觉改动交付前必须自己用 iOS 模拟器截图看过**（L100）。本环境有专门的模拟器工具
   （截图 + 按坐标点按），又快又便宜。CLAUDE.md 里"别用操作电脑验收"那条针对的是
   通用 computer-use，不适用。
2. **深色模式是验收面积的另一半，不是"配色的另一档"**（L112）。
   这一轮我提醒了用户四次"深色还没验"，自己一次没验，结果被用户一口气指出三处丑。
   **"做完"的定义里必须包含深色截一张。**

配套工具（scratchpad 里，会话结束就没了，可按需重建）：
- `xcrun simctl io booted screenshot x.png` 取图
- 一个 30 行的 Swift 取色/测量工具：按坐标打印色号、找边缘、量包围盒
  （**视觉的事别目测，要采样** —— L101/L104/L107/L109）

---

# 🔴 第一件事：底栏「边缘渐隐」还没修好

**现象**（用户 2026-08-05 在 **iOS 27 beta 真机**上）：
底栏是毛玻璃了，但**内容滚到栏附近没有那道柔和的渐隐**，是硬切断。
**创世版（genesis）里这个地方是好的。**

**已经查清的原因**：iOS 26 起滚动视图与栏交界处有系统画的渐隐。
创世版有，是因为那时工具栏用的是**系统自带的底**；
而这一轮为了让 dock「浮」起来，在三处调了 `configureWithTransparentBackground()`
把栏拍平 —— **那道渐隐是随着栏的底一起被拍掉的**。

**❌ 已经试过、不管用的做法（别再走）**：
给滚动视图设 `bottomEdgeEffect.style = .soft` / `isHidden = false`
（`UIScrollView.nnwEnableSoftBottomEdgeFade()`，接在首页 / 文章列表页 / 正文页三处）。
用户实测**仍然没有渐隐**。
原因判断：`bottomEdgeEffect` 是**滚动视图自己的**属性，
而系统并不知道我们那块**浮在上面的自绘 dock** 需要它让路。

**✅ 下一步该试的（已在 SDK 里确认存在，iOS 26+）**：
`UIScrollEdgeElementContainerInteraction`（`UIKit/UIScrollEdgeElementContainerInteraction.h`）。
头文件原话：*"Add this interaction to a container view of views that overlay the edge of
a scroll view."* —— 正是我们这个场景。用法：

```swift
let interaction = UIScrollEdgeElementContainerInteraction()
interaction.scrollView = <这一页的滚动视图>
interaction.edge = .bottom
<装着 dock 的容器视图>.addInteraction(interaction)
```

要接的三处容器与滚动视图：

| 页面 | 容器（浮着的那层） | 滚动视图 |
|---|---|---|
| 首页 | `navigationController?.toolbar` | `collectionView` |
| 文章列表页 | 同上 | `collectionView` |
| 正文页 | 同上 | `WebViewController` 里的 `webView.scrollView`（**private，只能在那个类内部接**） |

⚠️ **正文页那处上一轮插错过两次**：`WebViewController.webView` 是 private，
从 `ArticleViewController` 够不着；能拿到它的地方是
`WebViewController.nnwUseUIKitPaperBackground(_:)`。

**⚠️ 一个必须先做的隔离实验（一轮编译就能定性，别跳过）**：
把 `NNWSoftMaterial.isEnabled` 设成 `false`（或单独让 `nnwUseFloatingToolbar` 不生效），
装机看渐隐**是不是回来了**。
- 回来了 → 确认病根就是"拍平工具栏"，然后用上面那个 interaction 补回来。
- 没回来 → 说明我这条因果链判断错了，**别在这条路上继续改**，重新查。

（这一轮我在**没做这个实验**的情况下直接改了两版，两版都没修好 —— 先定性再动手。）

**⚠️ 无法自测的部分要说清楚**：开发机 SDK 与模拟器都是 **iOS 26**，
用户真机是 **27 beta**。这个项目已经在同一件事上栽过（L94/L95：搜索栏摆法）。
所以：**26 上验完只能说"不坏"，27 必须让用户验**，别声称修好了。
如果最后 27 上仍然不行，**兜底方案**是"消掉机制"（L92 的老规矩）：
撤掉 `configureWithTransparentBackground()`、让系统工具栏恢复自带的底 ——
代价是 dock 回到"胶囊套在栏里"的双层观感，**但那正是创世版的样子，而用户说创世版是好的**。

---

# 接下来的待办（按建议顺序）

## 2. 底部控件进/回页面时慢 0.5–1s 才出现

用户 2026-08-05 报，**一直没做**。⚠️ **别猜，先埋日志**（L94）：
在 `viewWillAppear` / 装配完成 / 图片画完各打一条时间戳，先证明时间花在哪一段。

我的怀疑（**不是结论**）：
- `NNWSoftMaterial.roundButtonImage` **每次调用都现画位图**（`UIGraphicsImageRenderer`
  × 2 颗圆钮 × 每次 `viewWillAppear`），**没有缓存** —— 这条最可疑，因为烘焙圆钮
  就是这一轮加的，而用户说的"现在"很可能就是指这一轮之后。
  修法：按 (图标, 尺寸, traits, 强调色) 做个缓存。
- 三档控件是在 `viewWillAppear → nnwUpdateReadingMode` 里装的，不是 `viewDidLoad`
- ★ 档要等 `NNWStarredIndex` 异步查库（L53）

## 3. 深色模式还没走过的页面

这一轮只在深色下验过：首页底栏、文章列表页、文章页 dock、文件夹行。
**没验过**：自绘选单、设置页、发现页、试读页、编辑模式。
⚠️ 选单也吃那层"提亮补丁"，按 L112 的经验大概率有同类问题。

## 4. 四颗底栏圆钮仍不透明

中间三档那条是真磨砂、两侧圆钮是烘焙的不透明图片，并排看得出来。
改成 customView 就能解决，但要自己转发 `menu`（首页的 `+` 是 IBOutlet 且上游挂了 menu）
和 `isEnabled`（三处上游在写）—— 换掉会**静默**丢功能，风险在这里。
✅ 好消息：尺寸已经不是障碍了（实测图片是 1:1 渲染、没有上限）。

## 5. 选单图标还是 SF Symbols

参考图那套是手绘的圆头粗笔画（笔画占比 11.6%），SF Symbols 顶到 `.bold` 也只有 10.5%，
风格上一眼认得出不是一家。要对上得整套手绘 15–18 个图标。**用户没催，优先级最低。**

---

# 硬约束（CLAUDE.md 里都有，这里只列最容易忘的）

- **一律中文回复，代码注释也用中文**（写给读不懂代码的用户看）
- **最高优先级是保持可 merge**：优先新增文件；改上游要最小化并带
  `[翻译]/[外观]/[管理]/[发现]/[链接]/[长图]/[品牌]/[阅读档]/[编辑]` 标记
- **每次改完自己编译**：
  `xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build`
- **装模拟器只用 `./tools/install-to-simulator.sh`**
- ⚠️ **编译和装机分两步跑**，别用 `&&` 串（编译失败会把旧产物装进去）
- ⚠️ **`Shared/` 会被扩展目标编译，那里看不到 `iOS/` 的类型**（L103）
- ⚠️ **底部工具栏的 `toolbarItems` 结构不能动**：有 `expectedItemCount == 3` 的守卫，
  且 `addNewItemButton` 是 storyboard 的 IBOutlet。只能换 `image` 和 `tintColor`
- **push 我说了才做**

# 这一轮新增的、反复咬人的判据

- **改一个显示值之前，先数清楚它有几个写入点**（L74 老账，这一轮又咬两次：
  文件夹颜色、分组头三角）
- **给已有函数加观察者/通知之前，先确认它幂等** —— 加触发源的人往往没意识到
  自己把"只跑一次"变成了"跑很多次"（L113，底栏圆钮糊成纯色就是这么来的）
- **给浅色打的补丁，先问它在深色下是不是反的**（L112，52% 的白在深色下是"刷白"）
- **"让某个系统外壳消失"时，先想清楚那层外壳还顺带提供了什么**（L114，
  拍平工具栏顺带丢了边缘渐隐 —— 就是第一件事那个 bug）
- **量圆的直径要横扫取最宽处，别竖扫**（L109，竖扫量到的是弦，会低估）
- **"换主题色跟不上"到目前为止只有两种原因**：(a) 用了 `Assets.Colors.*` 静态色板；
  (b) 上色写在只跑一次的地方
