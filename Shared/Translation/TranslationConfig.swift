//
//  TranslationConfig.swift
//  NetNewsWire — AI 翻译 fork
//
//  翻译服务的配置:服务地址、API key、可选模型列表。
//
//  设计要点:**没有配置文件**。
//  - API key   → 在 app 的设置里填,存进 Keychain(加密),不在代码库、不在 app 包里
//  - 服务地址   → 默认 OpenRouter,可在设置里改,存在偏好设置里
//  - 模型列表   → 公开信息,写死在下面。想加想减改这个数组即可
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

import Foundation

/// 发请求时用到的一份配置快照。
struct TranslationConfig: Sendable {

	let baseURL: String
	let apiKey: String

	/// 拼出真正要请求的地址。地址不合法时返回 nil。
	///
	/// ⚠️ **必须自己检查 scheme,不能只看 `URL(string:)` 返不返回 nil**(2026-07-22 实测):
	/// `URL(string:)` 对 "abc"、"abc def"、"openrouter.ai/api/v1"(少了 https://)
	/// **统统返回非 nil** —— 它们被当成合法的「相对地址」了。
	/// 光判断 `!= nil` 等于没判断:用户把服务地址写错时不会被拦下来,
	/// 而是拿一个相对地址去发请求,最后报一个看不懂的网络错误。
	/// 所以这里额外要求它是 http / https 的绝对地址。
	var chatCompletionsURL: URL? {
		var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
		while base.hasSuffix("/") {
			base.removeLast()
		}
		guard let url = URL(string: base + "/chat/completions"),
			  let scheme = url.scheme?.lowercased(),
			  scheme == "http" || scheme == "https",
			  url.host?.isEmpty == false else {
			return nil
		}
		return url
	}
}

/// 配置的读写。
enum TranslationConfigStore {

	// MARK: - 默认值(都是公开信息,可以进代码库)

	static let defaultBaseURL = "https://openrouter.ai/api/v1"

	/// 出厂自带的模型列表(用户没刷新过时用这份)。
	///
	/// 挑选依据:OpenRouter 排行榜 → Top models by task → Translation(2026-07 实测),
	/// 在前 10 名里选了跨价位、能拉开差距的 5 个。价格为每百万 token 输入/输出。
	static let builtInModels = [
		"deepseek/deepseek-v4-flash",		// $0.10 / $0.20   最便宜,日常主力
		"deepseek/deepseek-v4-pro",			// $0.43 / $0.87   同门升级版
		"google/gemini-3-flash-preview",	// $0.50 / $3.00   换个风格对比
		"anthropic/claude-sonnet-4.6",		// $3.00 / $15.00  中档,长难句更稳
		"anthropic/claude-opus-4.8"			// $5.00 / $25.00  榜首,难文章兜底
	]

	static let defaultModel = "deepseek/deepseek-v4-flash"

	// MARK: - 偏好设置里的键

	private static let selectedModelKey = "nnwTranslationSelectedModel"
	private static let baseURLKey = "nnwTranslationBaseURL"
	private static let fetchedModelsKey = "nnwTranslationFetchedModels"
	private static let fetchedModelsDateKey = "nnwTranslationFetchedModelsDate"

	// MARK: - API Key(存在 Keychain 里)

	static var apiKey: String? {
		get { TranslationKeychain.readAPIKey() }
		set { TranslationKeychain.saveAPIKey(newValue ?? "") }
	}

	static var hasAPIKey: Bool {
		!(apiKey ?? "").isEmpty
	}

	/// 配置是不是**真的能拿去用**:API Key 有值,且服务地址能拼出一个合法的请求地址。
	///
	/// 为什么不直接用 `hasAPIKey`:设置页那行「已设置 / 未设置」是给用户看
	/// 「翻译到底能不能用」的,只看 key 有值不够 —— 服务地址被改成乱码时,
	/// key 填得再对也发不出请求,那时候还显示「已设置」是在骗人。
	///
	/// ⚠️ 服务地址**留空是合法的**(留空 = 用默认的 OpenRouter,页面底部说明里写着),
	/// 所以「只填了 key、地址留空」这个最常见的正确配置,这里照样返回 true。
	static var isFullyConfigured: Bool {
		configurationProblem == nil
	}

	// MARK: - 服务地址

	static var baseURL: String {
		get { UserDefaults.standard.string(forKey: baseURLKey) ?? defaultBaseURL }
		set {
			let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
			if trimmed.isEmpty || trimmed == defaultBaseURL {
				UserDefaults.standard.removeObject(forKey: baseURLKey)
			} else {
				UserDefaults.standard.set(trimmed, forKey: baseURLKey)
			}
		}
	}

	// MARK: - 可选模型列表(出厂自带 / 从 OpenRouter 刷新而来)

	/// 当前可选的模型。刷新成功过就用刷来的,否则用出厂自带的。
	static var availableModels: [String] {
		let fetched = UserDefaults.standard.stringArray(forKey: fetchedModelsKey) ?? []
		return fetched.isEmpty ? builtInModels : fetched
	}

	/// 上次成功刷新的时间。从没刷新过就是 nil。
	static var modelsLastRefreshed: Date? {
		UserDefaults.standard.object(forKey: fetchedModelsDateKey) as? Date
	}

	/// 写入刷新结果。
	///
	/// ⚠️ **空列表一律拒绝写入** —— 这是"拉取失败不能覆盖上一次结果"的最后一道防线。
	/// 调用方本来就应该在失败时不调用本方法,这里再兜一层,防止将来有人改坏。
	static func updateFetchedModels(_ models: [String]) {
		let cleaned = models.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
		guard !cleaned.isEmpty else { return }
		UserDefaults.standard.set(cleaned, forKey: fetchedModelsKey)
		UserDefaults.standard.set(Date(), forKey: fetchedModelsDateKey)
	}

	/// 丢弃刷新结果,回到出厂自带的列表。
	static func resetFetchedModels() {
		UserDefaults.standard.removeObject(forKey: fetchedModelsKey)
		UserDefaults.standard.removeObject(forKey: fetchedModelsDateKey)
	}

	// MARK: - 当前选中的模型

	static var selectedModel: String {
		get {
			if let saved = UserDefaults.standard.string(forKey: selectedModelKey),
			   availableModels.contains(saved) {
				return saved
			}
			// 选中的模型可能在刷新后从列表里消失了,这时退回列表第一个
			return availableModels.first ?? defaultModel
		}
		set { UserDefaults.standard.set(newValue, forKey: selectedModelKey) }
	}

	// MARK: - 给外部用的

	/// 组装出一份可以拿去发请求的配置。没配好就返回 nil。
	static var config: TranslationConfig? {
		guard let key = apiKey, !key.isEmpty else { return nil }
		return TranslationConfig(baseURL: baseURL, apiKey: key)
	}

	/// 配置没配好时,给用户看的人话说明。配好了返回 nil。
	static var configurationProblem: String? {
		guard hasAPIKey else {
			return "还没有填写 API Key。请到「设置 → Articles → 翻译 API Key」里填入。"
		}
		guard let config, config.chatCompletionsURL != nil else {
			return "服务地址不是一个合法网址:\(baseURL)"
		}
		return nil
	}

	/// 模型 id 太长,界面上显示短名字。
	/// 例如 "deepseek/deepseek-v4-flash" → "deepseek-v4-flash"
	static func displayName(for modelID: String) -> String {
		guard let slash = modelID.lastIndex(of: "/") else {
			return modelID
		}
		return String(modelID[modelID.index(after: slash)...])
	}
}
