//
//  OpenAICompatibleTranslator.swift
//  NetNewsWire — AI 翻译 fork
//
//  真正发 HTTP 请求的那一层。走 OpenAI 兼容的 /chat/completions 格式,
//  因此 OpenRouter 和绝大多数第三方服务商都能直接用 —— 只要换 baseURL 和 model。
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

import Foundation

struct OpenAICompatibleTranslator: TranslationService {

	let config: TranslationConfig
	let model: String

	/// 单次请求的超时。一块正文通常不长,60 秒足够;
	/// 设太长的话,某一块卡住会让整篇迟迟翻不完。
	private static let requestTimeout: TimeInterval = 60

	// MARK: - 提示词

	/// 给模型的总要求。
	///
	/// 每一条都是有针对性的:
	/// - "保留 HTML 标签":防止译文把网页结构搞坏(CLAUDE.md 第 5 节的地基)
	/// - "不要解释、不要代码块标记":LLM 很爱加 ```html 或者"以下是译文:"
	/// - "流畅、易读、偏口语":用户指定的风格
	private static let systemPrompt = """
	你是一位专业的中英翻译,负责把英文文章翻译成简体中文。

	翻译风格要求:
	- 流畅、易读、偏口语,像中文母语者自然写出来的句子
	- 不要逐字硬译,不要翻译腔
	- **所有专有名词一律保留英文原文,禁止翻译、禁止音译**。包括但不限于:
	  人名(写 Steve Jobs,不写"史蒂夫·乔布斯";写 Chiu,不写"邱")、
	  公司名、产品名、品牌名、网站名、刊物名、书名、技术术语与缩写(API、RSS 等)

	输出格式要求(非常重要,违反任何一条都会导致显示错乱):
	- 输入是一段 HTML 片段。你必须**原样保留所有 HTML 标签、属性和结构**,只翻译标签之间的文字
	- 链接、图片、代码块内的内容不要改动
	- 直接输出翻译后的 HTML 片段本身
	- **绝对禁止输出英文原文**。不要做中英对照,不要先给原文再给译文,不要把原文附在译文前面或后面
	- 你的整个回复里不应该出现原文的句子,只应该有中文译文
	- 禁止添加任何解释、前言、后记,比如"以下是译文"
	- 禁止用 ``` 代码块包裹输出
	"""

	private func userPrompt(htmlChunk: String, context: TranslationContext) -> String {

		var parts: [String] = []

		if let title = context.articleTitle, !title.isEmpty {
			parts.append("文章标题:\(title)")
		}

		// 术语一致性方案 C:把第一块的原文/译文作为示范传给后续各块。
		if let original = context.sampleOriginal,
		   let translation = context.sampleTranslation,
		   !original.isEmpty, !translation.isEmpty {
			parts.append("""
			这篇文章的开头是这样翻译的,请保持一致的术语、人名译法和语气:

			【原文】
			\(original)

			【译文】
			\(translation)
			""")
		}

		parts.append("""
		请翻译下面这段 HTML 片段:

		\(htmlChunk)
		""")

		return parts.joined(separator: "\n\n")
	}

	// MARK: - 发请求

	func translate(htmlChunk: String, context: TranslationContext) async throws -> String {

		guard !htmlChunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			throw TranslationError.emptyContent
		}

		guard let url = config.chatCompletionsURL else {
			throw TranslationError.notConfigured("baseURL 不是合法网址:\(config.baseURL)")
		}

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.timeoutInterval = Self.requestTimeout
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

		// OpenRouter 建议带上这两个头,用于在它的后台区分来源。非必须。
		request.setValue("https://github.com/Dime2015/NetNewsWire_AITranslation", forHTTPHeaderField: "HTTP-Referer")
		request.setValue("NetNewsWire AI Translation", forHTTPHeaderField: "X-Title")

		// T5 对策 1:让 OpenRouter 优先路由到吞吐量高的服务商。
		// 用户实测数据:同尺寸两组耗时 22s vs 81.6s —— 慢的是被路由到了慢机器。
		// 只对 OpenRouter 发这个字段;其他 OpenAI 兼容服务商可能不认识它。
		let providerPreference: ChatRequest.Provider? =
			config.baseURL.lowercased().contains("openrouter") ? ChatRequest.Provider(sort: "throughput") : nil

