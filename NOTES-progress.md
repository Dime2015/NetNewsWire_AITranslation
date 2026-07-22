# NOTES-progress.md — 项目进度与交接

> **这是接手本项目的第一份必读文件。**
> 读完本文件,你应该知道:项目做到哪了、哪些已验证、哪些悬而未决、下一步是什么。
> 配套文件:`CLAUDE.md`(规则) → `NOTES-architecture.md`(代码考古) →
> `NOTES-lessons.md`(踩过的坑,41 条) → `NOTES-todo.md`(已知问题) →
> `NOTES-i18n.md`(多语言工程手册)。
>
> ⚠️ **动手前务必先看 CLAUDE.md 第 0 节第 7 条**:
> **不要用「操作电脑」去点模拟器做验收**(2026-07-21 用户明确要求,太慢太费)。
> 编译、装模拟器、看日志、查数据库照旧由你做;**界面上的点按与验收交给用户截图**。
>
> **维护纪律(对任何接手的 AI):每完成一个可验证的步骤、每做一个重要决定、
> 每发现一个坑,立刻更新对应文件。不要攒到最后。** 详见 CLAUDE.md 第 9 节。

最后更新:2026-07-22

---

## 一、项目一句话

给 NetNewsWire iOS 版加一个「翻译成中文」按钮,直连 OpenRouter(OpenAI 兼容格式),
分组并行翻译、逐块显示、本地缓存;并把 iOS 界面完整汉化。
fork 自上游 `Ranchero-Software/NetNewsWire`,必须长期保持可 merge
(最高优先级约束,见 CLAUDE.md 第 2 节)。

## 二、阶段进度

| 阶段 | 状态 | 说明 |
|---|---|---|
| 第 0 步 环境跑通 | ✅ | Xcode 26.6 / iPhone 17 模拟器 / scheme `NetNewsWire-iOS` |
| Phase 0 代码考古 | ✅ | `NOTES-architecture.md`,7 个问题全部回答并经用户确认 |
| Phase 1 服务接口 + mock | ✅ | `TranslationService` 协议 + `MockTranslationService` |
| Phase 2 iOS 翻译按钮 | ✅ | 路线 B(JS 原地替换正文),用户 5 项验收通过 |
| Phase 3 直连 OpenRouter | ✅ | 分组并行 + 缓存 + 设置界面,经用户多轮实测 |
| 界面汉化 | ✅ | 436 条字符串 + 5 个 storyboard,iOS 侧全覆盖 |
| Phase 4 macOS 移植 | ❌ | 默认不做,仅当用户明确要求 |
| 界面:换 app 图标 | ✅ | 三套素材(浅/深/单色),三种主屏外观实测通过 |
| 界面:**文章列表**改 Reeder 式 | ✅ | favicon + 三段文字 4 行 + 右侧缩略图 + 整行浓淡,用户已验收 |
| 界面:**阅读视图**能用了 | ✅ | 换成本机 Readability.js,不再依赖 Feedbin 密钥 |
| 界面:**正文阅读页** | ✅ 第一轮 | 图片四桶规则+图注+作者名层级+正文元素全套,2026-07-21 用户验收 |
| **订阅发现页**(搜索并添加内容源) | ✅ | 播客 / Reddit / YouTube / 网站四类,`+` 直接进入 |
| **播客语音条 + 跳 Podcasts** | ✅ | 音频走 feed,跳转走 iTunes |
| **YouTube 正文播放器 + 简介** | ✅ | 修掉「错误代码 152」,见 L37 |
| **app 改名 Babel** | ✅ | 只改显示层;改名基础设施 `i18n/rebrand.py` |
| **装到真机** | ✅ | 免费 Personal Team 实测可签,**App Groups 未报错**;7 天过期,见 T18 |
| **翻译体验优化(本轮 2026-07-22)** | ✅ 用户验收 | ①长文对冲压尾延迟 ②长按重翻整篇 ③记住并自动恢复 阅读/翻译 状态 ④点翻译滚到开头 ⑤失败/未配置弹提示 |

## 三、git 状态(2026-07-22)

**工作区干净。本地领先 GitHub(origin/main)1 个提交**,需要时 `git push`。
(此前那批提交已在 GitHub 上;这次翻译体验优化是新增的这 1 个。)

```
5fb5fba33  [翻译][状态记忆] 翻译体验五项优化 + 失败提示 + 装机脚本加固  ← 本轮 2026-07-22
```

在此之前(界面改造那一轮)的提交,从新到旧:

```
02dff2746  [品牌] app 显示名改为 Babel,并建立可复用的改名基础设施
5eb01e408  [发现] 搜索页收敛:统一右上角、加「全部」自动识别、+ 直接进页面
c4a093fcf  [界面] 「新建文件夹」从 + 操作单移到账户分组头右侧
60e19ed13  [YouTube] 正文嵌播放器 + 视频简介,并修掉「错误代码 152」
65f7cbd8a  [发现] Phase B(YouTube / 网站)+ [播客] 正文语音条与跳转 Podcasts
c7649020d  [发现] 订阅发现 Phase A:app 内搜索并订阅播客 / Reddit
95cf73af9  [界面] 正文阅读页第一轮:图片、图注、作者名层级、正文元素样式
55eae14f1  [文档] 本轮收尾:进度整理 + 新增「不要用操作电脑做验收」规则
5e66bf541  [界面] 藏掉 Substack 的图片按钮,并把「点图片」还给全屏查看器
e3069a2a6  [阅读视图] 改为本地 Readability.js,不再依赖 Feedbin
0f5d5f124  [界面] 列表两处修正:单个源里显示 favicon、时间靠右且缩略图垂直居中
7473021f8  [界面] 文章列表改为 Reeder 式布局
18b5571c0  [界面] 更正:图标跟随深浅色本来就正常,是我漏看了「始终/自动」子选项
e5c625b78  [界面] 查清图标不跟随深浅色(此结论后被 18b5571c0 更正)
355d14698  [界面] 记录模拟器实用操作
9aec0c2bf  [界面] 图标改用三套独立素材(浅色/深色/单色)
91f42afb6  [界面] 换用满铺无边框的图标素材,修掉框里套框
affb0b493  [界面] 换成用户提供的报纸 R 图标
62e75ba79  [界面] external resources/ 加入 .gitignore
eaf0bea0a  [界面] 铺好文章列表与正文页的改动通道,界面零变化
31c55467f  [翻译] 交接文档补齐至最新,并记录真机安装的前置条件
```

