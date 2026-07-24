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

struct OpenAICompatibleTranslator: StreamingTranslationService {

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
	/// v2(2026-07-24):用户反馈"读起来累、句子结构不顺"。v1 只说了"要流畅、别翻译腔",
	/// 没说**怎么做** —— 对速度档模型,要给具体的操作指令和一个示范才管用。
	/// ⚠️ 改这段记得把 TranslationCache.promptGeneration +1,否则旧译文一直从缓存里跳出来。
	private static let systemPrompt = """
	你是一位资深的中文译者,把英文文章翻译成简体中文。你的目标读者是把中文当母语的人,\
	译文要让他们读起来毫不费劲,就像原本就是用中文写的。

	翻译方法(核心:重写,不是转换):
	- 先读懂整段的意思,然后**用中文把这个意思重新讲一遍** —— 忘掉英文的句子结构
	- 英文的长句要拆:定语从句、插入语拆成独立短句,按中文习惯**先因后果、先条件后结论**地排
	- 每句话的主语要清楚。英文靠代词(it/this/which)串起来的地方,中文里把指代对象直接写出来
	- 少用"被"字:英文被动句多数应转成中文主动句("was acquired by X" → "X 收购了它")
	- 这些翻译腔的标志词能不用就不用:"进行""作出""对于""关于""其""之一""所""性""化"
	- 语气跟着原文走:原文轻松就轻松,原文严肃就严肃,不要一律翻成书面腔

	示范(注意句子是怎么拆散重排的):
	原文:The company, which had been struggling with declining ad revenue for years, \
	announced that it would be laying off 12% of its workforce.
	差的译文:这家多年来一直在与不断下降的广告收入作斗争的公司宣布,它将裁员其12%的员工。
	好的译文:这家公司的广告收入连年下滑,如今宣布裁员 12%。

	专有名词(硬规则):
	- **所有专有名词一律保留英文原文,禁止翻译、禁止音译**。包括:
	  人名(写 Steve Jobs,不写"史蒂夫·乔布斯")、公司名、产品名、品牌名、
	  网站名、刊物名、书名、技术术语与缩写(API、RSS 等)

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
			// 0.3 → 0.45(2026-07-24):温度太低译文发僵,是"读着累"的帮凶之一。
			// 0.45 仍然偏保守 —— 翻译要的是稳定,不是创意。
			temperature: 0.45,
			provider: providerPreference,
			stream: nil
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

	// MARK: - 流式翻译(先导块专用,2026-07-24)

	/// 和 `translate` 同一套请求,只是 `stream: true`,译文一边生成一边通过 `onDelta` 送出。
	/// SSE 的逐行解析在 `SSEStreamParser`(纯逻辑,已离线验证 15 种帧)。
	func translateStreaming(htmlChunk: String,
							context: TranslationContext,
							onDelta: @Sendable (String) async -> Bool) async throws -> String {

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
		request.setValue("https://github.com/Dime2015/NetNewsWire_AITranslation", forHTTPHeaderField: "HTTP-Referer")
		request.setValue("NetNewsWire AI Translation", forHTTPHeaderField: "X-Title")

		let providerPreference: ChatRequest.Provider? =
			config.baseURL.lowercased().contains("openrouter") ? ChatRequest.Provider(sort: "throughput") : nil

		let body = ChatRequest(
			model: model,
			messages: [
				ChatRequest.Message(role: "system", content: Self.systemPrompt),
				ChatRequest.Message(role: "user", content: userPrompt(htmlChunk: htmlChunk, context: context))
			],
			temperature: 0.45,
			provider: providerPreference,
			stream: true
		)
		request.httpBody = try JSONEncoder().encode(body)

		let bytes: URLSession.AsyncBytes
		let response: URLResponse
		do {
			(bytes, response) = try await URLSession.shared.bytes(for: request)
		} catch {
			throw TranslationError.networkFailure(underlying: error)
		}

		// 错误状态时响应体不是 SSE 而是一段 JSON,读一点出来给用户看原因
		if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
			var errorBody = ""
			for try await line in bytes.lines {
				errorBody += line
				if errorBody.count > 500 { break }
			}
			throw TranslationError.serverError(status: http.statusCode,
											   message: Self.errorMessage(from: Data(errorBody.utf8)))
		}

		var accumulated = ""
		lineLoop: for try await line in bytes.lines {
			switch SSEStreamParser.parse(line: line) {
			case .delta(let text):
				accumulated += text
				// onDelta 返回 false = 调用方不要这条流了(赛跑输了)→ 立刻停,别再花钱
				guard await onDelta(accumulated) else {
					throw CancellationError()
				}
			case .done:
				break lineLoop
			case .ignore:
				continue
			}
		}

		let cleaned = Self.cleanUp(accumulated, original: htmlChunk)
		guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			throw TranslationError.invalidResponse
		}
		return cleaned
	}

	// MARK: - 连通性自检

	/// 用一次极小的真实请求验证配置是否可用。
	///
	/// 为什么不只是 ping 一下地址:能连上不等于能用 ——
	/// key 过期、余额不足、模型名写错,都要真的发一次请求才会暴露。
	/// 这里让模型只回一个字,成本可以忽略不计。
	///
	/// - Returns: 成功时返回模型实际回复的内容(用于展示"确实通了")。
	static func testConnection(config: TranslationConfig, model: String) async throws -> String {

		guard let url = config.chatCompletionsURL else {
			throw TranslationError.notConfigured("服务地址不是合法网址:\(config.baseURL)")
		}

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.timeoutInterval = 30
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

		let body = ChatRequest(
			model: model,
			messages: [ChatRequest.Message(role: "user", content: "只回复两个字:你好")],
			temperature: 0,
			provider: nil,
			stream: nil
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
			throw TranslationError.serverError(status: http.statusCode, message: errorMessage(from: data))
		}

		guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
			  let content = decoded.choices.first?.message.content else {
			throw TranslationError.invalidResponse
		}

		return content.trimmingCharacters(in: .whitespacesAndNewlines)
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
	static func errorMessage(from data: Data) -> String {
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
	/// 流式开关。nil 时整个字段不出现在请求里(同 provider,靠 encodeIfPresent),
	/// 非流式请求的 JSON 和以前一个字节都不差。
	let stream: Bool?
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
