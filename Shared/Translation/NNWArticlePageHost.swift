//
//  NNWArticlePageHost.swift
//  NetNewsWire — AI 翻译 fork
//
//  [翻译] 本 fork 新增,上游没有这个文件。试读 Phase C(2026-07-30)。
//
//  ## 这是什么:「文章页宿主」协议 —— 翻译 / 长图与页面之间的唯一接口
//
//  翻译控制器(TranslationController)和长图导出器(ArticleLongImageExporter)
//  原本直接抓着 WebViewController 用。试读页(FeedPreviewArticleViewController)
//  也要这两个功能,于是把它们对页面的全部依赖收敛成这个协议:
//
//      nnwHostArticle    这一页在读哪篇文章(缓存键、标题都从它来)
//      nnwHostWebView    对哪个 WKWebView 执行 JS
//      nnwTranslationTitleDidChange(_:)  标题译文就位/还原时,通知页面同步它的原生标题
//                        (主阅读页 = 阅读栏的 titleOverride;试读页网页表头直接可见,空实现)
//
//  下面的桥接方法**原样搬自 WebViewController.swift 尾部的 fork 追加段**
//  (那边现在只剩一个 6 行的 conformance)。桥接全是「对 webView 跑 JS」,
//  和页面是谁无关 —— 这正是能抽出来的原因。
//
//  ⚠️ 搬家不改行为:方法名、JS 调用、注释一律保持原样,git blame 能对上老账。
//

#if os(iOS)

import UIKit
import WebKit
import Articles

/// 能承载翻译 / 长图的文章页。约束到 UIViewController:
/// 导出器要读 traitCollection,错误提示要从页面上弹。
@MainActor protocol NNWArticlePageHost: UIViewController {

	/// 这一页正在展示的文章(nil = 还没有文章,一切操作静默跳过)
	var nnwHostArticle: Article? { get }

	/// 这一页的网页视图(nil = 还没建好)
	var nnwHostWebView: WKWebView? { get }

	/// 标题译文就位(text)或还原(nil)时的通知:页面若在网页之外自绘了标题
	/// (主阅读页的阅读栏),在这里同步;没有就给空实现。
	func nnwTranslationTitleDidChange(_ text: String?)
}

extension NNWArticlePageHost {

	/// 读取当前页面里的文章正文 HTML。找不到正文容器时返回 nil。
	func nnwTranslationReadBody() async throws -> String? {
		try await nnwTranslationEnsureScriptInjected()
		return try await nnwTranslationEvaluateReturningString("window.nnwTranslation.readBody()")
	}

	/// 把页面里的正文替换成译文。返回 true 表示替换成功。
	func nnwTranslationApply(_ translatedHTML: String) async throws -> Bool {
		try await nnwTranslationEnsureScriptInjected()
		let literal = try nnwTranslationJavaScriptStringLiteral(translatedHTML)
		return try await nnwTranslationEvaluateReturningBool("window.nnwTranslation.apply(\(literal))")
	}

	/// 让网页把正文切成若干组,返回 JSON 字符串 [{"group":0,"html":"..."}, ...]。
	/// 找不到正文容器时返回 nil。
	///
	/// - Parameters:
	///   - leadChars: 第 0 组(先导块)的目标字符数。它单独先翻,让用户尽快有东西可读。
	///   - firstGroupChars: 第 1 组的目标字符数。之后逐组翻倍 —— 读者顺序阅读,
	///     越靠前的组越要小而快,越靠后的组越可以大而省。
	///   - maxGroupChars: 单组字符上限。超长文章会自动多分几组,避免单次输出被截断。
	func nnwTranslationSplitBody(leadChars: Int, firstGroupChars: Int, maxGroupChars: Int) async throws -> String? {
		try await nnwTranslationEnsureScriptInjected()
		return try await nnwTranslationEvaluateReturningString(
			"window.nnwTranslation.splitBody(\(leadChars), \(firstGroupChars), \(maxGroupChars))")
	}