在此之前的历史:

```
078023a99  三项完善:活化石改名、API Key 连通性测试、模型榜单刷新
cc2862501  汉化阶段 2:Feed 术语保留英文、修复设备变体、四个 storyboard 本地化
394698eab  界面汉化阶段 1:436 条字符串 + 语言切换 + 可复用 i18n 流水线
d020944fb  修复工具栏胶囊粘连:三组改为两组
6d3af854c  修复:customView 按钮被压成 0 宽后永久消失
52946ded5  Phase 3 完成:直连 OpenRouter 分组并行翻译 + 设置界面 + 本地缓存
7cce26cd1  修订 CLAUDE.md:方案由自建后端改为直连 OpenRouter
15191e95a  修复:用按钮切换文章时翻译按钮状态不重置
545f63678  Phase 2 完成:iOS 文章页加入翻译按钮
c46d1ce8c  Phase 0 考古笔记 + Phase 1 接口与 mock
3cc360839  填入已验证的 iOS scheme、模拟器型号与首次编译踩坑说明
08d10f501  ← 上游基线 commit
```

## 四、当前悬而未决(接手者先看这里)

### 🚧 界面重做成 Reeder 式暖色风格(2026-07-22 开始,分页推进中)

**目标**:参照 Reeder(用户在 `external resources/screenshots/` 放了参考图,含
`设置界面.PNG` 明确写着 "About Reeder"),把 app 做成**暖色纸张背景、无边界、无色块**的风格。
**分步做,每页验收后再下一页**;圆形图标等元素用户还在考虑,先只做配色。

**取色(命令行从截图取样,不是肉眼)**:浅色纸张 `#F3F0EB`、深色 `#1E1E1E`。
用户明确要求:**整片无边界、无颜色分野**(不要卡片色块、不要行分隔线)。

**基础设施(用户要求:以后换色只改一个地方)**:新增 `iOS/Appearance/AppAppearance.swift`,
`AppAppearance.paperBackground` 是唯一的暖纸色(动态 UIColor,自动跟随深浅色)。
各页都指到它。**下一步扩成一个完整调色板**(把文字色、强调色等语义色都收进来),
真正做到"动一个色号全变"。

**✅ 已完成并验收:订阅列表页(MainFeed)**。关键手法(见教训 L44/L45):
- 列表底色必须设 **`config.backgroundColor`**(不是 `collectionView.backgroundColor`——
  系统列表有自己一层底色会盖过它),这才消除"卡片 vs 边距"的色差;
- 行分隔线在 `itemSeparatorHandler` 里关(它覆盖 `showsSeparators`);
- cell / folder cell / 分组头非选中态背景抹成暖纸色;
- **不要**用全局 `UINavigationBarAppearance` 铺色——会把大标题+iOS 26 副标题冲掉;
  导航栏保持系统默认透明,透出下面已变暖的列表即可。

**🔜 待做的页(照搬同一套手法)**:文章列表(时间线,`.plain` 列表,同样要
`config.backgroundColor`)、设置页、添加订阅页、账户页;正文阅读页是 WebView,
走它自己的样式层(`nnw_appearance.js`)单独对齐。

**改动文件**:新增 `iOS/Appearance/AppAppearance.swift`;改
`iOS/MainFeed/MainFeedCollectionViewController.swift`(config.backgroundColor + 关分隔线)、
`MainFeedCollectionViewCell/FolderCell/HeaderReusableView.swift`(非选中态暖底),均带 `[外观]` 标记。

### ✅ 翻译体验五项优化:已完成并经用户验收(2026-07-22)

用户真机用下来提的四点 + 一个追加,都已实现、双平台编译过、装模拟器验收。
**改动只在:`translation.js`、`TranslationController.swift`、`ArticleViewController.swift`、
`WebViewController.swift`,加新文件 `ArticleReadingStateStore.swift`。上游两文件几乎全是追加
(ArticleViewController +40/-0,WebViewController +43/-1,那 -1 是给 setArticle 判断加了个「或」)。**

1. **① 长文开头不再干等 —— 对冲请求压尾延迟**(`TranslationController.hedgedTranslate`)。
   现有设计本来就先翻「先导块(标题+前一两段)」,慢是因为它是**单个阻塞请求卡在关键路径**,
   撞上慢服务商就 30s+(T5 尾延迟)。对冲:某请求超过阈值没成功就并发补发一份,谁先回用谁。
   先导块固定 4s 阈值;正文各组按大小估(200 字符/秒 ×2,下限 6s)。用户选了「开头+全文各组都对冲」。
   分组/术语一致性策略**一点没动**。日志 `对冲触发` 可看成本。详见 T5。
2. **② 长按翻译键 → 确认后重翻整篇**(`forceRetranslate` + `performToggle(force:)`)。
   **只对已有完整缓存的文章**长按才弹确认框;确认后跳过缓存、从原文重翻并覆盖。
   没缓存长按不反应。长按手势与单击共存(`ArticleViewController.handleTranslationLongPress`)。
3. **③ 记住并自动恢复 阅读模式 / 翻译 / 两者叠加**(新增 `ArticleReadingStateStore.swift`)。
   按单篇文章存 `{阅读模式, 已翻译}` 两个 bit(UserDefaults,LRU 上限 500)。
   - **翻译只在本地有匹配缓存时才自动秒显**(用户明确选择:**没缓存不自动联网重翻**,
     停在原文等点,免得打开老文章悄悄花钱)。
   - 阅读模式:在上游 `setArticle` 的 `readerViewAlwaysEnabled` 判断上加「或本篇记得开阅读模式」。
   - 记录时机:翻译状态在 `TranslationController` 的几个结算点写;阅读模式在
     `WebViewController.didFinish`(渲染出**最终内容**那次,gate 掉 loading 页)按
     `isShowingExtractedArticle` 真实值写 —— **不用** `articleExtractorButtonState` 的 `.off`,
     因为切文章时 `stopArticleExtractor()` 会对**旧文章**误发 `.off`(会污染旧文章记忆)。
   - 自动恢复触发:`didFinish` → `nnwRecordAndAutoRestoreOnDidFinish()` →
     `(delegate as? ArticleViewController)?.nnwAutoApplyTranslationFromCacheIfNeeded()`
     (故意用 cast,不动上游 `WebViewControllerDelegate` 协议)。
   - 已知小限制见 **T19**(feed 版/reader 版译文共用一个缓存键会互相顶)、**T20**(阅读模式每次重抓网页)。
