# NOTES-architecture.md — Phase 0 代码考古笔记

> 产出日期：2026-07-19
> 对应 CLAUDE.md 第 4 节 Phase 0 的 7 个问题
> 基线 commit：`08d10f501`（上游 main）

## 关于本文件的可信度

本笔记的**每一条结论**都给出：文件路径 + 行号 + 真实代码原文 + 你能自己执行的核对方法。

**证据等级标注：**

- 🟢 **已亲自核实** —— 我本人跑过命令看过原文，行号逐字对得上
- 🟡 **调查得出，未逐行复核** —— 由调查过程得出，我核对了关键行但未通读
- 🔴 **不确定** —— 明确不知道，说明还需要看什么

**凡是我不知道的，都标 🔴，不用推测填空。**

---

## 问题 1 — macOS 和 iOS 的正文分别由谁渲染？

### 🟢 答案：两个平台各有一个控制器，但它们都很薄

| 平台 | 承载 WebView 的控制器 |
|---|---|
| iOS | `iOS/Article/WebViewController.swift` |
| macOS | `Mac/MainWindow/Detail/DetailWebViewController.swift` |

**决定性证据**：全仓库把 HTML 装进 WebView 的地方，**总共只有两处**。

```
$ grep -rn "loadHTMLString" --include="*.swift" .
iOS/Article/WebViewController.swift:648
Mac/MainWindow/Detail/DetailWebViewController.swift:316
```

> **你可以这样核对**：在项目根目录打开终端，粘贴上面那条 `grep` 命令，应该只输出这两行。

iOS 侧的外层还有一个容器 `iOS/Article/ArticleViewController.swift`，它是个左右翻页的 `UIPageViewController`，**不负责渲染**，只负责翻页和工具栏。

`iOS/Article/ArticleViewController.swift:39-41`：

```swift
	private var currentWebViewController: WebViewController? {
		return pageViewController?.viewControllers?.first as? WebViewController
	}
```

> **你可以这样核对**：打开 `iOS/Article/ArticleViewController.swift`，⌘F 搜 `currentWebViewController`，应该能找到。

---

## 问题 2 — 是 WKWebView + HTML 模板吗？模板在哪？

### 🟢 答案：是。而且模板分两层。

**第一层：正文片段模板（两个平台共用同一份）**

`Shared/Article Rendering/template.html:43-47`：

```html
<article>
<div class="articleTitle"><h1><a href="[[preferred_link]]">[[title]]</a></h1></div>
<div class="[[dateline_style]]"><a href="[[preferred_link]]">[[datetime_medium]]</a></div>
<div class="externalLink">[[external_link_label]] <a href="[[external_link]]">[[external_link_stripped]]</a></div>
<div id="bodyContainer" class="articleBody [[text_size_class]]">[[body]]</div>
</article>
```

**注意第 46 行的 `id="bodyContainer"`。** 这是文章正文在网页里的容器，有一个稳定的 id。**这对翻译功能极其重要** —— 有了它，JS 可以精确定位并替换正文，不用碰其他部分。

**第二层：HTML 外壳（两个平台各一份）**

```
$ grep -n "\[\[body\]\]" "Shared/Article Rendering/template.html" iOS/Resources/page.html Mac/MainWindow/Detail/page.html
iOS/Resources/page.html:17:		[[body]]
Mac/MainWindow/Detail/page.html:10:		[[body]]
Shared/Article Rendering/template.html:46:<div id="bodyContainer" class="articleBody [[text_size_class]]">[[body]]</div>
```

`[[xxx]]` 是 NetNewsWire 自己的占位符语法，由 `MacroProcessor` 替换。

> **你可以这样核对**：打开 `Shared/Article Rendering/template.html`，⌘F 搜 `bodyContainer`，应该能在第 46 行找到。

---

## 问题 3 — CSS / 主题怎么注入？

### 🟢 答案：CSS 被当成字符串塞进 HTML 的 `[[style]]` 占位符，不是 `<link>` 标签。

`iOS/Article/WebViewController.swift:629-637`：

```swift
		let substitutions = [
			"title": rendering.title,
			"baseURL": rendering.baseURL,
			"style": rendering.style,
			"body": rendering.html,
			"windowScrollY": String(windowScrollY)
		]

		var html = try! MacroProcessor.renderedText(withTemplate: ArticleRenderer.page.html, substitutions: substitutions)
```

