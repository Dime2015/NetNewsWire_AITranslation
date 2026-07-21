# NOTES-progress.md — 项目进度与交接

> **这是接手本项目的第一份必读文件。**
> 读完本文件,你应该知道:项目做到哪了、哪些已验证、哪些悬而未决、下一步是什么。
> 配套文件:`CLAUDE.md`(规则) → `NOTES-architecture.md`(代码考古) →
> `NOTES-lessons.md`(踩过的坑,21 条) → `NOTES-todo.md`(已知问题) →
> `NOTES-i18n.md`(多语言工程手册)。
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
| **装到真机** | ⏳ **下一步,有前置条件** | 见第四节 |

## 三、git 状态(2026-07-21)

**本地与 GitHub(`Dime2015/NetNewsWire_AITranslation` main)完全同步,工作区干净。**

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

所有 Swift 改动都带 `[翻译]` 注释标记,⌘F 可盘点。

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
