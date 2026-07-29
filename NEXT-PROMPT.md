我在继续 NetNewsWire iOS fork(已改名 Babel)的工作。项目在 `/Users/wenbopan/Downloads/RSS ai translation`

**请先按顺序读这几份文件,读完再动手:**

1. `CLAUDE.md` —— 项目规则。特别注意第 0 节第 7 条(验收分工:你写代码/编译/装模拟器/看日志/查数据库,**界面点按验收交给我截图,不要用 computer-use 去点模拟器**)
2. `NOTES-progress.md` —— 只读第四节最前面的「📍 接手须知:2026-07-29」
3. `NOTES-todo.md` 的 **T30**(待验收)和 **T29**(已完成,含"别删的守卫")
4. `NOTES-lessons.md` 的 **L93–L98** —— 这六条全是前两天踩出来的,和接下来的工作直接相关

---

## ⚠️ 第一件事:让我验 T30(别急着做新功能)

发现页(搜索订阅源)有三条**已修但没被实测确认**的东西。请先让我验这三条:

1. 搜出结果之后,点「订阅到 / 文件夹」那一行 → **能不能弹出选单、选到某个文件夹**
2. 搜「klement」→ 那一行应该 **绿勾 + 文字偏灰 + 点不动**
3. 找一个没订阅过的源 → 订阅是否正常

**如果第 1 条还是不行:`NNWMenu.show` 里埋了一行诊断日志**(记"从第几层弹出、弹出者是谁"),
读日志定位,**不要靠猜** —— 上一轮已经在这里猜错两次了。

退路两条(T30 里写了):自己在底部摆一个搜索框,或者把搜索框放到表头(顶部)。
⚠️ 注意:**底部那个位置是 `UISearchController` 自带的,而"多余的那一层"也是它带来的** ——
两者是同一个东西的两面。我(用户)已经拍板:**要底部那个位置**。

---

## 然后:需求 2「每个源的设置页」

考古已经做完了,结论是**上游其实做好了一大半**:

- `Feed.readerViewAlwaysEnabled` **已经存在**(存在账户自己的数据库里,是 `Modules/Account` 的公开 API)
- 正文页 `WebViewController.setArticle` **已经在读它**,所以"自动进阅读视图"的逻辑不用写
- 上游还有一个 `FeedInspectorViewController`,**那个开关就在里面**,中文也翻好了(「始终使用阅读视图」)
- 现在从**编辑模式行尾的「⋯」→「源信息与设置」**就能打开它

**所以第一个设置项可能已经能用了 —— 先让我试一下再说要不要做。**

真正要做的是:上游那页是英文 storyboard 拼的,以后加"这个源的字体大小"之类要动 storyboard,
merge 风险高。建议**新建一个 fork 自己的「源设置」页**(暖纸风、中文、纯代码,
照 `Shared/Translation/TranslationAPIKeyViewController.swift` 的模板),
但**第一个设置项仍然读写上游那个字段**(白拿:删源时上游自动清理、OPML 导入认它、跨账户天然不撞键)。

以后加上游没有的项(字体大小等)再建 fork 自己的存储,**键必须带账户前缀** ——
现有的 `FeedOrderStore` 就是反面教材(它没带,两个账户里同名文件夹会共用设置)。

**顺带该修的一个现成 bug**:`WebViewController` 每次渲染完都把当前状态写进「按文章记忆」
(上限 500 篇,LRU 淘汰)。一旦某个源开了"总是阅读视图",它的每篇文章都会占一条,
很快把 500 条刷满、挤掉别的源的记忆。加设置页之前应该先加一句
"源已开全局开关就别记单篇"。

---

## 我的环境(很重要)

- **真机是 iOS 27 developer beta 4**,而开发机的 SDK 和模拟器都是 **iOS 26**。
  所以涉及转场/布局的改动,**你那边"模拟器通过"参考价值有限,必须让我在真机上看**。
- 我有 **84 个订阅源、7 个文件夹**。凡是"要拖很久""要滚很多屏"的设计,先想想这个规模。

## 硬约束(都在 CLAUDE.md 里,这里只列最容易忘的)

- **一律中文回复,代码注释也用中文**(写给读不懂代码的我看)
- **最高优先级是保持可 merge**:优先新增文件;改上游要最小化并带
  `[翻译]/[外观]/[管理]/[发现]/[链接]/[长图]/[品牌]/[阅读档]/[编辑]` 标记
- **每次改完自己编译**:`xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build`
- **装模拟器只用 `./tools/install-to-simulator.sh`**;装机后等几秒 → 确认进程活着 → 查
  `~/Library/Logs/DiagnosticReports/NetNewsWire*.ips` 无今日新崩溃
- ⚠️ **编译和装机分两步跑**,别串成 `xcodebuild ... && 装机`(`&&` 判断的是前一条的退出码,
  编译失败会把旧产物装进去)
- **push 我说了才做**

## 这个项目反复验证有效的排查方法

- **改了没生效时,第一件事是证明"跑的确实是新代码"**,而不是查逻辑(L41)
- **别猜,埋日志**:交互类 bug 猜三轮不如埋一轮日志。埋的时候**把相关状态一次打全**,
  信息量最大的往往是"你以为不用看的那个"(L94)
- **能抽成纯逻辑的部分自己先离线验**:仓库里有两个现成的仿真脚本,改了对应规则**必须重跑**:
  - `swiftc -o /tmp/sim-dropzone "iOS/FolderManager/DropZoneResolver.swift" "tools/sim-dropzone.swift" && /tmp/sim-dropzone`
  - `swiftc -o /tmp/sim-feedorder "iOS/FeedListEdit/NNWFeedOrderMath.swift" "tools/sim-feedorder.swift" && /tmp/sim-feedorder`
- **交付前跑一轮独立审查**:前三次分别抓到 5 / 8 / 3 个真 bug,其中好几个是"不进那个模式也会坏"的
- **一个修法开始在下游长出新症状,说明它引入的不是修复,是耦合**,该停下来消掉前提(L96)
