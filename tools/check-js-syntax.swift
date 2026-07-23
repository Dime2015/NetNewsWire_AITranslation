// tools/check-js-syntax.swift
//
// [工具] 本 fork 新增。检查注入到正文页的那些 .js 文件**能不能被解析**。
//
// ## 为什么需要它
//
// 这些脚本是运行时才注入网页的,**Xcode 编译不会看它们一眼** ——
// 语法写错了照样编译成功、照样装机成功,只有在真机上打开文章时才悄悄失效,
// 而且失效得很安静:页面还在、文字还有,只是我们加的那层样式/功能全没了。
//
// 真实事故(2026-07-23,教训 L32 的第二次重演):
// 往 `nnw_appearance.js` 的样式模板字符串里加注释时用反引号包了一个代码名,
// **提前终结了字符串** → 整个脚本语法错误 → 正文页所有自定义样式静默失效。
// 因为正文背景那时已改由 UIKit 画,肉眼看不出异常,直到用户报"播客条布局乱了"才暴露。
//
// ## 怎么用
//
//     swift tools/check-js-syntax.swift            # 检查全部注入脚本
//     swift tools/check-js-syntax.swift 某个.js     # 只检查指定文件
//
// **改完任何 .js 都跑一次**,和 xcodebuild 一样是交付前的必做项。
//
// ## 原理
//
// 用 JavaScriptCore 的 `new Function(源码)` —— 它**只解析、不执行**,
// 所以脚本里引用 document / window 这些浏览器专有的东西不会误报。

import Foundation
import JavaScriptCore

/// 上游 WebViewConfiguration.swift 的 iOS 分支里注入的、属于本 fork 的脚本。
/// (上游自带的 main / newsfoot 不在此列 —— 那些不归我们维护。)
let defaultTargets = [
	"Shared/Appearance/nnw_appearance.js",
	"Shared/Podcast/nnw_podcast.js",
	"Shared/YouTube/nnw_youtube.js",
	"Shared/Translation/translation.js"
]

let args = Array(CommandLine.arguments.dropFirst())
let targets = args.isEmpty ? defaultTargets : args

guard let context = JSContext() else {
	print("❌ 起不来 JavaScript 引擎")
	exit(2)
}

var failed = 0

for path in targets {
	guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
		print("❌ \(path) —— 读不到这个文件")
		failed += 1
		continue
	}

	context.setObject(source, forKeyedSubscript: "NNW_SOURCE" as NSString)
	// new Function 只把源码解析成函数体,不会真的执行它
	let check = """
	(function () {
		try { new Function(NNW_SOURCE); return "OK"; }
		catch (e) { return "ERR:" + e.toString(); }
	})()
	"""
	let result = context.evaluateScript(check)?.toString() ?? "ERR:引擎没有返回结果"

	let name = (path as NSString).lastPathComponent
	if result == "OK" {
		let lines = source.components(separatedBy: .newlines).count
		print("✅ \(name)(\(lines) 行)")
	} else {
		print("❌ \(name) —— \(result.dropFirst(4))")
		// 未终结的模板字符串是本项目最常见的那种错(L32),单独点名一下修法
		if result.contains("Unexpected") || result.contains("Unterminated") {
			print("   提示:检查是不是在模板字符串(反引号包住的那段)里的**注释**中用了反引号 —— ")
			print("   那会提前终结字符串。本项目里代码名请用「」括起来,不要用反引号。")
		}
		failed += 1
	}
}

print(failed == 0 ? "\n全部通过。" : "\n有 \(failed) 个文件解析不了,修完再交。")
exit(failed == 0 ? 0 : 1)