CSS 文件本体在共享目录：

- `Shared/Article Rendering/core.css` —— 基础规则，主题**不能**覆盖
- `Shared/Article Rendering/stylesheet.css` —— 默认主题样式

### 🟡 主题机制

用户可以装 `.nnwtheme` 主题包（仓库根目录 `Themes/` 有 8 个内置的），每个主题可以整体替换 `stylesheet.css` 和 `template.html`，但 `core.css` 永远被强制拼在最前面。相关代码在 `Shared/ArticleStyles/ArticleTheme.swift`。

**这对我们的影响：如果翻译功能要加自己的 CSS，不能依赖修改 `stylesheet.css`** —— 用户换个主题就没了。要么走 `core.css`（但那是已有文件，改它有 merge 风险），要么由 JS 在运行时注入。

> **你可以这样核对**：打开 `Shared/Article Rendering/` 文件夹，应该能看到 `core.css` 和 `stylesheet.css` 两个文件。

---

## 问题 4 — 有现成的 JS ↔ Swift 通信机制吗？

### 🟢 答案：有，而且两个方向都有。这是好消息。

**方向一：JS → Swift**（`WKScriptMessageHandler`）

iOS 已注册 3 个消息通道，`iOS/Article/WebViewController.swift:25-29`：

```swift
	private struct MessageName {
		static let imageWasClicked = "imageWasClicked"
		static let imageWasShown = "imageWasShown"
		static let showFeedInspector = "showFeedInspector"
	}
```

JS 侧这样发消息（`iOS/Resources/main_ios.js:50`）：

```javascript
		window.webkit.messageHandlers.imageWasClicked.postMessage(jsonMessage);
```

**方向二：Swift → JS**（`evaluateJavaScript`）

`iOS/Article/WebViewController.swift:684-686`：

```swift
		if let imageSrc = components.string {
			webView?.evaluateJavaScript("reloadArticleImage(\"\(imageSrc)\")")
		}
```

**JS 文件注入机制**，`Shared/Article Rendering/WebViewConfiguration.swift:116-129`：

```swift
	static let articleScripts: [WKUserScript] = {
#if os(iOS)
		let filenames = ["main", "main_ios", "newsfoot"]
#else
		let filenames = ["main", "main_mac", "newsfoot"]
#endif

		let scripts = filenames.map { filename in
			let scriptURL = Bundle.main.url(forResource: filename, withExtension: ".js")!
			let scriptSource = try! String(contentsOf: scriptURL, encoding: .utf8)
			return WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
		}
		return scripts
	}()
```

**意味着**：我们已经有了一条现成的双向通道。翻译功能不需要发明新机制，顺着已有模式加即可。

> **你可以这样核对**：打开 `iOS/Article/WebViewController.swift`，⌘F 搜 `messageHandlers` 或 `MessageName`，应该能找到。

---

## 问题 5 — HTML 进 WebView 前，最后经过哪个函数？

### 🟢 答案：`ArticleRenderingSpecialCases.filterHTMLIfNeeded`

完整管线（iOS，第 607 行的 `renderPage(_:)` 函数内）：

```
1. ArticleRenderer.articleHTML(...)              生成正文 HTML
   → Shared/Article Rendering/ArticleRenderer.swift:124

2. MacroProcessor.renderedText(...)              套进 page.html 外壳
   → iOS/Article/WebViewController.swift:637

3. ArticleRenderingSpecialCases.filterHTMLIfNeeded(...)   ← 最后一道字符串处理
   → iOS/Article/WebViewController.swift:638

4. webView.loadHTMLString(html, ...)             装进 WebView
   → iOS/Article/WebViewController.swift:648
```

`iOS/Article/WebViewController.swift:637-648` 原文：

```swift
		var html = try! MacroProcessor.renderedText(withTemplate: ArticleRenderer.page.html, substitutions: substitutions)
		html = ArticleRenderingSpecialCases.filterHTMLIfNeeded(baseURL: rendering.baseURL, html: html)

		// Uncomment when you want to debug HTML and CSS for an article.
		...
		WebViewConfiguration.addContentBlockingRules(to: webView)
		webView.loadHTMLString(html, baseURL: URL(string: rendering.baseURL))
	}
```

> **你可以这样核对**：打开 `iOS/Article/WebViewController.swift`，⌘F 搜 `loadHTMLString`，跳到第 648 行，往上看几行就是这段。