		let body = ChatRequest(
			model: model,
			messages: [
				ChatRequest.Message(role: "system", content: Self.systemPrompt),
				ChatRequest.Message(role: "user", content: userPrompt(htmlChunk: htmlChunk, context: context))
			],
			temperature: 0.3,
			provider: providerPreference
		)
		request.httpBody = try JSONEncoder().encode(body)

		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await URLSession.shared.data(for: request)
		} catch {
			throw TranslationError.networkFailure(underlying: error)
		}

		if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
			let message = Self.errorMessage(from: data)
			throw TranslationError.serverError(status: http.statusCode, message: message)
		}

		guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
			  let content = decoded.choices.first?.message.content,
			  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			throw TranslationError.invalidResponse
		}

		return Self.cleanUp(content, original: htmlChunk)
	}

	// MARK: - 收拾模型的输出

	/// 模型经常不听话:把译文包在 ``` 里、加一句"以下是译文:"、
	/// 或者把原文和译文一起吐出来(中英对照)。
	/// 提示词里已经明令禁止,这里再兜一层 —— 提示词是软约束,代码才是硬的。
	///
	/// - Parameter original: 送出去的原文。用来识别"模型把原文也回显了"的情况。
	static func cleanUp(_ raw: String, original: String) -> String {

		var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

		// 去掉包裹用的代码块围栏
		if text.hasPrefix("```") {
			// 去掉第一行(可能是 ``` 或 ```html)
			if let firstNewline = text.firstIndex(of: "\n") {
				text = String(text[text.index(after: firstNewline)...])
			} else {
				text = String(text.dropFirst(3))
			}
			if let range = text.range(of: "```", options: .backwards) {
				text = String(text[..<range.lowerBound])
			}
			text = text.trimmingCharacters(in: .whitespacesAndNewlines)
		}

		text = stripEchoedOriginal(from: text, original: original)

		return text
	}

	/// 模型有时会先把原文原样吐一遍,再跟上译文(中英对照)。
	/// 这里检测这种情况并把原文那一段切掉。
	///
	/// 判断很保守:只有当输出**以原文开头**、且去掉原文后还剩下足够内容时才切。
	/// 宁可漏掉一些异常情况,也不能把正常的译文误删。
	private static func stripEchoedOriginal(from text: String, original: String) -> String {

		let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)

		// 原文太短时不做判断 —— 短句子容易误伤(比如原文是个数字或人名,译文里本来就该保留)
		guard trimmedOriginal.count >= 40 else {
			return text
		}

		guard text.hasPrefix(trimmedOriginal) else {
			return text
		}

		let remainder = String(text.dropFirst(trimmedOriginal.count))
			.trimmingCharacters(in: .whitespacesAndNewlines)

		// 切完之后必须还剩下像样的内容,否则说明这压根不是"原文+译文",而是模型没翻译
		guard remainder.count >= 10 else {
			return text
		}

		return remainder
	}

	/// 从错误响应里挖出可读的说明。挖不到就把原始内容截一段返回。
	private static func errorMessage(from data: Data) -> String {
		if let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
			return decoded.error.message
		}
		let raw = String(data: data, encoding: .utf8) ?? ""
		return String(raw.prefix(200))
	}
}

// MARK: - 请求/响应的数据结构

private struct ChatRequest: Encodable {

	struct Message: Encodable {
		let role: String
		let content: String
	}

	/// OpenRouter 特有的路由偏好。nil 时整个字段不会出现在请求里
	/// (Swift 自动合成的编码对可选值用 encodeIfPresent)。
	struct Provider: Encodable {
		let sort: String
	}

	let model: String
	let messages: [Message]
	let temperature: Double
	let provider: Provider?
}

private struct ChatResponse: Decodable {

	struct Choice: Decodable {
		struct Message: Decodable {
			let content: String?
		}
		let message: Message
	}

	let choices: [Choice]
}

private struct ErrorResponse: Decodable {
	struct ErrorDetail: Decodable {
		let message: String
	}
	let error: ErrorDetail
}