4. **④ 点翻译自动滚到开头**(`translation.js` 的 `scrollToTop` + 桥接)。
   凡「要显示译文」(含缓存秒显、强制重翻)都先滚到顶;**切回原文不滚**(可能在读)。
5. **⑤ 失败/未配置弹提示,不再静默感叹号**(`presentError` 回调 + `presentTranslationError`)。
   根因是 `lastErrorMessage` 一直只写不读(教训 L43)。**未配置**在点击入口就直接弹
   "请前往设置中填写 API 并选择翻译模型",且**不再变感叹号**;网络/服务器等硬错误在 catch 里弹;
   **自动恢复等后台流程静默**,不弹。

**同轮加固**:`tools/install-to-simulator.sh` 原来的「防假安装」`cmp` 只比 57KB 主 stub,
漏了真正装代码的 `NetNewsWire.debug.dylib`(教训 L42)。已改为两者都比,任一不一致就整目录覆盖。

⚠️ **两条硬约束仍然有效**:自动恢复只在有缓存时应用译文;`performToggle` 只由用户点击/长按触发,
所以它里面弹窗一定是用户发起的(自动恢复走的是另一个方法 `autoApplyTranslationFromCacheIfNeeded`,不弹)。

### ✅ 正文阅读页第一轮:已完成并经用户验收(2026-07-21 晚)

全部改动在 `Shared/Appearance/nnw_appearance.js` 一个文件里(上游零改动),要点:

1. **图片四桶规则** —— 按图片自身宽高分桶,与订阅源无关,任何图必落一桶(教训见 L31):
   - 宽 <100px:行内小图标,不动
   - 竖图(高>宽):独占一行居中,最宽 85%、最高 62vh
   - 横图且原图宽 ≥ 屏宽 85%:左右顶到屏幕边(负 margin 抵掉 body padding;
     padding 是运行时量出来的,不是写死 20)
   - 其余横图:独占一行居中、保持原大小(**不放大,放大会糊**)
   - 尺寸优先读 HTML 的 width/height 属性(实测 78% 的图有,不用等下载),
     没有的等 load 事件读 naturalWidth
   - **实现不碰文章 DOM**:JS 只读尺寸,把结论写成 `img[src="…"]` 规则追加进
     `<head>` 里第二张样式表(id=nnwAppearanceImageRules)。翻译整段替换正文后,
     规则按图片地址照样命中,不需重扫
2. 图注 `figcaption`:靠右、淡色(自定义 `--nnw-secondary-text`,深浅色自适应)、
   0.82em;图注里的链接一并压灰
3. 顶部层级:`.header` 整块 0.8em+淡色,`.feedlink` 放大回 1.25em ——
   净效果=只有作者名变小变淡;作者名若是链接也压灰
4. 装图片的段落抹平源站写死的左右 padding(`p:has(> img)`,必须 `!important` 盖行内样式)
5. 正文元素全套:行高 1.65(**无单位**,带单位会把像素传给子元素)、段距 1.15em、
   小标题 1.32/1.20/1.08/1em + 上疏下密 + **`:empty` 藏空标题(mjtsai 每篇都有空 `<h4>`)**、
   引用块竖线 2px(**引用文字有意不调淡** —— mjtsai/Daring Fireball 这类源引用就是正文)、
   代码块 12/14px 内边距 + `pre code` 去嵌套底色、列表缩进 1.5em、`hr` 细线、表格 0.9em

验收:The Conversation、3QD 横竖图、ACX 小图、mjtsai、Liberty Street(BibTeX 代码块)、
Julia Evans(h4)、Experimental History(正文 h1)均通过。

⚠️ 两条硬约束(继续有效):
1. **不要动 DOM 结构** —— `#bodyContainer`、`.articleTitle` 是翻译功能的命脉(L12)
2. **不要拆图片外面的 `<a>`** —— 系统长按菜单靠它才存在(见 T12)

**iOS 没有正文字号滑块**(那是 macOS 专属),正文字号跟随系统动态字体;
要固定就在这层 CSS 里覆盖(见 L23 末尾)。

### ✅ 订阅发现 Phase A:已完成并经用户验收(2026-07-21 深夜)

**入口**:订阅列表页右下角 `+` → 操作单第三项「搜索订阅源」。
**上游改动只有一行**(`MainFeedCollectionViewController.add(_:)` 里调我们的扩展)。

⚠️ **为什么入口不做成工具栏按钮**:底部工具栏在故事板里正好 3 项,而
`configureToolbarWithProgressView()` 里有 `guard items.count == 3 else { return }` ——
加第 4 个按钮会让**刷新进度条静默消失**。详见 CLAUDE.md「D 级 · 订阅发现专用」。

**新增文件(全在 `Shared/Discovery/`,上游不存在此目录)**:

| 文件 | 职责 |
|---|---|
| `FeedSearchResult.swift` | 统一的搜索结果模型 + 会说人话的错误定义 |
| `PodcastSearcher.swift` | iTunes Search API(苹果官方,不要 key,直接返回 feedUrl) |
| `RedditFeedBuilder.swift` | 版块名解析 + 拼 .rss 地址,**全本地零网络请求**(原因见 L33) |
| `FeedDiscoveryViewController.swift` | 搜索页(iOS only) |
| `MainFeedCollectionViewController+Discovery.swift` | 往 `+` 操作单挂一项 |

**复用的上游现成件(它们本身零改动)**:`Account.createFeed(...)`、
`AddFeedFolderViewController`(选文件夹)、`AddFeedDefaultContainer`(记住上次的文件夹)、
`account.hasFeed(withURL:)`(查重)、`.UserDidAddFeed` 通知。

**本轮踩的两个坑,都已修复并记进教训**:
- L33 — Reddit 429 被上游报成「feed 不存在」;我多打的那次「验证」请求是帮凶,已删
- L34 — Reddit 正文是「一行两格表格」,图文并排不是样式问题;已按结构特征堆叠

### ✅ 订阅发现 Phase B + 播客语音条:已完成并经用户验收(2026-07-21 深夜)

**Phase B —— 搜索页补齐到四栏**

| 栏 | 做法 | 新增文件 |
|---|---|---|
| YouTube | 拉一次频道页抠 `channel_id`,拼官方 RSS。网址里已带 id 就不联网 | `YouTubeFeedResolver.swift` |
| 网站 | **刻意只补全 `https://`,不自己找 feed** —— 上游 FeedFinder 本来就做全套发现 | `WebsiteFeedResolver.swift` |