### 🟢 附带发现：已经存在一条"替换正文"的官方通道

`Shared/Article Rendering/ArticleRenderer.swift:113-118`：

```swift
		if let content = extractedArticle?.content {
			self.body = content
			self.baseURL = extractedArticle?.url
		} else {
			self.body = article?.body ?? ""
			self.baseURL = article?.baseURL?.absoluteString
		}
```

**这是整份笔记里最重要的五行。** 它说明：NetNewsWire 本来就支持"用另一份内容替换文章正文"——这就是"阅读视图"（Reader View）的实现方式。翻译功能在架构上与它同构。

⚠️ 但**这不代表我们应该复用 `extractedArticle` 这个字段**。它属于 `Shared/Article Extractor/` 体系，复用它意味着改已有代码。是参考模板，不是现成插座。

> **你可以这样核对**：打开 `Shared/Article Rendering/ArticleRenderer.swift`，⌘F 搜 `extractedArticle?.content`，应该能找到。

---

## 问题 6 — SPM 还是 CocoaPods？有哪些 scheme？

### 🟢 答案：SPM，无 CocoaPods。

- 无 `Podfile`、无 `Podfile.lock`（已确认）
- 本地 SPM 包在 `Modules/` 下（18 个）
- 外部依赖 4 个：`Zip`、`Sparkle-Binary`、`PLCrashReporter`、`Tidemark`

**关键 scheme**（共 28 个，只有这两个和我们有关）：

| scheme | 对应 |
|---|---|
| **`NetNewsWire-iOS`** | iOS app ← **我们只用这个** |
| `NetNewsWire` | macOS app |

**已实测通过的构建命令**（BUILD SUCCEEDED）：

```bash
cd "/Users/wenbopan/Downloads/RSS ai translation"
xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

> **你可以这样核对**：把上面的命令粘进终端跑一次，最后应该输出 `** BUILD SUCCEEDED **`。

⚠️ **全新 clone 后第一次编译必定失败**，报 `cannot find 'SecretKey' in scope`。原因：`Modules/Secrets/Sources/Secrets/SecretKey.swift` 被 `.gitignore` 排除，由编译期脚本生成，但生成时机晚于 `Secrets` 模块的编译。**解决：再编译一次即可。不要去改那两个报错的文件。**

---

## 问题 6b（关键题）— macOS 和 iOS 的渲染层共享了多少？

### 🟢 答案：**大部分共享。共享的部分在仓库根目录的 `Shared/` 文件夹。**

### 硬证据：两个 app target 挂载了同一个 `Shared` 文件夹

Xcode 工程里，`Shared` 文件夹的内部编号是 `84D35D422DB9F32D004AA60E`。查它出现在哪里：

```
$ grep -n "84D35D422DB9F32D004AA60E" NetNewsWire.xcodeproj/project.pbxproj
555:  ...path = Shared;...          ← 定义
718:  ...                            ← 挂在项目根组下
899:  84D35D42... /* Shared */,     ← 属于 target "NetNewsWire-iOS"
946:  84D35D42... /* Shared */,     ← 属于 target "NetNewsWire"（macOS）
```

对应的上下文（`project.pbxproj:897-901` 与 `:944-948`）：

```
			fileSystemSynchronizedGroups = (
				84A6CFB52D1B4EC500F23315 /* iOS */,
				84D35D422DB9F32D004AA60E /* Shared */,
			);
			name = "NetNewsWire-iOS";
```

```
			fileSystemSynchronizedGroups = (
				842E249F2DB9F9B800FF7DD8 /* Mac */,
				84D35D422DB9F32D004AA60E /* Shared */,
			);
			name = NetNewsWire;
