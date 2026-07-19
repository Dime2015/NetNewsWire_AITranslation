//
//  TranslationService.swift
//  NetNewsWire — AI 翻译 fork
//
//  Phase 1:只定义"翻译服务"长什么样,并给一个不联网的假实现。
//  真正调用后端在 Phase 3。
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

import Foundation

// MARK: - 翻译服务的接口

/// 一个"能把文章正文翻译成中文"的东西。
///
/// 为什么要先定义接口、再写实现:
/// 这样界面代码(按钮)只认识这个接口,不关心背后是假数据还是真后端。
/// Phase 2 接界面时用假实现,Phase 3 换成真后端,**界面代码一行都不用改**。
protocol TranslationService: Sendable {

	/// 把一段文章正文的 HTML 翻译成中文。
	///
	/// - Parameters:
	///   - html: 文章正文的 HTML 原文。**原样传递,不解析、不修改结构。**
	///   - articleURL: 文章的网址。后端可能用它做上下文判断,可以为空。
	/// - Returns: 翻译后的 HTML。结构应与输入保持一致,只有文字变成中文。
	/// - Throws: 失败时抛 `TranslationError`。
	func translate(html: String, articleURL: String?) async throws -> String
}

// MARK: - 可能出现的错误

/// 翻译失败的原因。Phase 1 用不到,是给 Phase 3 真实网络请求预留的。
enum TranslationError: Error, LocalizedError {

	/// 传进来的正文是空的,没东西可翻。
	case emptyContent

	/// 网络请求失败(连不上、超时等)。
	case networkFailure(underlying: Error)

	/// 后端返回了,但内容不是预期格式。
	case invalidResponse

	var errorDescription: String? {
		switch self {
		case .emptyContent:
			return NSLocalizedString("这篇文章没有正文,无法翻译。", comment: "翻译失败:正文为空")
		case .networkFailure:
			return NSLocalizedString("连接翻译服务失败,请检查网络后重试。", comment: "翻译失败:网络问题")
		case .invalidResponse:
			return NSLocalizedString("翻译服务返回了无法识别的内容。", comment: "翻译失败:响应格式错误")
		}
	}
}

// MARK: - Phase 1 的假实现(不联网)

/// 假的翻译服务:不联网,只在正文前后各加一个醒目的标记。
///
/// **它存在的唯一目的,是让人肉眼确认"整条链路通了"。**
/// 如果点了翻译按钮后,文章顶部和底部都出现了标记,就说明:
/// 按钮 → 服务 → 拿到结果 → 替换正文显示,这四步全都通了。
///
/// ⚠️ 关于与 CLAUDE.md 原 spec 的偏离(重要,请勿当成疏忽):
///
/// CLAUDE.md Phase 1 原文写的是「把每个文本节点替换成 `[译文占位]`」。
/// 但第 5 节同时规定「绝不把整段 HTML 直接当字符串处理,Swift 侧只负责传递,
/// 不解析、不修改 HTML 结构」。
///
/// 这两条无法同时满足 —— "替换每个文本节点"必须先解析 HTML 才能找到文本节点,
/// 那就等于在 Swift 里写一个 HTML 解析器,正是第 5 节要禁止的事。
///
/// 因此这里选择服从第 5 节(更根本的技术约定),改用"前后加标记"的方式:
///   - 不需要解析 HTML,只做字符串拼接,零结构风险
///   - 前后**各**加一个标记,如果两个都显示出来,说明正文被完整替换了(没被截断)
///   - 验证效果完全等价:肉眼一看就知道链路通没通
///
/// 若将来确实需要"逐文本节点替换"的效果,正确做法是在 JavaScript 侧做
/// (浏览器里有现成的 DOM 解析器),而不是在 Swift 里手写解析。
struct MockTranslationService: TranslationService {

	/// 加在正文最前面的标记。
	static let headerMarker = "<p style=\"padding:8px;background:#ffe9a8;border-radius:6px;font-weight:bold;\">[译文占位 · 开头]</p>"

	/// 加在正文最后面的标记。
	static let footerMarker = "<p style=\"padding:8px;background:#ffe9a8;border-radius:6px;font-weight:bold;\">[译文占位 · 结尾]</p>"

	/// 假装网络请求要花多久。
	///
	/// 故意留一点延迟,是为了让 Phase 2 能顺便验证"加载中"状态 ——
	/// 如果瞬间就返回,就看不出转圈动画有没有正常工作。
	let simulatedDelay: Duration

	init(simulatedDelay: Duration = .seconds(1)) {
		self.simulatedDelay = simulatedDelay
	}

	func translate(html: String, articleURL: String?) async throws -> String {

		guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			throw TranslationError.emptyContent
		}

		// 假装在联网。真实现里这里会换成一次 HTTP 请求。
		try await Task.sleep(for: simulatedDelay)

		// 原文原样夹在中间,前后各加一个标记。
		// 注意:这里没有对 html 做任何解析或改写,只是拼字符串。
		return Self.headerMarker + html + Self.footerMarker
	}
}
