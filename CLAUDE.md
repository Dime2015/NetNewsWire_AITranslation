# CLAUDE.md — NetNewsWire AI 翻译 fork

> 这个文件是给 AI agent 读的项目规则。人类的操作步骤在 `HANDBOOK.md`,agent 不需要读那个文件。

---

## 0. 用户背景（最重要的一节,决定你的整个工作方式）

- 用户 **长期使用 AI 辅助编程**,已经用这种方式做出过实际可用的工具(数据分析、翻译流水线等),对项目结构、需求拆解、工程取舍有清晰判断。
- 但用户 **不能自己读懂代码**。这一条是硬约束,不是谦虚。他无法通过阅读你写的 Swift 代码来判断你做得对不对。
- 用户 **从未做过任何 Xcode / Swift / iOS 项目**,不熟悉 Xcode 的界面和术语(scheme、target、destination、simulator、signing、workspace)。

### 这意味着你必须改变默认行为

**1. 用户的验证手段是"行为",不是"代码"。**
所以每一步的交付,都要附带一个**用户能自己执行、自己看到结果**的验证方法。例如:
> "改完后按 ⌘R,应该看到文章右上角多出一个'翻译'按钮。如果没看到,告诉我。"

不要说"这段代码实现了 XX 功能"就结束——那句话对用户是无法验证的。

**2. 每次改动后,用大白话说清三件事:**
- 改了什么(用产品语言,不是代码语言)
- 用户按什么键、看到什么,才算成功
- 如果失败,可能是哪两三种原因

**3. 涉及 Xcode 操作时,写清楚点哪里。** 菜单路径、面板名称、按钮在屏幕哪个位置。绝不说"在项目设置里改一下"。

**4. 不要要求用户去读代码做判断。** 可以要求他:
- 确认某个文件路径是否存在
- 用 ⌘F 搜索某个字符串是否出现在文件里
- 运行某个命令并把输出贴回来
- 描述他在屏幕上看到了什么

这些是他能做的。"你看看这段逻辑对不对"是他做不到的。

**5. 你是唯一的代码质量把关人。** 没有人会 review 你的代码。因此:
- 宁可慢,不要蒙。不确定就先读文件,不要猜。
- 每次改完必须自己先 build 一次,编译不过的代码绝不交出去。
- 发现自己前面做错了,**主动说出来**并说明影响范围。用户不可能自己发现。

**6. 频繁提交,这是用户唯一的后悔药。**
每完成一个可验证的小步骤,提醒用户 commit 一次(或你代为执行,但要先说明)。因为用户无法靠读代码 debug,`git` 回滚是他唯一能自己操作的补救手段。

- **一律用中文回复。** 代码注释也用中文,写给一个读不懂代码的人看。

---

## 1. 项目是什么

这是 [NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire)(MIT,Swift,macOS + iOS)的 fork。

**唯一目标:给文章阅读界面加一个"翻译成中文"的按钮。** 点击后调用用户自建的后端翻译服务,把当前文章正文替换为中文译文。

**明确不在范围内的事:**
- 不改界面样式、配色、排版、动效
- 不加除翻译以外的任何功能
- 不做性能优化、代码清理、重构

如果用户提出范围外的需求,先提醒他这条规则,再问是否确认扩大范围。

---

## 2. 最高优先级约束:保持可 merge

这是一个 fork,**上游仍在积极开发**(2026 年 1 月刚发布 macOS 版 7.0)。用户需要长期能 `git pull upstream` 而不陷入冲突地狱。

因此,按优先级排序:

1. **优先新增文件**,放在 `Translation/` 目录下(如无此目录则创建)
2. **其次是最小化修改已有文件** —— 每次修改前,先说明"为什么这个改动无法通过新增文件实现"
3. **禁止重构任何已有代码**,包括:重命名、抽取函数、调整格式、修正你认为的 bug、更新依赖
4. **禁止修改** 与账户和同步相关的任何代码(Account / Feed / Sync 层)

> ✅ 禁区清单(Phase 0 考古后确定,用户已于 2026-07-19 确认)
> 详细依据见 `NOTES-architecture.md` 问题 7。

**A 级 —— 绝对不碰（账户 / 订阅 / 同步）**

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

**B 级 —— 本次范围外,不碰（第 1 节:只做 iOS）**

```
Mac/                        整个 macOS UI
Widget/                     小组件扩展
Intents/                    Siri / App Intents
```

**C 级 —— 数据层,碰之前必须先问用户**

```
Modules/Articles/           文章数据模型
Modules/ArticlesDatabase/   文章正文与已读状态的 SQLite 存储
```

> 说明:按第 5 节「缓存逻辑全部在后端」,Swift 侧不应该需要动这两个包。
> 若发现必须动,那是设计出了问题,**先报告,不要动手**。

**D 级 —— 允许修改,但每次改前必须说明"为什么无法通过新增文件实现"**