抓 YouTube 频道页用**桌面浏览器 UA**(和抓 feed 相反,见 L33 末尾):
那是普通网页不是 feed,非浏览器 UA 会拿到精简页面,里面没有那个 id。

**播客语音条 + 跳转 Apple Podcasts**(新增 `Shared/Podcast/`)

| 文件 | 职责 |
|---|---|
| `PodcastEpisodeLocator.swift` | 按需重拉 feed → `FeedParser` 解析 → 按 guid 找这一集的 enclosure。按 feed 缓存,**含负缓存** |
| `ApplePodcastsLinkResolver.swift` | iTunes 搜节目(**用 feed 地址比对确认**)→ 列单集 → `episodeGuid` 匹配 → 深链 |
| `nnw_podcast.js` | 往页面插语音条 |

关键设计,改动前务必先读:

- **音频走 feed,跳转走 iTunes**。iTunes 的 `episodeUrl` 是**试听片段**(见 L36)
- **音频地址数据库里没有** —— 上游解析了 enclosure 但 Article 模型没这字段、
  建库脚本还 DROP 了 attachments 表。绕路重取,C 级禁区零改动(见 L35)
- **播放器插在 `#bodyContainer` 外面**(是它的兄弟节点)。插里面会被
  `translation.js` 当成正文的一段拿去翻译

**上游改动**:`WebViewConfiguration.swift` 脚本清单加一个词;
`WebViewController.swift` 的 `didFinish` 里加一行 + 末尾追加一个扩展
(扩展必须写在该文件内,因为 `webView` 属性是 private)。

**已知限制(不是 bug)**:
1. **时长不显示** —— 上游解析 enclosure 时把 `durationInSeconds` 写死为 `nil`
2. **切后台音频会停**,无锁屏控件(WKWebView 的限制)。语音条定位是"试听"
3. 某播客第一篇文章会慢 1~2 秒(拉 feed,Exponent 的 767 KB),同会话内之后免费
4. 私人/付费 feed 不在苹果目录里 → 跳转链接静静地不显示

**Phase C**:用户明确说「A/B 用完再说」,暂不列入计划。

### ✅ YouTube 正文播放器 + 视频简介:已完成并经用户验收(2026-07-21 深夜)

**播放器**(`Shared/YouTube/nnw_youtube.js`,纯 JS,不需要 Swift):
视频 ID 直接从页面里的文章链接读(模板把 `[[preferred_link]]` 放进了标题和日期的
href),拼出 embed。比例用 **`aspect-ratio: 16/9` 自己写全**,
**不要**借用上游的 `.iframeWrap` —— 那是老式的 `padding-top: 56.25%`,
一旦 iframe 没盖住那块 padding,就会在标题和播放器之间露出一大片空白(实际踩过)。

**视频简介**(`YouTubeDescriptionLoader.swift`):
YouTube RSS 里有 `<media:group><media:description>`,但上游 `AtomParser` 写着
`if namespace.prefix != nil { return }` —— **所有带前缀的元素被明确忽略**,
所以 `FeedParser` 永远拿不到。改为重拉 feed + `XMLParser`(SAX 真解析器,**不用正则**)。
非 YouTube 的源靠 feed 地址就能认出来,**一次请求都不发**。

⚠️ **两个元素的位置刻意相反,别改反了**:
- **播放器放 `#bodyContainer` 外面** —— 它不能被翻译
- **简介放 `#bodyContainer` 里面** —— 它应该跟着正文一起被翻译

**踩的大坑:所有视频报「错误代码 152」** —— 完整排查见 L37。
根因是上游 `loadHTMLString(html, baseURL:)` 把 YouTube 文章的身份设成了
`youtube.com`(baseURL 取自文章链接),播放器校验"谁在嵌我"时对不上。
修法:`WebViewController.nnwAdjustedBaseURL()` 只对 YouTube 文章换成中性身份。
安全性已量:全库 15 篇 YouTube 文章正文非空的 **0 篇**,2293 篇其它文章不受影响。

### ✅ 「+」与订阅发现页改造:已完成并验收(2026-07-21 深夜)

1. **「新建文件夹」移到账户分组头右侧**(`iOS/MainFeed/AddFolderHeaderButton.swift`)。
   **Main.storyboard 零改动** —— 运行时按「约束两端分别是谁」找出
   `未读数.leading = 标题.trailing` 那一节并停用,再把按钮接进链条;
   找不到该约束就什么都不做。分组头有折叠手势,加了仲裁者。
   ⚠️ 标题 label 的水平 hugging 默认只有 251 会自动拉伸,必须调高才能让按钮跟住名字(见 L38)
2. **`+` 不再弹操作单,直接进发现页**。理由:「添加订阅」和「搜索订阅源」
   本就是同一件事 —— 粘网址也是搜索的一种
3. **右上角统一**:去掉「完成」,只留左上角唯一的「取消」。
   根因是这个页面**没有「提交」动作**,点一条就订阅一条、当场生效
4. **订阅状态只在行尾表达**,三态齐全:⊕ 加号 / 转圈 / ✓ 对勾,**失败路径也刷新**
5. **「全部」tab 自动识别输入类型**(`FeedQueryRouter`,拆出来是为了能离线跑测试)
6. **结果行左侧图标**:播客封面来自 iTunes 返回、YouTube 头像来自已抓的频道页 ——
   **两者都是白拿的,没多发请求**;Reddit / 网站退回类型符号

⚠️ **网站这一类改过一次实现,别改回去**:初版把网址原样交给
`createFeed(validateFeed:)`,指望上游 `FeedFinder` 发现 —— **实测一个网站都订不上**。
现在改为**在搜索阶段就把 feed 找出来**:先用 `RSParser` 的 `HTMLMetadataParser`
读网页里的 `<link rel="alternate">`,没有再探 `/feed/` `/rss` `/index.xml` 等七个常见地址。
实测 stratechery.com 的 `<head>` 里**一个 RSS 声明都没有**,只能靠探测;
daringfireball.net 反过来只能靠读声明 —— **两步缺一不可**。
(不能直接调上游 `FeedFinder`:该模块**没有链接进 app target**,
project.pbxproj 里出现 0 次,链进来要改 .xcodeproj,违反第 8 节。)

### ✅ app 改名 Babel + 改名基础设施(2026-07-21 深夜)

