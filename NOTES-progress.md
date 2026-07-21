# NOTES-progress.md — 项目进度与交接

> **这是接手本项目的第一份必读文件。**
> 读完本文件,你应该知道:项目做到哪了、哪些已验证、哪些悬而未决、下一步是什么。
> 配套文件:`CLAUDE.md`(规则) → `NOTES-architecture.md`(代码考古) →
> `NOTES-lessons.md`(踩过的坑) → `NOTES-todo.md`(已知问题)。
>
> **维护纪律(对任何接手的 AI):每完成一个可验证的步骤、每做一个重要决定、
> 每发现一个坑,立刻更新对应文件。不要攒到最后。** 详见 CLAUDE.md 第 9 节。

最后更新:2026-07-19

---

## 一、项目一句话

给 NetNewsWire iOS 版加一个「翻译成中文」按钮,直连 OpenRouter(OpenAI 兼容格式),
分组并行翻译、逐块显示、本地缓存。fork 自上游 `Ranchero-Software/NetNewsWire`,
必须长期保持可 merge(最高优先级约束,见 CLAUDE.md 第 2 节)。

## 二、阶段进度

| 阶段 | 状态 | 说明 |
|---|---|---|
| 第 0 步 环境跑通 | ✅ 完成 | Xcode 26.6 / iPhone 17 模拟器 / scheme `NetNewsWire-iOS` |
| Phase 0 代码考古 | ✅ 完成 | 产出 `NOTES-architecture.md`,7 个问题全部回答并经用户确认 |
| Phase 1 服务接口 + mock | ✅ 完成 | `TranslationService` 协议 + `MockTranslationService` |
| Phase 2 iOS 翻译按钮 | ✅ 完成 | 路线 B(JS 原地替换正文),用户 5 项验收通过 |
| Phase 3 直连 OpenRouter | 🟡 **代码完成,等待用户最终验收** | 见下方「当前悬而未决」 |
| Phase 4 macOS 移植 | ❌ 默认不做 | 仅当用户明确要求 |

## 三、git 状态(2026-07-19)

**已推送 GitHub(`Dime2015/NetNewsWire_AITranslation`,main 分支):**

```
15191e95a  [翻译] 修复:用按钮切换文章时翻译按钮状态不重置
545f63678  [翻译] Phase 2 完成:iOS 文章页加入翻译按钮
c46d1ce8c  [翻译] Phase 0 考古笔记 + Phase 1 翻译服务接口与 mock 实现
3cc360839  [翻译] 填入已验证的 iOS scheme、模拟器型号与首次编译踩坑说明
08d10f501  ← 上游基线 commit
```

**仅本地、未推送:**

```
7cce26cd1  [翻译] 修订 CLAUDE.md:方案由自建后端改为直连 OpenRouter
```

**⚠️ 工作区有大量未提交改动(等用户验收 Phase 3 最新一轮后一起提交):**

- Phase 3 全部实现(OpenAI 兼容 HTTP 层、分组并行、事后自检)
- Keychain 存 API key + 设置界面两个入口(翻译模型 / 翻译 API Key)
- 用户第一轮实测反馈的 4 个修复(按钮状态、中英对照清洗、失败重试、标题翻译)
- 用户第二轮实测反馈的改造(渐进式分组、标题与先导块同发、本地缓存)
- 文档更新(CLAUDE.md、NOTES-todo.md、本文件、NOTES-lessons.md)

## 四、当前悬而未决(接手者先看这里)

0. **🔴 刚完成,等用户实机验收(2026-07-21):界面汉化阶段 1**
   - 436 条字符串注入 4 个 .xcstrings(只增行,逐 key 校验原内容零改动)
   - `iOS/zh-Hans.lproj/Main.strings` 9 条(纯新增文件)
   - 新增「设置 → 外观 → 界面语言」:跟随系统 / 简体中文 / English,切换后需重启 app
   - 建立可复用流水线 `i18n/inject.py` + 手册 `NOTES-i18n.md`,加新语言只需 4 条命令
   - 双平台编译通过;模拟器实测中文生效(日期变 `2026年7月9日`)
   - **未做**:Settings/Account/Add/Inspector 四个 storyboard 共 78 条
     (它们未本地化,需先移动上游文件,风险较高,待用户决定)
1. **✅ 已修复并确认(2026-07-21)**:工具栏两个 customView 按钮
   (阅读视图 + 翻译)同时消失且不再恢复。原因是缺尺寸约束被压成 0 宽,
   详见 NOTES-lessons **L19**。已加 44×44 约束,日志层面验证:
   修复前 40 次 `ButtonWrapper width == 0` 冲突 → 修复后 0 次。
   **需要用户按原复现方式(反复进文章/退列表/点阅读视图)确认症状消失。**
