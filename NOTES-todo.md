# NOTES-todo.md — 已知问题与待办

> 这里记录**已经发现、但决定暂时不修**的问题。
> 目的:防止"先放一放"变成"永远忘了"。
> 每条都写清楚:现象、原因、什么时候修、为什么现在不修。

---

## T1 · 翻译按钮与相邻按钮视觉粘连,工具栏被撑宽

**状态**:✅ 已解决(2026-07-21)

**解决方式**:把工具栏从三组改为两组。

iOS 26 的 Liquid Glass 工具栏按 flexibleSpace 把按钮切成若干玻璃胶囊,
剩余宽度由弹性间隔平分。上游原本三组
`[已读 星标] | [下一篇未读] | [阅读视图 分享]`,我们加入第 6 个按钮后,
两个间隔各自只剩 40pt 出头,相邻胶囊边缘几乎相接 —— Liquid Glass 会把
靠近的玻璃融合,视觉上就是粘成水滴。

改为两组后剩余宽度全部给中间一个间隔,分隔清晰:
`[已读 星标 下一篇未读] ⟷ [阅读视图 分享 翻译]`
(左=这篇文章的状态与去向,右=拿这篇文章做点什么)

实现位于本 fork 的 `installTranslationButton()`,只在 iOS 26 分支重排,
旧系统分支保持上游的均匀分布布局。已截图确认两个胶囊分离。

---

### 原始记录(保留)

**状态**:待修复
**发现时间**:2026-07-19,Phase 2 验收时由用户发现
**严重程度**:纯视觉,不影响功能

### 现象

底部工具栏加入翻译按钮后:
1. 整条工具栏变宽了
2. 翻译按钮和左边那个"下一篇未读"(圆圈里的下箭头)看起来像水滴一样粘连在一起

### 原因

iOS 26 的 Liquid Glass 工具栏会把相邻的 bar button item 自动吸附成一个胶囊分组。
当前实现是把翻译按钮**追加到 toolbarItems 数组末尾**
(`iOS/Article/ArticleViewController.swift` 末尾的 `installTranslationButton()`),
系统就把它和前一个按钮归进了同一组。

### 为什么现在不修

Phase 3 接入真实后端后,按钮可能需要更多状态展示(进度、错误提示等),
届时按钮在工具栏里的位置和形态**很可能要重新设计一次**。
现在修等于修两遍。

### 修的时候该怎么做

需要调整按钮的插入位置而不是简单 append。参考上游自己的做法:
`iOS/Article/ArticleViewController.swift` 里 iOS 26 分支用的是
`toolbarItems?.insert(articleExtractorBarButtonItem, at: 5)`,即插入到特定索引。
但索引 5 的实际含义**尚未实测确认**(见 NOTES-architecture.md 🔴 第 1 条),
修之前需要先跑起来打印 `toolbarItems` 看清楚真实顺序。

---

## T4 · 离开文章再返回,译文丢失,需要重新翻译

**状态**:✅ 已解决(2026-07-19,本地缓存落地)
**发现时间**:2026-07-19,Phase 2 验收后由用户提出

**解决方式**:新增 `Shared/Translation/TranslationCache.swift`。
译文按「文章 ID + 模型 + 原文哈希」缓存在内存 + 磁盘(系统 Caches 目录,上限 50 篇,删最旧)。
再次打开已翻译过的文章并点翻译按钮 → 命中缓存,秒开、零请求。

设计要点:
- 只缓存**全部成功**的翻译;中途取消或有失败组的不缓存,避免固化残缺版本
- 换模型会重新翻译(键里含模型名,有意的 —— 便于对比模型效果)
- 文章内容更新后键会变,不会拿旧译文冒充新内容
- 未触碰 Modules/ArticlesDatabase(C 级禁区),缓存文件与上游数据库零交集

### 现象

翻译文章 A → 跳到上一篇/下一篇 → 再返回 A → A 显示原文,按钮为"未翻译"。

### 这不是 bug

译文存在于**网页的 DOM 里**(路线 B 的做法)。返回文章时 NetNewsWire 会重新渲染页面,
新页面是全新的 JS 环境,译文自然不存在。按钮显示"未翻译"与页面实际内容**一致**,
没有状态错乱。

但这也不是刻意的产品设计 —— 是路线 B 的固有后果,选型时未预先说明。

### 为什么现在不处理

用 mock 时重翻只要 1 秒,无感。接入真实后端后,每次返回 = 一次真实翻译请求,
才会变成实际问题(耗时、可能产生费用)。

**选哪个方案取决于后端的真实速度与成本,而这些数字目前不存在。**

### 三个候选方案

- **A(默认)**:什么都不做,每次重新请求。若后端自带缓存则第二次很快,
  完全符合 CLAUDE.md 第 5 节「缓存逻辑全部在后端」。**零代码改动。**