**只改用户看得见的地方**:`CFBundleDisplayName`(单一真源是
`xcconfig/NetNewsWire_iOSapp_target.xcconfig` 里的 `APP_DISPLAY_NAME` 一行)
+ 界面中文文案 13 处。

**刻意不动,每条都有代价**:bundle id(一改数据全清零)、
target/scheme/.xcodeproj(构建失效 + 143 处冲突)、类名模块名(370 个文件)、
User-Agent(服务器兼容性标识,L33)、.xcstrings 的英文原文(上游文件)。

```bash
python3 i18n/rebrand.py 新名字      # 改名
python3 i18n/rebrand.py --check     # 自查
python3 i18n/inject.py zh-Hans      # 让译文生效
```

### ✅ 装到真机:已成功(2026-07-21)

免费 Personal Team **可以签**,预想的 App Groups 报错**没有出现**,退路没用上。
配置见 `NOTES-todo.md` 的 **T6**(含 Team ID 的读法 —— 新版 Xcode 界面不显示)。

**以后更新真机版本**:连线 → Xcode 选设备 → ⌘R。bundle id 没变 → **原地覆盖**,
订阅源、已读状态、Keychain 里的 API Key 全部保留。7 天倒计时也随之重置。

⚠️ **模拟器那个「假安装」的坑,真机没有**(见 L41)。真机走 Xcode 直推,所见即所得。

### 🔜 下一步:由用户决定

本轮结束时没有指定的下一件事。手上还悬着的:

- **T16** 订阅发现页那四个分类 tab 可能多余 —— 用几天再决定,别用推测代替使用数据
- **T17** 网站类订阅的探测路径清单,遇到订不上的站再补
- **T13** ACX 连续多图间距偏大,未诊断
- **T5** 翻译尾延迟,需要日常使用攒日志
- **T18** 长期安装 / 分享给朋友的选项(已讨论,用户暂不处理)

### 📋 四个内容源需求的方案结论(2026-07-21 深夜,①③ 已在 Phase A 落地)

用户提出:①YouTube 频道正文嵌播放器 ②订阅 X/Twitter ③订阅 Reddit 子版热帖
④播客(正文内语音条 + 跳 Apple Podcasts)。方案结论概要:

- ③ **零代码**:Reddit 官方 RSS 还活着(`/r/<sub>/top/.rss?t=day`),文字帖正文自带,教订阅即可
- ② **基本无解**:X 无官方 feed;Nitter/RSSHub 桥接要登录 cookie、极脆、有封号风险;
  建议改订 Bluesky(`/rss`)/ Mastodon(`.rss`)的官方 feed
- ① 可行:官方 RSS 本来就通(正文空而已),新增独立脚本往空正文插 embed iframe;
  已查 ContentRules.json **不含** youtube/ytimg/googlevideo(实现时仍要探针实测);
  「强制最高画质」做不到,embed 是自适应码率
- ④ 大半可行,但有个已查实的坑:RSParser **解析**了 enclosure(RSSParser.swift:279
  存进 ParsedItem.attachments),但 **Article 模型没有 attachments 字段、
  数据库还主动 DROP 了 attachments 表** —— 音频地址根本没入库。
  不碰 C 级禁区的做法:Swift 侧按需重新拉一次 feed XML,按 guid 匹配出该集的
  enclosure URL,交给注入脚本生成 `<audio>`;跳 Podcasts 用 iTunes lookup
  (节目级容易,单集级 best-effort);WKWebView 音频退后台会停,语音条只适合试听
- ①④ 属 CLAUDE.md 第 1 节**范围外新功能**,须用户确认扩大范围并补规则通道后才动手

---

### 已完成的界面改造(2026-07-21)

**范围扩大的由来**:改 iOS 界面本来被 CLAUDE.md 第 1 节明令禁止,
**已按规则先提醒、再由用户确认,规则文件已更新**
(第 1 节加了修订说明,第 2 节加了「D 级 · 界面改造专用」)。

两条改动通道已铺好并验证:

| 通道 | 做法 | 上游改动量 |
|---|---|---|
| 文章列表 | 新增 `iOS/MainTimeline/TimelineStyle.swift`,所有可调数值集中在此 | 两个上游文件,**一行换一行**的引用替换 |
| 正文阅读页 | 新增 `Shared/Appearance/nnw_appearance.js`,页面加载后往 `<head>` 追加一层 CSS | `WebViewConfiguration.swift` **一行里加一个单词** |

**这一步刻意不产生任何视觉变化**,验收标准就是「界面零变化」,并且是量过的:

- 列表:用「设置 → 文章列表布局」那两条**内容固定**的预览做对照,
  改动前后各截图,去掉状态栏后逐像素比 → **280 万像素 0 处不同**
- 正文页:同一篇文章改动前后逐像素比 → **280 万像素 0 处不同**
- iOS 与 macOS 双平台编译均通过

正文页那条通道用探针验证过是真的通的(先刷成琥珀色底,确认变了,再清空),
不是"写了空 CSS 看起来没坏"。踩到的坑记在 L23。

**已完成的第一项改动(2026-07-21):文章列表改成 Reeder 式布局。**

```
[favicon] [ 源名 ……………………… 时间 ★ ]  [缩略图]
          [ 标题(粗,最多 3 行)      ]
          [ 正文(补足到共 4 行)      ]
```

规则:
- favicon 那一列**永远占位**(没有图标也留着),否则混合列表里各行文字起点会参差不齐
- favicon **所有列表都显示**。⚠️ 上游的 `showIcons` 是跟着「要不要显示源名」走的,
  打开单个源时源名默认隐藏、图标就被一起关掉 ——
  本 fork 在 `iconImageFor()` 里去掉了这个判断
- 源名**所有列表都显示**(单个源里也显示,用户要求格式统一)
- **顶行占满整宽**,时间贴齐最右边、在缩略图正上方;
  缩略图只和「标题+正文」并排,并在这块高度上**垂直居中**
- 标题最多 3 行,正文 = 4 − 标题实际行数,至少 1 行
- 右侧缩略图取自正文首图;**没有图时文字铺满到最右边**
- 已读/未读**不再用小圆点**,改为**整行浓淡**(`TimelineStyle.readAlpha`)
- 设置里的「文章列表布局」(图标大小/行数两个滑块)已藏起来 —— 新布局写死了

**下一步**:继续等用户截图 → 优先只改 `TimelineStyle.swift` 和 `nnw_appearance.js` 里的值。

### 1. ⏳ 用户想装到真机 —— 有硬前置条件,别直接跑就以为能行

