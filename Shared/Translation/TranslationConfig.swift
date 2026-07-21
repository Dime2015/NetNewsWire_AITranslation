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

	/// 拼出真正要请求的地址。
	var chatCompletionsURL: URL? {
		var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
		while base.hasSuffix("/") {
			base.removeLast()
		}
		return URL(string: base + "/chat/completions")
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