	/// 某一组的译文回来了,替换掉这一组。
	func nnwTranslationApplyGroup(group: Int, translatedHTML: String) async throws -> Bool {
		try await nnwTranslationEnsureScriptInjected()
		let literal = try nnwTranslationJavaScriptStringLiteral(translatedHTML)
		return try await nnwTranslationEvaluateReturningBool("window.nnwTranslation.applyGroup(\(group), \(literal))")
	}

	/// 事后检查:哪些组还是英文、或者混进了英文原文,需要重翻。
	/// 纯本地判断,不发请求、不花钱。
	/// 返回 JSON 字符串 [{"group":3,"html":"<原文>"}, ...]。
	func nnwTranslationFindGroupsNeedingRetranslation() async throws -> String? {
		try await nnwTranslationEnsureScriptInjected()
		return try await nnwTranslationEvaluateReturningString("window.nnwTranslation.findGroupsNeedingRetranslation()")
	}

	/// 正文的稳定指纹(纯文字,不含 HTML)。用于缓存的"内容变没变"校验。
	func nnwTranslationBodyFingerprint() async throws -> String? {
		try await nnwTranslationEnsureScriptInjected()
		return try await nnwTranslationEvaluateReturningString("window.nnwTranslation.bodyFingerprint()")
	}

	/// 读取文章标题的 HTML。标题在正文容器外面,所以要单独取。
	func nnwTranslationReadTitle() async throws -> String? {
		try await nnwTranslationEnsureScriptInjected()
		return try await nnwTranslationEvaluateReturningString("window.nnwTranslation.readTitle()")
	}

	/// 把标题换成译文。
	func nnwTranslationApplyTitle(_ translatedHTML: String) async throws -> Bool {
		try await nnwTranslationEnsureScriptInjected()
		let literal = try nnwTranslationJavaScriptStringLiteral(translatedHTML)
		let applied = try await nnwTranslationEvaluateReturningBool("window.nnwTranslation.applyTitle(\(literal))")
		// [翻译] 标题的译文在被阅读栏 CSS 藏掉的 DOM 里,用户看到的是 UIKit 画的那份 ——
		// 把译文的**纯文字**回读出来喂给阅读栏,标题才真正"被翻译"(2026-07-24 用户报的)。
		// 集中做在这一处桥接里:所有调 applyTitle 的路径(首翻/缓存/自动恢复/事后重翻)都自动生效。
		if applied,
		   let text = try? await nnwTranslationEvaluateReturningString("window.nnwTranslation.titleText()"),
		   !text.isEmpty {
			nnwTranslationTitleDidChange(text)
		}
		return applied
	}

	/// 把正文换回原文。
	func nnwTranslationRestore() async throws -> Bool {
		try await nnwTranslationEnsureScriptInjected()
		let restored = try await nnwTranslationEvaluateReturningBool("window.nnwTranslation.restore()")
		if restored {
			nnwTranslationTitleDidChange(nil)	// [翻译] 切回原文,阅读栏标题也还原
		}
		return restored
	}

	/// 当前页面显示的是译文还是原文。
	func nnwTranslationIsShowingTranslation() async throws -> Bool {
		try await nnwTranslationEnsureScriptInjected()
		return try await nnwTranslationEvaluateReturningBool("window.nnwTranslation.state().isShowingTranslation")
	}

	/// 把页面滚到顶部。点翻译后调用,方便从头读译文(item④)。
	func nnwTranslationScrollToTop() async throws -> Bool {
		try await nnwTranslationEnsureScriptInjected()
		return try await nnwTranslationEvaluateReturningBool("window.nnwTranslation.scrollToTop()")
	}

	// [翻译] 先导块流式显示的三个桥接(2026-07-24,实现在 translation.js)