```
iOS/Article/WebViewController.swift        唯一的 iOS 正文装载点
iOS/Article/ArticleViewController.swift    工具栏所在
iOS/Base.lproj/Main.storyboard             按钮实体所在(XML,merge 冲突风险高)
Shared/Article Rendering/                  共享渲染层(改这里会同时影响 macOS)
```

每次动手前,先用一句话报告:"本次改动新增 N 个文件,修改 M 个已有文件,分别是……"

---

## 3. 工作方式:先考古,后动手

在这个代码库里,**你不知道的比你知道的多**。禁止在没有读过相关代码的情况下写实现。

每个阶段的流程固定为:

```
你调查 → 你产出书面结论 → 用户确认 → 你才动手
```

**不要一次性完成多个阶段。** 每完成一个 Phase 就停下,等用户说继续。

---

## 4. 分阶段任务

### Phase 0 — 代码考古(不写任何生产代码)

产出一份 `NOTES-architecture.md`,回答:

1. macOS 版和 iOS 版的文章正文,分别是由哪个文件/类负责渲染的?
2. 正文是用 WKWebView + HTML 模板渲染的吗?如果是,模板文件在哪、叫什么?
3. 现有的 CSS / 主题是怎么注入的?
4. 有没有已经存在的 JS ↔ Swift 通信机制(`WKScriptMessageHandler` 之类)?如果有,在哪、怎么用的?
5. 文章正文的 HTML 字符串,在被塞进 WebView 之前,最后经过的是哪个函数?
6. 项目用 SPM 还是 CocoaPods?有哪些 scheme?哪个 scheme 对应 macOS app、哪个对应 iOS app?
6b. **(关键)macOS 版和 iOS 版的文章渲染层共享了多少?** 具体说:HTML 模板、CSS、JS 是同一份被两边复用,还是各自一套?如果共享,共享的部分在哪个目录/framework?
   —— 这个答案决定翻译按钮应该做在哪一层。如果 HTML/JS 层是共享的,按钮做在那里两个平台同时生效;如果不共享,就只做 iOS。**这条必须给出证据,不要凭直觉判断。**
7. 根据以上,建议哪几个目录应该列入本文件第 2 节的"禁区"?

**证据要求(用户读不懂代码,所以你必须让结论可被间接核验):**

1. 每条结论给出**文件路径 + 行号**
2. 每条结论**粘贴 3–10 行真实的代码原文**(不是你的转述)
3. 每条结论后面加一句:**"用户可以这样核对:打开 XX 文件,⌘F 搜索 `YYY`,应该能找到。"**
4. 不确定的地方明确写"**不确定**",并说明还需要看什么才能确定。**禁止用推测填空。**

**这是整个项目风险最高的一步。** 后面所有工作都建立在这份笔记上,而用户无法直接验证它的正确性。宁可少答几条、多写几个"不确定",也不要给出看起来完整但其中掺了推测的结论。

### Phase 1 — 定义接口,用 mock 实现

新建 `Translation/TranslationService.swift`:

- 输入:文章的 HTML 字符串 + 文章 URL
- 输出:翻译后的 HTML 字符串
- 本阶段实现:**直接返回把每个文本节点替换成 `[译文占位]` 的 HTML**,不调用任何网络

目的是把 UI 改动和翻译逻辑解耦,先验证链路。

### Phase 2 — 接 UI(iOS,在 Simulator 里验证)

- 在文章视图上加一个"翻译"按钮
- 点击 → 调用 `TranslationService` → 用返回的 HTML 替换当前显示内容
- 要能切回原文
- **目标平台是 iOS。** 用户主要在 iPhone 上读 RSS,macOS 版不是重点
- 全程在 **iOS Simulator** 上验证,不需要真机、不需要签名配置

**按钮做在哪一层,取决于 Phase 0 问题 6b 的结论:**
- 如果 HTML/JS 渲染层是两个平台共享的 → 按钮做在那一层,顺带 macOS 也能用
- 如果不共享 → 只改 iOS 的 UI 层,不要为了"顺便"去动 macOS

用户会在 Simulator 里验证整条链路通了,再进入下一步。

### Phase 3 — 直连 LLM API(已于 2026-07-19 重新定义,见下方修订说明)

- `TranslationService` 改为直接调用 **OpenAI 兼容格式** 的 `/chat/completions` 端点
- 默认服务商:OpenRouter。服务地址与模型名做成可配置,以兼容其他第三方
- **只做 OpenAI 兼容格式**,Anthropic 原生格式暂不做
- API key 存在 `.gitignore` 排除的本地配置文件里,**暂不做设置界面**
- 加载状态、错误处理、超时
- **分块与并行调度在 Swift 侧**(详见 §5 修订)
- 术语一致性方案:**C —— 第一块先翻,其译文作为上下文传给后续并行的各块**

