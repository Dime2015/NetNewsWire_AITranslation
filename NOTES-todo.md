# NOTES-todo.md — 已知问题与待办

> 这里记录**已经发现、但决定暂时不修**的问题。
> 目的:防止"先放一放"变成"永远忘了"。
> 每条都写清楚:现象、原因、什么时候修、为什么现在不修。

---

## T1 · 翻译按钮与相邻按钮视觉粘连,工具栏被撑宽

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