1. **等用户验收(2026-07-19 第四轮)**:三项新改动,双平台编译通过,待实测:
   - T5 对策1:OpenRouter 请求加 `provider: {sort: throughput}`,治 80s 级尾延迟
   - 按钮角标点替代灰底:实心点=完整缓存,空心点=未完成缓存(用户嫌灰底丑)
   - **断点续翻**:翻到一半被打断(翻页/取消/部分失败)→ 已翻好的组存成
     "未完成缓存";下次点翻译,已翻的组零请求复用,只翻剩下的。
     防串号保护:runID 序号,快速切文章时宁可放弃保存也不张冠李戴
2. 第三轮(渐进分组/自检/指纹修复)已验收提交:`52946ded5`,已推 GitHub
3. 其余待办:见 `NOTES-todo.md`(T1 按钮视觉粘连;T5 观察 provider 路由效果)
4. 缓存指纹修复(L18)与断点续翻均需**长期使用观察**

## 五、翻译功能架构速览(细节看代码注释,都是中文)

```
点按钮 → TranslationController.performToggle()
  ├─ 查 TranslationCache(文章+模型+原文哈希) → 命中则秒开,零请求
  ├─ translation.js splitBody() 切组:先导块500字符 → 第1组1000 → 逐组翻倍,4000封顶
  ├─ 标题 + 先导块 同时发出(标题最短最快回)
  ├─ 先导块译文作为"术语示范"传给后续组(一致性方案 C)
  ├─ 其余组并行(最多4并发),谁回来谁替换(applyGroup),失败自动重试1次
  ├─ 事后自检 findGroupsNeedingRetranslation():纯本地判断
  │    ①还是英文?(中文字符<5%且英文字母>40%) ②混进原文?(原文中段60字符探针)
  │    → 查出的组重翻一轮
  └─ 全部成功 → 写缓存;有失败 → 按钮变⚠️,lastErrorMessage 记录人话说明
```

**文件清单(全部在 `Shared/Translation/`,上游不存在此目录):**

| 文件 | 职责 |
|---|---|
| `TranslationService.swift` | 协议 + 错误定义 + mock |
| `OpenAICompatibleTranslator.swift` | HTTP 请求、提示词、输出清洗 |
| `TranslationController.swift` | 编排:分组、并发、重试、自检、缓存、按钮状态 |
| `TranslationConfig.swift` | 模型列表(写死)、baseURL、选中模型(UserDefaults) |
| `TranslationKeychain.swift` | API key 存取(系统 Security 框架,**没用上游的 Secrets 模块**) |
| `TranslationCache.swift` | 译文缓存(内存+磁盘 Caches,上限50篇) |
| `TranslationModelPickerViewController.swift` | 设置→翻译模型 选择页 |
| `TranslationAPIKeyViewController.swift` | 设置→翻译 API Key 填写页 |
| `translation.js` | 网页内:切组、替换、自检、还原(所有 HTML 解析都在这层) |

**动过的上游文件(只有 3 个,改动全部带 `[翻译]` 注释标记,⌘F 可查):**

| 文件 | 改动方式 |
|---|---|
| `iOS/Article/WebViewController.swift` | 纯末尾追加(JS 桥接扩展) |
| `iOS/Article/ArticleViewController.swift` | 3 处单行插入 + 末尾追加(按钮安装/状态重置) |
| `iOS/Settings/SettingsViewController.swift` | 4 处中间插入(设置里的两行入口) |

## 六、构建与验证命令(实测可用)

```bash
cd "/Users/wenbopan/Downloads/RSS ai translation"

# iOS(主要目标)
xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire-iOS \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build

# macOS(每次改 Shared/ 后必须跑,验证没弄坏它;需要免签名参数)
xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  ENTITLEMENTS_REQUIRED=NO build
```

⚠️ 全新 clone 后第一次 iOS 编译必失败(`SecretKey` 不存在),再编译一次即可。详见 NOTES-lessons L1。

## 七、用户如何使用(验收时照此操作)

1. 设置 → Articles → 「翻译 API Key」→ 填 OpenRouter key(存 Keychain,不进代码库)
2. 设置 → Articles → 「翻译模型」→ 5 个可选,默认 deepseek-v4-flash
3. 文章页底部工具栏最右侧气泡按钮:点=翻译/回原文;翻译中再点=取消
