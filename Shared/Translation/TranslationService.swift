//
//  TranslationService.swift
//  NetNewsWire — AI 翻译 fork
//
//  定义"翻译服务"长什么样。
//
//  Phase 3 起,接口的单位是**一个 HTML 片段**,不是整篇文章。
//  因为文章会先由 JavaScript 切成若干块,再并行翻译(见 CLAUDE.md 第 5 节)。
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

import Foundation

// MARK: - 翻译时能参考的上下文

/// 翻一块的时候,能给模型看的额外信息。
///
/// 为什么需要它:每一块都是独立的请求,模型看不到文章的其他部分。
/// 不给上下文的话,同一个人名在第 2 块和第 9 块可能翻成两个样子。
struct TranslationContext: Sendable {

	/// 文章标题。帮助模型判断领域和语气。
	let articleTitle: String?

	/// 文章网址。
	let articleURL: String?

	/// 第一块的原文。
	let sampleOriginal: String?

	/// 第一块的译文。
	///
	/// 这两个字段合起来是"示范":告诉模型"这篇文章开头是这么翻的,你照这个风格和术语来"。
	/// 这就是 CLAUDE.md 里定的术语一致性方案 C。
	let sampleTranslation: String?

	static func initial(articleTitle: String?, articleURL: String?) -> TranslationContext {
		TranslationContext(articleTitle: articleTitle,
						   articleURL: articleURL,
						   sampleOriginal: nil,
						   sampleTranslation: nil)
	}

	/// 第一块翻完后,带上示范给后续各块用。
	func withSample(original: String, translation: String) -> TranslationContext {
		TranslationContext(articleTitle: articleTitle,
						   articleURL: articleURL,
						   sampleOriginal: original,
						   sampleTranslation: translation)
	}
}

// MARK: - 翻译服务的接口

/// 一个"能把 HTML 片段翻译成中文"的东西。
///
/// 界面代码只认识这个接口,不关心背后是假数据还是真的 LLM。
protocol TranslationService: Sendable {

	/// 翻译一个 HTML 片段。
	///
	/// - Parameters:
	///   - htmlChunk: 一小段正文 HTML。**原样传递,不解析、不修改结构。**
	///   - context: 标题、网址、以及第一块的翻译示范。
	/// - Returns: 翻译后的 HTML 片段,结构应与输入一致。
	func translate(htmlChunk: String, context: TranslationContext) async throws -> String
}

/// 额外支持**流式**翻译的服务(2026-07-24,给先导块用)。
///
/// 单独一个协议而不是塞进 TranslationService:MockTranslationService 不需要流式,
/// 调用方用 `as?` 探测能力,探不到就回落到非流式赛跑 —— 两条路都是完整可用的。
protocol StreamingTranslationService: TranslationService {

	/// 流式翻译:译文一边生成一边通过 `onDelta` 送出来。
	///
	/// - Parameter onDelta: 每收到一段增量就带着**累计的完整文本**调一次
	///   (给累计值而不是增量:调用方好做幂等显示,漏一次也不缺字)。
	///   返回 false = 调用方不要这条流了(赛跑输了),实现应立刻中止并抛 CancellationError。
	/// - Returns: 完整译文(已做过和非流式相同的清理)。
	func translateStreaming(htmlChunk: String,
							context: TranslationContext,
							onDelta: @Sendable (String) async -> Bool) async throws -> String
}

// MARK: - 可能出现的错误

enum TranslationError: Error, LocalizedError {

	/// 传进来的正文是空的。
	case emptyContent

	/// 配置文件没配好(缺 API key 等)。附带给用户看的说明。
	case notConfigured(String)

	/// 网络请求失败。
	case networkFailure(underlying: Error)

	/// 服务端返回了错误状态码。
	case serverError(status: Int, message: String)

	/// 返回内容不是预期格式。
	case invalidResponse

	/// 在页面里找不到正文容器(可能是不受支持的主题)。
	case bodyNotFound

	// 注意:这里故意**不用** NSLocalizedString。
	// 用了的话,Xcode 会在编译时自动把这些文字塞进 Shared/Localizable.xcstrings ——
	// 那是上游共用的大文件,改它会在 git pull upstream 时造成难以判断的冲突,
	// 违反 CLAUDE.md 第 2 节「保持可 merge」的最高优先级约束。
	// 本 app 只给一个中文用户自己用,不需要多语言支持。
	var errorDescription: String? {
		switch self {
		case .emptyContent:
			return "这篇文章没有正文,无法翻译。"
		case .notConfigured(let detail):
			return detail
		case .networkFailure:
			return "连接翻译服务失败,请检查网络后重试。"
		case .serverError(let status, let message):
			return "翻译服务返回错误(\(status)):\(message)"
		case .invalidResponse:
			return "翻译服务返回了无法识别的内容。"
		case .bodyNotFound:
			return "在页面里找不到文章正文,当前的文章主题可能不受支持。"
		}
	}
}

// MARK: - 不联网的假实现(Phase 1 遗留,现在只用于排查问题)

/// 假的翻译服务:不联网,只在片段前后加标记。
///
/// 保留它的意义:如果真实翻译出问题,可以临时换成它,
/// 用来判断"是网络/API 的问题,还是 app 自身链路的问题"。
struct MockTranslationService: TranslationService {

	let simulatedDelay: Duration

	init(simulatedDelay: Duration = .seconds(1)) {
		self.simulatedDelay = simulatedDelay
	}

	func translate(htmlChunk: String, context: TranslationContext) async throws -> String {

		guard !htmlChunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			throw TranslationError.emptyContent
		}

		try await Task.sleep(for: simulatedDelay)

		// 没有对 htmlChunk 做任何解析或改写,只是拼字符串。
		return "<mark>[译]</mark> " + htmlChunk
	}
}