> ⚠️ **修订说明(2026-07-19,用户已确认)**
>
> 本节原文是「接真实后端」,并规定「分块、术语一致性、缓存等逻辑全部在后端,
> Swift 侧只负责发请求」。该规定的前提是**存在一个用户自建的后端**。
>
> 用户确认实际方案是 **app 直连 OpenRouter**,中间没有自建后端。
> OpenRouter 只是 LLM 网关,不会代为分块、保证术语一致或缓存译文。
> 因此这些职责**只能移到 Swift 侧**,原规定已失去前提。

### Phase 4 —(可选)移植到 macOS

仅当 Phase 0 发现渲染层不共享、且用户明确要求时才做。默认**不做**。

---

## 5. 技术约定

- **保结构翻译(本条是地基,不可动摇)**:绝不把整段 HTML 直接当字符串处理。
  **Swift 侧永远不解析、不修改、不拼接 HTML 结构。**
- **分块由 JavaScript 完成**。网页里有浏览器自带的完整 HTML 解析器,
  由它把正文按顶层块元素切开,Swift 只见到一个个独立的 HTML 片段。
  结构完整性由浏览器保证,不由我们的代码保证。
- **分块调度、并行控制、失败重试在 Swift 侧**。
- **API 密钥不进代码库**。存在 `.gitignore` 排除的本地配置文件里。

> ⚠️ **修订说明(2026-07-19,用户已确认)**
>
> 本节原文为「Swift 侧只负责传递,不解析、不修改 HTML 结构」,
> 并在 §4 Phase 3 规定「分块、术语一致性、缓存等逻辑全部在后端」。
>
> 因方案改为 app 直连 OpenRouter(无自建后端),后半条失去前提。
> 拆分方式:
> - ① 「Swift 不解析 HTML」是**地基**,继续严格保留 —— 靠 JS 分块来实现
> - ② 「复杂度全在后端」只是分工安排,现改为由 Swift 承担调度
>
> 判断依据:第 ① 条防的是"译文把网页结构搞烂",与后端是否存在无关,必须守住。
- 新增代码写在 **`Shared/Translation/`** 下,不要往已有的目录里塞文件。

> ⚠️ **修订说明(2026-07-19,用户已确认)**:本条原文是「写在 `Translation/` 下」,
> 即仓库根目录。经 Phase 0 考古发现该写法与第 8 节「不要修改 .xcodeproj」冲突 ——
> 本工程用 Xcode 16+ 的文件系统同步文件夹机制,只有 `Mac/ iOS/ Shared/ Modules/
> Widget/ Tests/ Technotes/ xcconfig/` 这 8 个文件夹里的新文件会被自动编译,
> **根目录不在其中**。在根目录建 `Translation/` 会导致代码根本不参与编译。
> 改用 `Shared/Translation/` 后:不需要碰 .xcodeproj,且仍是上游不存在的全新文件夹,
> merge 冲突风险为零。证据见 `NOTES-architecture.md` 末尾「重要发现」一节。
- 提交信息用中文,格式:`[翻译] 简短描述`

---

## 6. 构建与验证

```bash
# scheme 名称和 Simulator 型号在 Phase 0 考古后填入
xcodebuild -project NetNewsWire.xcodeproj -scheme <IOS_SCHEME> \
  -destination 'platform=iOS Simulator,name=<SIMULATOR_NAME>' build

# 查看可用的 Simulator:
# xcrun simctl list devices available
```

> 已验证填写(2026-07-19,实测 BUILD SUCCEEDED):
> - iOS scheme: `NetNewsWire-iOS`
> - Simulator 型号: `iPhone 17`
> - macOS scheme(备用): `NetNewsWire`
>
> 实测可用的完整命令:
> ```bash
> cd "/Users/wenbopan/Downloads/RSS ai translation"
> xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS \
>   -configuration Debug \
>   -destination 'platform=iOS Simulator,name=iPhone 17' build
> ```
>
> ⚠️ 全新 clone 后第一次编译必定失败,报 `cannot find 'SecretKey' in scope`。
> 原因:`Modules/Secrets/Sources/Secrets/SecretKey.swift` 被 .gitignore 排除,
> 由编译期脚本生成,但生成时机晚于 Secrets 模块的编译。
> 解决:再编译一次即可,或先跑 `./buildscripts/updateSecrets.sh`。**不要去改那两个报错的文件。**

**每次改完代码,先自己跑一次 build,确认能编译过再交给用户。** 不要把编译不过的代码交出去。

---

## 7. 你应该主动做的事

- 发现自己在猜测时,**停下来说"我需要先读 XX 文件"**,而不是继续写
- 发现一个改动会导致大量已有文件被修改时,**先报告并给出替代方案**
- 用户提出的做法如果会破坏第 2 节的约束,**直接指出**,不要照做

## 8. 你不应该做的事

- 不要为了"顺手"改任何范围外的代码
- 不要添加测试框架、CI 配置、格式化工具
- 不要 `git commit` 或 `git push`,除非用户明确要求
- 不要修改 `.xcodeproj` 文件里的构建设置,除非用户明确要求并且你解释清楚了改了什么