**iOS 模拟器不需要签名,真机需要。** 这是整个项目至今一直绕开的东西。

已查证的事实:

- 工程默认写死了上游作者的身份,**必须覆盖**
  (`xcconfig/common/NetNewsWire_codesigning_common.xcconfig`):
  ```
  ORGANIZATION_IDENTIFIER = com.ranchero
  DEVELOPMENT_TEAM = M8L2WTLA8W        ← Ranchero 自己的 team
  ```
- 覆盖方式是在**仓库外面**建一个文件(工程用 `#include?` 可选包含):
  ```
  /Users/wenbopan/Downloads/SharedXcodeSettings/DeveloperSettings.xcconfig
  ```
  **当前不存在。** 内容形如:
  ```
  DEVELOPMENT_TEAM = <你的 Team ID>
  ORGANIZATION_IDENTIFIER = <你自己的反向域名,例如 com.wenbopan>
  CODE_SIGN_STYLE = Automatic
  DEVELOPER_ENTITLEMENTS = -dev
  PROVISIONING_PROFILE_SPECIFIER =
  ```
  bundle id 由 `$(ORGANIZATION_IDENTIFIER).NetNewsWire.iOS$(BUNDLE_ID_SUFFIX)` 拼出,
  所以改 ORGANIZATION_IDENTIFIER 就能避开与上游冲突。
- `DEVELOPER_ENTITLEMENTS = -dev` 会切到精简版权限文件。两者差异已核对:
  | | 权限 |
  |---|---|
  | `NetNewsWire.entitlements`(默认) | iCloud/CloudKit、推送、App Groups、钥匙串组 |
  | `NetNewsWire-dev.entitlements` | **只有** App Groups、钥匙串组 |

  即真机 dev 版**没有 iCloud 同步和推送**。用户用的是本地账户(我的 iPhone),不受影响。

**🔴 尚未验证(必须实测,不要假设)**:
免费 Apple ID(个人团队)能否签 App Groups 权限。若不能,需要进一步精简 entitlements。
免费账号签出的 app **7 天过期**,需每周用 Xcode 重装;付费账号($99/年)为 1 年。

按 L3 的纪律:**先真机跑一次,让 Xcode 报错说话,不要凭推测下结论。**

### 2. 上一轮三个新功能只做了编译验证,用户尚未在界面上实测

`078023a99` 引入的:活化石改名、API Key 连通性测试、模型榜单刷新。
已验证:双平台编译通过;榜单解析链路用等价脚本实测 10/10 映射成功。
**未验证:界面上点下去的实际表现,尤其失败路径**
(故意填错 key 应报 401;断网刷新应保留原列表)。

### 3. 其余待办

见 `NOTES-todo.md`。当前活跃的是 **T5**(个别翻译组耗时数倍波动) ——
对策 1(provider sort=throughput)已上线,**需要用户日常使用几天攒日志**才能判断是否奏效。

### 模拟器的当前状态(2026-07-21 晚)

用户在本轮末尾**重置并清空了 app 的全部数据**,然后导入了一份新的订阅源清单
`external resources/english-reading-all-sources-organized.opml`(65 个源、7 个文件夹):

| 文件夹 | 未读 |
|---|---|
| 01 宏观、经济与政治经济 | 254 |
| 02 社会、政治、法律与思想 | 80 |
| 03 严肃长文、科学与文化 | 246 |
| 04 产业、工程与技术 | 211 |
| 05 投资、金融与市场 | 78 |
| 90 付费墙或部分付费通讯 | 259 |
| 99 无标准 RSS(供网页监控) | — |

**全是英文长文站**(Stratechery、SemiAnalysis、Astral Codex Ten、Aeon、
Marginal Revolution、Matt Stoller 等),就是为了测正文排版和翻译效果。

⚠️ **翻译用的 API key 存在 Keychain 里,清数据后需要重新填**
(设置 → 文章 → 翻译 API Key)。

「90 付费墙」那个文件夹里的文章大多是**截断的**(正文末尾一个 "Read more"),
是测「阅读视图抓全文 → 再翻译」这条组合链路的最佳样本。

⚠️ **更正(2026-07-21 深夜实测)**:实际订阅是 **77 个源**,不止 OPML 那 65 个 ——
Michael Tsai、Julia Evans、Daring Fireball 等十来个在**文件夹外的顶层**。
数法:模拟器容器里的 `Subscriptions.opml` 数 `xmlUrl`。
另:**app 数据容器路径会变**(本轮一晚上就变了三次),查数据库别复用旧路径,每次现找:
```bash
find ~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Data/Application \
  -name DB.sqlite3 -path "*Accounts*" 2>/dev/null
```

---

## 五、翻译功能架构速览(细节看代码注释,都是中文)

```
点按钮 → TranslationController.performToggle()
  ├─ 查 TranslationCache(文章+模型+提示词版本;条目内校验正文纯文字指纹)
  │    ├─ 完整缓存命中 → 整篇秒开,零请求
  │    └─ 未完成缓存命中 → 已翻好的组直接复用,只翻剩下的(断点续翻)
  ├─ translation.js splitBody() 切组:先导块500字符 → 第1组1000 → 逐组翻倍,4000封顶
  │    (超大单元素如巨型 blockquote 会下钻一层按子元素切;组不跨父节点)
  ├─ 标题 + 先导块 同时发出(标题最短最快回)
  ├─ 先导块译文作为"术语示范"传给后续组(一致性方案 C)
  ├─ 其余组并行(最多4并发),谁回来谁替换,失败自动重试1次
  ├─ 事后自检 findGroupsNeedingRetranslation():纯本地零费用
  │    ①还是英文?(中文<5% 且英文字母>40%) ②混进原文?(原文中段60字符探针)
  │    → 查出的组重翻一轮
  └─ 全部成功 → 写完整缓存;有失败 → 按钮变⚠️ 并存未完成缓存
```

**文件清单(全部在 `Shared/Translation/`,上游不存在此目录):**