- **B**:Swift 侧内存缓存译文,返回时直接重新应用。体验最好,
  但在 Swift 侧存译文与第 5 节有擦边,需要用户确认。
- **C**:只记住"这篇翻译过"的标记,返回时自动重新请求一次。
  体验上像"记住了",但仍有网络开销。

**Phase 3 后端跑通、拿到真实耗时数据后再决定。**

---

## T5 · 个别组的翻译耗时呈数倍波动(尾部延迟)

**状态**:待处理(下一个优先级,2026-07-19 用户实测数据确认)
**严重程度**:体验问题 —— 一个慢组会卡住顺序阅读

### 现象(用户实测日志,同一篇文章、同一模型)

```
组4 第1次:完成,耗时 22.2s,原文 4326 字符
组5 第1次:完成,耗时 81.6s,原文 4374 字符   ← 尺寸相同,耗时 4 倍
```

### 数据能排除什么

- 不是切分问题:渐进分组已生效(组1=1243字符/4.1s 最先回,顺序基本正确)
- 不是模型本身性能:组4 和组5 尺寸几乎一样,同模型,耗时差 4 倍 → 是**服务端方差**
  (OpenRouter 会把请求路由到不同 provider,各家速度差异巨大,还有排队)

### 候选方案(按性价比排序)

1. ✅ **已实施(2026-07-19)**:请求体里加 provider 偏好 `"provider": {"sort": "throughput"}` ——
   让 OpenRouter 优先路由到吞吐量高的服务商(只对 openrouter 域名发送,其他服务商不认识此字段)。
   **观察中:用户日志里 80s 级异常值是否消失。**
2. **对冲请求(hedging)**:某组耗时超过已完成组中位数的 2~3 倍时,
   再发一个同样的请求,谁先回用谁。经典尾延迟对策;代价是偶尔多花一次请求的钱。
   **若方案 1 观察后仍有异常值再上。**
3. 缩小 maxGroupChars(4000→3000):治标,收益有限,先不动。

### 相关缓解(2026-07-19 同轮实施)

断点续翻上线后,慢组卡住时用户翻页离开的代价大幅降低 ——
已翻好的组存成"未完成缓存",回来点一下接着翻,不重复花钱。

---

## T6 · 装到真机需要代码签名(前置条件,尚未做)

**状态**:待办,**排在界面改造之后**(2026-07-21 用户明确选择先改界面)
**记录时间**:2026-07-21

> ⏳ **可以提前做掉的一件事(需要用户本人操作,AI 做不了)**:
> 打开 Xcode → 菜单 `Xcode → Settings → Accounts` → 左下角 `+` → 用 Apple ID 登录。
> 登录后才能拿到 Team ID,才能填下面那个 `DeveloperSettings.xcconfig`。
> 界面改完就能直接进真机环节,不用再等。

模拟器不需要签名,真机需要 —— 这是本项目至今一直绕开的东西。

### 已查证的事实

工程默认写死了上游作者的身份,**必须覆盖**
(`xcconfig/common/NetNewsWire_codesigning_common.xcconfig`):

```
ORGANIZATION_IDENTIFIER = com.ranchero
DEVELOPMENT_TEAM = M8L2WTLA8W        ← Ranchero 自己的 team,不是我们的
```

覆盖方式:在**仓库外面**新建(工程用 `#include?` 可选包含,不存在也不报错):

```
/Users/wenbopan/Downloads/SharedXcodeSettings/DeveloperSettings.xcconfig
```

内容:

```
DEVELOPMENT_TEAM = <你的 Team ID>
ORGANIZATION_IDENTIFIER = <自己的反向域名,例如 com.wenbopan>
CODE_SIGN_STYLE = Automatic
DEVELOPER_ENTITLEMENTS = -dev
PROVISIONING_PROFILE_SPECIFIER =
```

bundle id = `$(ORGANIZATION_IDENTIFIER).NetNewsWire.iOS$(BUNDLE_ID_SUFFIX)`,
改 ORGANIZATION_IDENTIFIER 即可避开与上游/App Store 版冲突。

`DEVELOPER_ENTITLEMENTS = -dev` 切到精简权限文件,差异已核对:

| 文件 | 包含的权限 |
|---|---|
| `NetNewsWire.entitlements`(默认) | iCloud/CloudKit、推送、App Groups、钥匙串组 |
| `NetNewsWire-dev.entitlements` | **只有** App Groups、钥匙串组 |

即真机 dev 版没有 iCloud 同步和推送。用户用本地账户(我的 iPhone),不受影响。

### 🔴 尚未验证的关键点

- **免费 Apple ID(个人团队)能否签 App Groups 权限?** 若不能,需进一步精简 entitlements。
- 免费账号签出的 app **7 天过期**,需每周用 Xcode 重装;付费($99/年)为 1 年。

