# NOTES-progress.md — 项目进度与交接

> **这是接手本项目的第一份必读文件。**
> 读完本文件,你应该知道:项目做到哪了、哪些已验证、哪些悬而未决、下一步是什么。
> 配套文件:`CLAUDE.md`(规则) → `NOTES-architecture.md`(代码考古) →
> `NOTES-lessons.md`(踩过的坑,30 条) → `NOTES-todo.md`(已知问题) →
> `NOTES-i18n.md`(多语言工程手册)。
>
> ⚠️ **动手前务必先看 CLAUDE.md 第 0 节第 7 条**:
> **不要用「操作电脑」去点模拟器做验收**(2026-07-21 用户明确要求,太慢太费)。
> 编译、装模拟器、看日志、查数据库照旧由你做;**界面上的点按与验收交给用户截图**。
>
> **维护纪律(对任何接手的 AI):每完成一个可验证的步骤、每做一个重要决定、
> 每发现一个坑,立刻更新对应文件。不要攒到最后。** 详见 CLAUDE.md 第 9 节。

最后更新:2026-07-21

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
| 界面:**正文阅读页** | 🔜 **下一步** | 通道已铺好(`nnw_appearance.js`),尚未做实质改动 |
| 装到真机 | ⏳ 排在界面之后 | Apple ID 已登录;剩余前置条件见第四节 |

## 三、git 状态(2026-07-21 晚)

**工作区干净。本地领先 GitHub 12 个提交(`Dime2015/NetNewsWire_AITranslation` main),
需要时 `git push`。**

本轮(界面改造)新增的提交,从新到旧:

```
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

### 🔜 下一步:改**正文阅读页**

用户 2026-07-21 晚明确说下一段工作是**文章阅读页面**,并会另开对话窗口。

**通道已经铺好、验证过、且到目前为止还没被用来做任何实质的样式改动** ——
`Shared/Appearance/nnw_appearance.js` 里的 `STYLE` 现在只有一条
「藏掉 Substack 图片按钮」的规则,其余都是注释。

**改正文页的样子 = 往那个 `STYLE` 里写 CSS。上游文件一个字都不用动。**
文件顶部的注释里列全了可用的选择器(`.articleTitle` / `#bodyContainer` / 等等),
以及两个已经踩过的坑(标题颜色在 `.articleTitle a` 上不在 `h1` 上;
样式必须插进 `<head>` 否则会被上游 `main.js` 删掉)。

⚠️ 两条硬约束:
1. **只改样式,不要动 DOM 结构** —— `#bodyContainer`、`.articleTitle` 是翻译功能的命脉(L12)
2. **不要拆图片外面的 `<a>`** —— 系统长按菜单靠它才存在(见 T12)

**iOS 没有正文字号滑块**(那是 macOS 专属),iOS 的正文字号跟随系统动态字体,
由 `ArticleRenderer.styleSubstitutions()` 注进 CSS 的 `font-size`。
想固定字号就在我们这层 CSS 里覆盖(见 L23 末尾)。

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

翻译功能的改动带 `[翻译]` 标记,界面改造带 `[界面]` 标记,
阅读视图带 `[阅读视图]` 标记,⌘F 可分别盘点。

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