| 文件 | 职责 |
|---|---|
| `TranslationService.swift` | 协议 + 错误定义 + mock |
| `OpenAICompatibleTranslator.swift` | HTTP 请求、提示词、输出清洗、连通性测试 |
| `TranslationController.swift` | 编排:分组、并发、重试、自检、缓存、按钮状态 |
| `TranslationConfig.swift` | 模型列表(内置/刷新而来)、baseURL、选中模型 |
| `TranslationKeychain.swift` | API key 存取(系统 Security 框架,**没用上游 Secrets 模块**) |
| `TranslationCache.swift` | 译文缓存(内存+磁盘 Caches,上限50篇,支持未完成缓存) |
| `ArticleReadingStateStore.swift` | **(2026-07-22 新增)** 按单篇文章记住 `{阅读模式, 已翻译}`,供 item③ 自动恢复。UserDefaults,LRU 上限500 |
| `OpenRouterModelCatalog.swift` | 从 OpenRouter 翻译榜拉模型(防御式解析,失败不覆盖) |
| `TranslationModelPickerViewController.swift` | 设置→翻译模型(含刷新按钮) |
| `TranslationAPIKeyViewController.swift` | 设置→翻译 API Key(含连通性测试) |
| `AppLanguageController.swift` | 界面语言读写,可选项从 Bundle 动态发现 |
| `AppLanguagePickerViewController.swift` | 设置→外观→界面语言 |
| `translation.js` | 网页内:切组、替换、自检、还原(**所有 HTML 解析都在这层**) |

**界面改造新增的文件(2026-07-21,上游都不存在):**

| 文件 | 职责 |
|---|---|
| `iOS/MainTimeline/TimelineStyle.swift` | 文章列表的全部可调数值(字号、间距、颜色、行数、缩略图尺寸)。**调列表外观只改这里** |
| `iOS/MainTimeline/ArticleThumbnail.swift` | 从正文 HTML 抽首图 + 交给 ImageDownloader 下载(见 L28) |
| `Shared/ReaderView/ReaderViewExtractor.swift` | 「阅读视图」的正文提取:隐藏 WebView + Readability.js,**全本地** |
| `Shared/ReaderView/Readability.js` | **第三方**(Mozilla,Apache 2.0)。规矩见同目录 README-vendor.md |
| `Shared/Appearance/nnw_appearance.js` | 正文页的覆盖样式层。**调正文外观只改这里的 CSS** |
| `iOS/Resources/Assets.xcassets/AppIconCustom.appiconset/` | 本 fork 的 app 图标。上游的 `AppIcon.appiconset` 未动,靠 xcconfig 一行指过来(见 L24) |

**订阅发现 / 播客 / YouTube 新增的文件(2026-07-21 深夜,上游都不存在):**

| 文件 | 职责 |
|---|---|
| `Shared/Discovery/FeedSearchResult.swift` | 统一的结果模型 + 会说人话的错误定义 |
| `Shared/Discovery/FeedQueryRouter.swift` | 「全部」tab 的输入类型判断。**拆出来是为了能离线跑测试** |
| `Shared/Discovery/PodcastSearcher.swift` | iTunes Search API(官方、免 key、直接给 feedUrl 和封面) |
| `Shared/Discovery/RedditFeedBuilder.swift` | 版块名解析 + 拼 .rss,**全本地零请求**(L33) |
| `Shared/Discovery/YouTubeFeedResolver.swift` | 频道页抠 channel_id + 头像。抓页面用**桌面浏览器 UA** |
| `Shared/Discovery/WebsiteFeedResolver.swift` | 读网页 RSS 声明 + 探测常见地址 + favicon |
| `Shared/Discovery/FeedDiscoveryViewController.swift` | 搜索页(iOS only) |
| `Shared/Discovery/MainFeedCollectionViewController+Discovery.swift` | `+` 的入口 + 新建文件夹动作 |
| `Shared/Podcast/PodcastEpisodeLocator.swift` | 重拉 feed 按 guid 找 enclosure,**含负缓存**(L35) |
| `Shared/Podcast/ApplePodcastsLinkResolver.swift` | iTunes 单集深链(`episodeGuid` 对得上 `Article.uniqueID`) |
| `Shared/Podcast/nnw_podcast.js` | 语音条,插在 `#bodyContainer` **外面** |
| `Shared/YouTube/nnw_youtube.js` | 播放器(外面)+ 简介容器(里面) |
| `Shared/YouTube/YouTubeDescriptionLoader.swift` | `XMLParser` 解 `media:description`(上游明确忽略带前缀元素) |
| `iOS/MainFeed/AddFolderHeaderButton.swift` | 账户分组头右侧的「新建文件夹」按钮 |
| `i18n/rebrand.py` | 改 app 显示名 + 自查 |

**本地化产物(见 `NOTES-i18n.md`):**
`i18n/inject.py`(注入器)、`i18n/zh-Hans.json`(436 条翻译表)、
各 `<语言>.lproj/*.strings`。

**动过的上游文件(只有 3 个 Swift + 4 个 storyboard 位置移动):**

| 文件 | 改动方式 |
|---|---|
| `iOS/Article/WebViewController.swift` | 纯末尾追加(JS 桥接扩展) |
| `iOS/Article/ArticleViewController.swift` | 少量插入 + 末尾追加(按钮安装/状态重置/工具栏重排) |
| `iOS/Settings/SettingsViewController.swift` | 中间插入(设置里三行入口) |
| 4 个 storyboard | 仅用 `git mv` 移入各自 `Base.lproj/`,**内容零改动** |
| 4 个 `.xcstrings` | 注入 zh-Hans 段,**原有内容逐 key 校验零改动** |
| `iOS/MainTimeline/Cell/MainTimelineCellLayout.swift` | 常量值改为引用 `TimelineStyle`,一行换一行 |
| `iOS/MainTimeline/Cell/MainTimelineCell.swift` | 颜色改为引用 `TimelineStyle`,一行换一行 |
| `Shared/Article Rendering/WebViewConfiguration.swift` | 脚本清单数组里加一个名字,共一行 |
| `xcconfig/NetNewsWire_iOSapp_target.xcconfig` | 末尾追加一行,把 app 图标指向本 fork 自己的图标集 |