按 L3 的纪律:**先真机跑一次让 Xcode 报错说话,不要凭推测下结论。**

### 顺带注意

翻译用的 API key 存在 Keychain 里,**不会跟着代码走** ——
装到手机后需要在设置里重新填一次。

---

## T8 · app 图标在「色调」主屏外观下是一块白板

**状态**:待定 —— 需要用户决定要不要做一张深底的单色版
**发现时间**:2026-07-21,换图标后实测三种主屏外观时发现

### 现象

主屏长按 → 编辑 → 自定 → **色调**(iOS 会把所有图标变成同一个色系的单色图):
别的 app 图标都变成了蓝色调,**只有 NetNewsWire 还是白底黑字**,一排蓝里突兀的一块白板。

浅色、深色两种外观都正常,只有「色调」这一种有问题。

### 原因(已用编译产物核实,不是推测)

`xcrun assetutil --info` 查 `Assets.car`,里面只有「默认」和「深色」两份图 ——
**单色版是 iOS 自己生成的**:把图转成灰度,再按用户选的色调上色。

我们这张图是**浅底**(报纸白底 + 黑色 R),转成灰度后几乎全白,
上色后自然停在色阶最亮的一端,看起来就没被上色。

**这不是配置写错了,是原图性质决定的。** 试过把「单色」那条从 Contents.json 里
删掉让系统自己生成 —— 结果一样,因为系统的输入还是这张浅底图。

### 怎么修(需要用户提供素材)

做一张**深底浅字**的灰度版(例如黑底、白色 R),放进
`AppIconCustom.appiconset` 并在 Contents.json 里加回 `luminosity: tinted` 那条。
iOS 会按它的亮度分布上色,深色区域吃色、浅色区域变亮,才是正常的单色图标观感。

### 为什么现在不修

用户 2026-07-21 明确选了「三处都用这一张,先这样」。
而且「色调」是主屏的一个可选外观,**用户自己不一定会开**。
等用户看过截图再决定要不要补素材。

---

## T7 · 界面改造:大字号(无障碍)布局是另一套代码,改默认布局时容易漏

**状态**:未踩到,但已确认存在 —— 记下来防止以后翻车
**记录时间**:2026-07-21

`MainTimelineCellLayout.swift` 里有**两套**布局:

| 结构 | 何时生效 |
|---|---|
| `MainTimelineDefaultCellLayout` | 平时 |
| `MainTimelineAccessibilityCellLayout` | 系统字号调到「辅助功能」档位时 |

切换点在 `MainTimelineCell.updatedLayout()`:
`traitCollection.preferredContentSizeCategory.isAccessibilityCategory`。

两套的**元素顺序都不一样**(无障碍版把日期换行放到订阅源名下面,不是右对齐)。

**风险**:以后调列表布局时,如果只改了默认那套,用户一旦把系统字号调大,
就会看到一个完全没改过的旧样子,而且**我们平时的验证根本不会触发那条分支**。

**怎么办**:
- 已铺的 `TimelineStyle.swift` 里的常量**两套都在用**,所以纯改数值(字号、颜色、间距)
  两套会同时生效,不用担心。
- 但如果将来要改的是**结构**(挪位置、增删元素),必须两套都改,并且实测:
  模拟器里 `设置 → 辅助功能 → 显示与文字大小 → 更大文字` 拉到最大,再看列表。

---

## T2 · 旧版 iOS 的工具栏分支无法验证

**状态**:已知限制,可能永远不修
**严重程度**:低(用户自己只用 iOS 26)

`installTranslationButton()` 里有一个 `if #unavailable(iOS 26)` 分支,
用于在更早的系统上手动补 flexibleSpace 间隔。

用户的模拟器是 iOS 26.5,**只能验证 iOS 26 那条分支**。
旧系统分支是按同样逻辑写的,但从未实际运行过。

若将来需要支持旧系统,必须先在旧版模拟器上实测。

---

## T3 · macOS 版无法用常规方式编译验证

**状态**:环境限制,非代码问题
**严重程度**:低(macOS 不在项目范围内)

macOS target 需要 Apple 开发者签名才能编译,用户没有配置:

```
error: No profiles for 'com.ranchero.NetNewsWire-Evergreen-DEBUG' were found
```

**绕过方法**(已验证有效,2026-07-19 实测 BUILD SUCCEEDED):

```bash
xcodebuild -project NetNewsWire.xcodeproj -scheme NetNewsWire \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  ENTITLEMENTS_REQUIRED=NO build
```

**每次改动 `Shared/` 下的文件后,都应该用这条命令验证一次**,
因为 `Shared/` 会被 macOS 版一起编译,写错了 iOS 这边发现不了。
