//
//  OpenRouterModelCatalog.swift
//  NetNewsWire — AI 翻译 fork
//
//  从 OpenRouter 拉取「翻译任务」分类下最热门的模型,用来刷新可选模型列表。
//
//  ⚠️ 重要前提(实测得出,别想当然):
//
//  1. 排行榜接口是 OpenRouter **网站前端自用的内部接口**,不是公开 API。
//     它随时可能改结构或下线 —— 实测同一天内返回结构就变过一次。
//     因此本文件的所有解析都写得很防御,任何一步不对就整体判定失败。
//
//  2. 排行榜给出的模型 ID **带日期后缀,不能直接当调用参数**:
//         排行榜:anthropic/claude-4.8-opus-20260528
//         可用的:anthropic/claude-opus-4.8
//     必须再拉一次公开的 /models 接口,用 canonical_slug 字段映射回去。
//     实测 10 个全部能映射成功。
//
//  3. translation 分类固定只返回 10 个模型,**拿不到 20 个**。
//     拿多少存多少,不去掺别的分类硬凑 —— 掺了就不是"翻译最流行"了。
//
//  失败策略:**宁可什么都不改,也不能把好的列表覆盖成坏的。**
//  调用方只有在拿到非空结果时才写入配置。
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

import Foundation

/// 榜单里的一个模型。
struct RankedModel: Sendable {
	/// 可直接用于 API 调用的模型 id,例如 anthropic/claude-opus-4.8
	let id: String
	/// 占翻译任务花费的比例,0–1。
	let share: Double
}

enum OpenRouterModelCatalog {

	enum CatalogError: LocalizedError {
		case notOpenRouter
		case network(Error)
		case badResponse(status: Int)
		case unexpectedFormat(String)
		case empty

		var errorDescription: String? {
			switch self {
			case .notOpenRouter:
				return "模型榜单只支持 OpenRouter。当前服务地址不是 OpenRouter,已保留原列表。"
			case .network(let error):
				return "网络请求失败:\(error.localizedDescription)"
			case .badResponse(let status):
				return "OpenRouter 返回了错误状态码 \(status)。"
			case .unexpectedFormat(let detail):
				return "榜单数据格式和预期不符(\(detail))。这是 OpenRouter 的内部接口,可能已经改版。"
			case .empty:
				return "榜单里没有可用的模型。"
			}
		}
	}

	private static let rankingsURL = URL(string: "https://openrouter.ai/api/frontend/v1/rankings/task-spend")!
	private static let modelsURL = URL(string: "https://openrouter.ai/api/v1/models")!

	/// 拉取翻译分类下最热门的模型,按花费占比从高到低。
	///
	/// - Parameter baseURL: 当前配置的服务地址。非 OpenRouter 时直接放弃(榜单是 OpenRouter 专有的)。
	/// - Throws: `CatalogError`。**抛错时调用方必须保留原有列表。**
	static func fetchTopTranslationModels(baseURL: String) async throws -> [RankedModel] {

		guard baseURL.lowercased().contains("openrouter") else {
			throw CatalogError.notOpenRouter
		}

		async let rankingsData = get(rankingsURL)
		async let modelsData = get(modelsURL)

		let ranked = try parseRankings(try await rankingsData)
		let canonicalToID = try parseCanonicalMap(try await modelsData)

		// 把带日期的榜单 id 映射成可调用的 id;映射不到的宁可丢掉,
		// 也不要塞一个调用时才会报错的模型名给用户。
		let resolved = ranked.compactMap { entry -> RankedModel? in
			guard let usableID = canonicalToID[entry.rawID] else { return nil }
			return RankedModel(id: usableID, share: entry.share)
		}

		guard !resolved.isEmpty else {
			throw CatalogError.empty
		}
		return resolved
	}

	// MARK: - 网络

	private static func get(_ url: URL) async throws -> Data {
		var request = URLRequest(url: url)
		request.timeoutInterval = 30
		request.setValue("NetNewsWire AI Translation", forHTTPHeaderField: "User-Agent")

		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await URLSession.shared.data(for: request)
		} catch {
			throw CatalogError.network(error)
		}
		if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
			throw CatalogError.badResponse(status: http.statusCode)
		}
		return data
	}

	// MARK: - 解析(全部写成防御式,结构一变就报错而不是给出半成品)

	private struct RawRanked {
		let rawID: String
		let share: Double
	}

	/// 排行榜结构:data.spend.tasks[] 里 tag == "translation" 的那一项。
	/// 结构变过一次,所以这里逐层检查,任何一层缺失都明确报错。
	private static func parseRankings(_ data: Data) throws -> [RawRanked] {

		guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw CatalogError.unexpectedFormat("顶层不是 JSON 对象")
		}
		guard let payload = root["data"] as? [String: Any] else {
			throw CatalogError.unexpectedFormat("缺少 data")
		}
		guard let spend = payload["spend"] as? [String: Any] else {
			throw CatalogError.unexpectedFormat("缺少 data.spend")
		}
		guard let tasks = spend["tasks"] as? [[String: Any]] else {
			throw CatalogError.unexpectedFormat("缺少 data.spend.tasks")
		}
		guard let translation = tasks.first(where: { ($0["tag"] as? String) == "translation" }) else {
			throw CatalogError.unexpectedFormat("没有 translation 分类")
		}
		guard let models = translation["models"] as? [[String: Any]] else {
			throw CatalogError.unexpectedFormat("translation 分类里缺少 models")
		}

		let parsed = models.compactMap { item -> RawRanked? in
			guard let id = item["model"] as? String, !id.isEmpty else { return nil }
			return RawRanked(rawID: id, share: (item["share"] as? Double) ?? 0)
		}
		guard !parsed.isEmpty else {
			throw CatalogError.empty
		}
		return parsed.sorted { $0.share > $1.share }
	}

	/// 从公开 /models 接口建立 canonical_slug → 可调用 id 的映射。
	private static func parseCanonicalMap(_ data: Data) throws -> [String: String] {

		guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let models = root["data"] as? [[String: Any]] else {
			throw CatalogError.unexpectedFormat("模型列表结构不符")
		}

		var map = [String: String]()
		for model in models {
			guard let id = model["id"] as? String else { continue }
			// id 本身也登记一份,万一将来榜单直接给可用 id 就不用改代码了
			map[id] = id
			if let canonical = model["canonical_slug"] as? String {
				map[canonical] = id
			}
		}
		guard !map.isEmpty else {
			throw CatalogError.unexpectedFormat("模型列表是空的")
		}
		return map
	}
}
