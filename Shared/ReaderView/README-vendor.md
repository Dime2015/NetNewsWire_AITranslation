# Shared/ReaderView/ —— 第三方文件说明

本目录里的 `Readability.js` 是**原封不动搬进来的第三方代码**,
是本项目引入的**第一个** vendored 文件。规矩在这里一次说清。

## Readability.js

| 项 | 值 |
|---|---|
| 来源 | https://github.com/mozilla/readability |
| 取用的文件 | 仓库根目录的 `Readability.js` |
| 下载地址 | https://raw.githubusercontent.com/mozilla/readability/main/Readability.js |
| 取用日期 | 2026-07-21 |
| 对应 commit | `ab4027a8b376`(2026-07-09) |
| SHA-256 | `e9330028c8a5a4aa7d75147be2605d520f7f213c7b28474947dc0e9c984e9bed` |
| 许可证 | **Apache License 2.0** |
| 大小 | 约 89 KB |

这就是 **Firefox 阅读模式**背后的那个库。

## 规矩

1. **不要手改这个文件。** 一个字符都不要。
   需要调整行为的话,改我们自己的 `ReaderViewExtractor.swift` 或调用时传的 options,
   不要改库本身 —— 否则以后升级会把你的改动冲掉,而且没人记得改过什么。
2. **升级 = 整个文件替换**,然后回来更新上面表格里的日期、commit、SHA-256。
3. **文件头部的 Apache 2.0 许可证声明不许删。** Apache 2.0 要求保留它。
4. 这个文件**只被 `ReaderViewExtractor` 注入到"外部网页"里用**,
   **绝不能**加进 `WebViewConfiguration.articleScripts` ——
   那个清单里的脚本会注入到我们自己的文章渲染页上,不是这个文件该去的地方。

## 为什么需要它

上游的「阅读视图」按钮原本调用 Feedbin 的付费解析服务,
需要 `mercuryClientID` / `mercuryClientSecret` 两个密钥 ——
它们是 NetNewsWire 官方买的,开源仓库里是空的,所以这个功能在我们的构建里**从来就是坏的**。

改成在本机用 Readability.js 提取后:不需要服务器、不需要密钥、不会过期、
不把你读了什么告诉任何第三方。

详见 `NOTES-progress.md` 与 CLAUDE.md 第 2 节。