```

**同一个编号出现在两个 target 下 = 磁盘上同一份文件被两边编译。** 这不是"看起来像"，这是工程文件的字面记录。

> **你可以这样核对**：在项目根目录终端里粘贴
> `grep -n "84D35D422DB9F32D004AA60E" NetNewsWire.xcodeproj/project.pbxproj`
> 应该输出 4 行，其中两行在 899 和 946 附近。

### 共享矩阵

| 文件 | 共享？ | 位置 |
|---|---|---|
| `ArticleRenderer.swift`（生成正文 HTML） | ✅ **共享** | `Shared/Article Rendering/` |
| `WebViewConfiguration.swift`（WebView 配置 + 注入 JS） | ✅ **共享** | `Shared/Article Rendering/` |
| `template.html`（正文模板，含 `id="bodyContainer"`） | ✅ **共享** | `Shared/Article Rendering/` |
| `core.css` / `stylesheet.css` | ✅ **共享** | `Shared/Article Rendering/` |
| `main.js`（渲染后处理 pipeline） | ✅ **共享** | `Shared/Article Rendering/` |
| `newsfoot.js`（脚注弹窗） | ✅ **共享** | `Shared/Article Rendering/` |
| `Themes/*.nnwtheme`（8 个主题） | ✅ **共享** | 根目录 `Themes/` |
| `page.html`（HTML 外壳） | ❌ 各一份 | `iOS/Resources/` · `Mac/MainWindow/Detail/` |
| `blank.html`（预热空白页） | ❌ 各一份 | 同上 |
| `main_ios.js` / `main_mac.js`（平台钩子） | ❌ 各一份 | 同上 |
| 承载 WebView 的控制器 | ❌ 各一份 | `iOS/Article/WebViewController.swift` · `Mac/MainWindow/Detail/DetailWebViewController.swift` |
| 工具栏 / 按钮 UI | ❌ 各一份 | iOS 在 Storyboard + `ArticleViewController.swift` |

### 共享 JS 里有一个现成的扩展点

`Shared/Article Rendering/main.js:159-170`：

```javascript
function processPage() {
	wrapFrames();
	wrapTables();
	inlineVideos();
	stripStyles();
	constrainBodyRelativeIframes();
	convertImgSrc();
	flattenPreElements();
	styleLocalFootnotes();
	removeWpSmiley()
	postRenderProcessing();
}
```

`postRenderProcessing()` 由两个平台各自实现（`main_ios.js` / `main_mac.js`），是官方留的平台钩子。

### 对方案的直接含义

**按钮 UI 必须做在 iOS 层（不共享），但翻译的核心逻辑可以做在共享层。**

也就是说：如果把"替换正文"做成一个共享的 JS 函数 + 共享的 Swift 服务，那么将来想让 macOS 也支持翻译时，**只需要补一个 macOS 的按钮**，逻辑不用重写。

⚠️ 但按 CLAUDE.md 第 1 节，macOS **明确不在本次范围内**。上面这句只是说明"这样做以后不会堵死路"，**不是**建议现在就做 macOS。

---

## 问题 7 — 建议哪些目录列入禁区？

### 🟡 建议的禁区清单

**A 级 —— 绝对不碰（账户 / 订阅 / 同步，CLAUDE.md 第 2 节已明令禁止）**

```
Modules/Account/            账户与订阅源模型 + 5 种同步后端
Modules/SyncDatabase/       同步状态存储
Modules/CloudKitSync/       CloudKit 同步
Modules/Secrets/            钥匙串凭据 + 编译期注入的 API key
Modules/FeedFinder/         订阅源发现
Modules/NewsBlur/           NewsBlur API 客户端
iOS/Account/                iOS 账户设置界面
iOS/Add/                    添加订阅源界面
Mac/Preferences/Accounts/   macOS 账户设置界面
Shared/SmartFeeds/          Today / Unread / Starred 伪订阅源
Shared/Importers/           OPML 导入
Shared/Exporters/           OPML 导出
```

**B 级 —— 本次范围外，不碰（CLAUDE.md 第 1 节：只做 iOS）**

```
Mac/                        整个 macOS UI
Widget/                     小组件扩展
Intents/                    Siri / App Intents
```

**C 级 —— 数据层，碰之前必须先问用户**

```
Modules/Articles/           文章数据模型（Article.swift 等）
Modules/ArticlesDatabase/   文章正文与已读状态的 SQLite 存储
```

> 说明：C 级不属于"账户 / 同步"，但如果将来要**把译文缓存下来**，就会碰到它们。按 CLAUDE.md 第 5 节「缓存逻辑全部在后端」，**Swift 侧不应该需要动这两个包**。若发现必须动，那是设计出了问题，应先报告。

**D 级 —— 允许修改，但每次改前必须说明理由**

```
iOS/Article/WebViewController.swift        唯一的 iOS 正文装载点
iOS/Article/ArticleViewController.swift    工具栏所在
iOS/Base.lproj/Main.storyboard             按钮实体所在
Shared/Article Rendering/                  共享渲染层
```

---

## ⚠️ 重要发现：CLAUDE.md 第 5 节与第 8 节冲突，需要修订

### 冲突内容

- **第 5 节**：「新增代码写在 `Translation/` 下，不要往已有的目录里塞文件。」
- **第 8 节**：「不要修改 `.xcodeproj` 文件里的构建设置。」

### 🟢 为什么冲突

这个工程用的是 Xcode 16+ 的"文件系统同步文件夹"机制 —— 只有被工程显式声明的文件夹，往里面丢新文件才会被自动编译。声明列表是：

```
$ grep -n "PBXFileSystemSynchronizedRootGroup" NetNewsWire.xcodeproj/project.pbxproj
548:  path = Technotes
549:  path = Mac
550:  path = Widget
551:  path = Tests
552:  path = xcconfig
553:  path = iOS
554:  path = Modules
555:  path = Shared
```

**仓库根目录不在这个列表里。** 所以在根目录建 `Translation/` 文件夹，Xcode 看不见它，代码不会被编译 —— 除非改 `.xcodeproj`，那就违反第 8 节。

> **你可以这样核对**：粘贴上面那条 grep 命令，输出 8 行，里面没有一行是根目录。

### 建议的修订

新代码放 **`Shared/Translation/`**（而非根目录 `Translation/`）。

理由：

1. `Shared/` 已在同步列表里 → **不需要碰 `.xcodeproj`**，满足第 8 节
2. `Shared/Translation/` 是上游不存在的全新文件夹 → merge 冲突风险与根目录方案**完全相同**（都是零）
3. 代码仍然集中在自己的目录里 → 满足第 5 节的本意
4. 放在 `Shared/` 下，将来若要支持 macOS，逻辑层不用搬家

**此结论待 Phase 1 实测验证**：Phase 1 第一件事是往 `Shared/Translation/` 放一个最小文件并编译，用一次 build 证明它确实被编进去了，而不是停留在推理。

---

## 🔴 明确不确定的事项

以下问题我**没有答案**，需要进一步调查或实测才能确定。**不要在这些点上假设我说过什么。**

1. **iOS 26 工具栏插入位置**
   `iOS/Article/ArticleViewController.swift:137-138`：
   ```swift
		if #available(iOS 26, *) {
			toolbarItems?.insert(articleExtractorBarButtonItem, at: 5)
   ```
   iOS 26 分支直接在索引 5 插入，旧系统分支则完全重建数组。索引 5 在运行时到底落在哪个位置，我**没有实测**。加按钮时需要实际跑起来看，不能照着数字推。

2. **新按钮要不要同时改 Storyboard**
   工具栏按钮实体定义在 `iOS/Base.lproj/Main.storyboard:36-73`。Storyboard 是 XML，**merge 冲突风险高于纯 Swift 文件**。能否纯代码加按钮而完全不碰 Storyboard，我**还没有验证**。这是 Phase 2 要先解决的问题。

3. **翻译后的 HTML 走哪条路替换正文**
   目前看到两条候选路径（重新走一遍 `loadHTMLString` / 用 JS 替换 `#bodyContainer` 的内容），各有取舍。**Phase 2 开始前必须先定，现在不做结论。**

4. **`Resources/Themes/` 是不是死副本**
   仓库里 `Themes/` 和 `Resources/Themes/` 内容完全相同。工程似乎只引用根目录的 `Themes/`。**与我们无关，不要动它**，仅作记录。

5. **`MacroProcessor` 对未提供的占位符如何处理**
   iOS 下 `[[text_size_class]]` 没有被赋值，会被替换成空串还是原样保留，我**没有读过 `MacroProcessor` 的实现**。如果翻译功能要往模板里加占位符，需要先搞清楚这一点。

6. **macOS 侧的细节**
   问题 1/6b 里涉及 macOS 的部分，我核实了 `loadHTMLString` 的位置，但**没有通读** macOS 的渲染代码。由于 macOS 明确不在范围内，暂不深入。

---

## 一句话总结

> 正文渲染的**逻辑层是共享的**（`Shared/Article Rendering/`），**UI 层是各自的**。
> 全仓库只有 **2 个** 把 HTML 装进 WebView 的位置，**1 个** 稳定的正文 DOM 容器（`#bodyContainer`），以及 **1 套现成的双向 JS↔Swift 通道**。
> 落点干净，不需要大改。