| `iOS/Article/ArticleViewController.swift` | 另:去掉阅读视图按钮的 `!isDeveloperBuild` 禁用判断 |
| `iOS/Article/WebViewController.swift` | 另:提取器换成 `ReaderViewExtractor`,共两行 |
| `iOS/MainTimeline/MainTimelineModernViewController.swift` | 填缩略图、监听图片就绪、favicon 恒显,共三处 |
| `iOS/MainFeed/MainFeedCollectionViewController.swift` | `+` 改为直接进发现页;分组头装按钮一行 |
| `iOS/Article/WebViewController.swift` | `didFinish` 一行钩子 + `loadHTMLString` 的 baseURL 换成我们的函数 + 末尾追加扩展 |
| `Shared/Article Rendering/WebViewConfiguration.swift` | 脚本清单里再加两个名字(nnw_podcast、nnw_youtube) |
| `iOS/Resources/Info.plist` | 加 `CFBundleDisplayName = $(APP_DISPLAY_NAME)` 两行 |
| `xcconfig/NetNewsWire_iOSapp_target.xcconfig` | 末尾追加 `APP_DISPLAY_NAME`(改名单一真源) |
| `iOS/Article/WebViewController.swift` | **(2026-07-22 item③)** `didFinish` 再加一行钩子 + `setArticle` 判断加「或」+ 末尾追加 `[状态记忆]` 扩展 |
| `iOS/Article/ArticleViewController.swift` | **(2026-07-22 item②③⑤)** 全在已有 `[翻译]` 扩展里追加:长按手势/确认框、`presentError` 弹窗、自动恢复转接方法 |

翻译功能的改动带 `[翻译]` 标记,界面改造带 `[界面]` 标记,
阅读视图带 `[阅读视图]` 标记,状态记忆带 `[状态记忆]` 标记,⌘F 可分别盘点。

## 六、构建与验证命令(实测可用)

```bash
cd "/Users/wenbopan/Downloads/RSS ai translation"

# iOS 模拟器(主要目标)
xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build

# macOS(每次改 Shared/ 后必须跑,验证没弄坏它;需要免签名参数)
xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  ENTITLEMENTS_REQUIRED=NO build

# 装到模拟器并启动(比在 Xcode 里按 ⌘R 更适合 AI 自己验证)
APP=$(find ~/Library/Developer/Xcode/DerivedData/NetNewsWire-*/Build/Products/Debug-iphonesimulator \
  -maxdepth 1 -name "NetNewsWire.app" -type d | head -1)
xcrun simctl install booted "$APP"
xcrun simctl launch booted com.ranchero.NetNewsWire.iOS-DEBUG
xcrun simctl io booted screenshot /tmp/shot.png

# 强制用中文启动(验证本地化)
xcrun simctl launch booted com.ranchero.NetNewsWire.iOS-DEBUG --args -AppleLanguages '(zh-Hans)'

# 看 app 日志(排查翻译问题,过滤 [翻译])
xcrun simctl spawn booted log show --last 30m --predicate 'process == "NetNewsWire"' --style compact
```

### 模拟器实用操作(2026-07-21 实测)

**一键切换浅色 / 深色**:`⇧⌘A`(菜单 Features → Toggle Appearance)。
验证任何配色改动都该按一下这个键看另一半。

同一个 Features 菜单里还有两个对本项目特别有用的:

| 操作 | 快捷键 | 为什么有用 |
|---|---|---|
| Toggle Appearance | `⇧⌘A` | 浅色 / 深色 |
| Increase / Decrease Preferred Text Size | `⌥⌘+` / `⌥⌘−` | **系统动态字号**。文章列表和正文的字号都跟着它走,调大几档能顺便检查布局会不会崩(拉到最大会切到 T7 说的无障碍布局) |

⚠️ **主屏图标外观(默认/深色/透明/色调)是另一回事**,`⇧⌘A` 和
`simctl ui appearance` 都管不着它。要测图标必须:
主屏长按空白处 → 左上角「编辑」→「自定」→ 选那四个之一。

**把文件送进模拟器(例如导入 OPML 订阅源)**:

模拟器没有直接的"添加文件"命令。可用的办法是把文件复制进
**Files app 的「我的 iPhone」存储**,app 内的文件选择器就能看到:

```bash
UDID=A7B1AE1F-0391-4C3A-B979-FA35653256FF   # xcrun simctl list devices booted 可查

# 找到 Files app 的本地存储(认 group.com.apple.FileProvider.LocalStorage)
D=~/Library/Developer/CoreSimulator/Devices/$UDID/data/Containers/Shared/AppGroup
for g in "$D"/*/; do
  echo -n "$(basename $g) → "
  plutil -extract MCMMetadataIdentifier raw "$g/.com.apple.mobile_container_manager.metadata.plist"
done

# 复制进去(把 <GROUP> 换成上面认出来的那个 UUID)
cp 你的文件.opml "$D/<GROUP>/File Provider Storage/"
```

然后在 app 里:设置 → Feed →「导入订阅」→ 文件选择器里直接就能看到它。
**实测 2026-07-21**:55 个订阅源 + 6 个文件夹(生活/旅行/财经/科技/博客/China from other)
一次导入成功,中文源抓取正常。

⚠️ 全新 clone 后第一次 iOS 编译必失败(`SecretKey` 不存在),再编译一次即可。详见 L1。

## 七、用户如何使用

1. 设置 → 文章 → 「翻译 API Key」→ 填 OpenRouter key(存 Keychain),可点「测试连通性」
2. 设置 → 文章 → 「翻译模型」→ 选模型;右上角可从 OpenRouter 翻译榜刷新列表
3. 设置 → 外观 → 「界面语言」→ 跟随系统 / 简体中文 / English(改后需重启 app)
4. 文章页底部工具栏最右侧气泡按钮:
   - 空心 = 没翻过,点击联网翻译
   - 空心 + 实心角标点 = 有完整缓存,点击秒开
   - 空心 + 空心角标点 = 有未完成缓存,点击接着上次继续翻
   - 实心 = 正在显示译文,点击回原文
   - 转圈中再点 = 取消

---

## 八、每次改完代码,装模拟器请用这个脚本

```bash
./tools/install-to-simulator.sh
```

**不要**直接 `xcrun simctl install`。原因(L41,2026-07-21 真实踩过):
`simctl install` 会把新版装进一个**新容器**,而系统注册的仍是旧容器 ——
命令返回成功、app 能启动,**但跑的是旧代码**。
本轮因此让用户测了 40 分钟前的二进制,还据此排查了一整轮无效功。

脚本装完必 `cmp` 比对,不一致就 rsync 覆盖到系统正在用的那个容器
(非破坏性,不动数据容器,订阅源和 Keychain 都不会丢)。
**实测这个卡死是持续存在的**,脚本每次都会报警并自动兜住。

排查「改了没生效」的第一步永远是:**先证明跑的确实是新代码**,再去查逻辑。
```bash
A=$(xcrun simctl get_app_container booted com.ranchero.NetNewsWire.iOS-DEBUG app)
cmp "$A/NetNewsWire" <构建产物>/NetNewsWire
```

另:`log show` **默认不保留 info 级别**,看到日志空白先加 `--info` 再下结论。