	/// 开始流式显示(藏掉先导块原文、插临时容器)。false = 页面不具备条件,退回非流式。
	func nnwTranslationStreamLeadBegin() async throws -> Bool {
		try await nnwTranslationEnsureScriptInjected()
		return try await nnwTranslationEvaluateReturningBool("window.nnwTranslation.streamLeadBegin()")
	}

	/// 更新流式显示(传累计的完整文本)。
	func nnwTranslationStreamLeadUpdate(_ accumulatedHTML: String) async throws -> Bool {
		let literal = try nnwTranslationJavaScriptStringLiteral(accumulatedHTML)
		return try await nnwTranslationEvaluateReturningBool("window.nnwTranslation.streamLeadUpdate(\(literal))")
	}

	/// 结束流式显示(拆临时容器、原文复位)。成功失败都要调,幂等。
	func nnwTranslationStreamLeadEnd() async throws -> Bool {
		try await nnwTranslationEvaluateReturningBool("window.nnwTranslation.streamLeadEnd()")
	}
}

// MARK: - [长图] 分享长图的桥接(T22,实现在 ArticleLongImageExporter.swift + nnw_snapshot.js)

extension NNWArticlePageHost {

	/// 进入截图模式:注入脚本(幂等)→ 露出标题区、强制加载图片。
	func nnwSnapshotPrepare() async throws -> Bool {
		_ = try await nnwTranslationEvaluateReturningBool(NNWSnapshotScript.source)
		return try await nnwTranslationEvaluateReturningBool("window.nnwSnapshot.prepare()")
	}

	/// 还有几张图没加载完(0 = 可以截了)。
	func nnwSnapshotPendingImageCount() async throws -> Int {
		let text = try await nnwTranslationEvaluateReturningString("String(window.nnwSnapshot.pendingImageCount())")
		return Int(text ?? "0") ?? 0
	}

	/// 退出截图模式,页面复位。幂等。
	func nnwSnapshotFinish() async throws -> Bool {
		try await nnwTranslationEvaluateReturningBool("window.nnwSnapshot.finish()")
	}
}

/// nnw_snapshot.js 的装载器(照抄 TranslationScript 的做法)。
enum NNWSnapshotScript {
	static let source: String = {
		guard let url = Bundle.main.url(forResource: "nnw_snapshot", withExtension: "js"),
			  let text = try? String(contentsOf: url, encoding: .utf8) else {
			assertionFailure("nnw_snapshot.js 没有被打进 app 包,长图功能无法工作")
			return ""
		}
		return text
	}()
}

private extension NNWArticlePageHost {

	/// 确保 translation.js 已经注入到当前页面。
	/// 脚本自身有幂等保护,重复注入是安全的,所以每次操作前都注入一遍最省事。
	func nnwTranslationEnsureScriptInjected() async throws {
		_ = try await nnwTranslationEvaluateReturningBool(TranslationScript.source)
	}

	/// 把一段 HTML 变成可以安全嵌进 JS 代码里的字符串字面量。
	/// 用 JSON 编码来做转义 —— 引号、换行、反斜杠都会被正确处理。
	func nnwTranslationJavaScriptStringLiteral(_ string: String) throws -> String {
		let data = try JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed])
		guard let literal = String(data: data, encoding: .utf8) else {
			throw TranslationError.invalidResponse
		}
		return literal
	}

	func nnwTranslationEvaluateReturningString(_ javaScript: String) async throws -> String? {
		guard let webView = nnwHostWebView else { return nil }
		return try await withCheckedThrowingContinuation { continuation in
			webView.evaluateJavaScript(javaScript) { result, error in
				if let error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume(returning: result as? String)
				}
			}
		}
	}

	func nnwTranslationEvaluateReturningBool(_ javaScript: String) async throws -> Bool {
		guard let webView = nnwHostWebView else { return false }
		return try await withCheckedThrowingContinuation { continuation in
			webView.evaluateJavaScript(javaScript) { result, error in
				if let error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume(returning: (result as? Bool) ?? false)
				}
			}
		}
	}
}


#endif
