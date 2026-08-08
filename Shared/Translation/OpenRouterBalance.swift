//
//  OpenRouterBalance.swift
//  NetNewsWire — AI 翻译 fork
//
//  [翻译] 本 fork 新增,上游没有这个文件。用户 2026-08-08 第 7 件的一部分:
//  **模型菜单顶部显示 OpenRouter 账户余额**。
//
//  ## ⚠️ 这一段是「没验过就别假装知道」的典型,写法要照着这条来
//
//  查证过的只有一件事:`/api/v1/credits` 和 `/api/v1/auth/key` **两个都存在**
//  (不带 key 请求时返回 **401 而不是 404**,说明路由在,只是没授权)。
//  **成功时的返回结构没有用真 key 验过。**
//
//  所以这里的规矩是(T51 里用户点名要求的):
//  - 两个端点**都试**,谁先解析出数就用谁;
//  - 两个都解析不出来 → **一个字都不显示**,界面上就当没有这一行;
//  - **绝不猜一个数显示出来** —— 显示一个错的余额比不显示有害得多。
//
//  解析写得很宽:字段名按目前公开文档里出现过的几种都认一遍,
//  数字是字符串还是数字都收。认不出来就老老实实返回 nil。
//

import Foundation

/// 一次余额查询的结果。三个数都可能缺,缺的那项界面上就不提。
struct OpenRouterBalance: Sendable {

	/// 已用(美元)
	let usage: Double?
	/// 额度上限(美元)。为 nil = 没设上限 / 读不到
	let limit: Double?
	/// 剩余(美元)。能算出来才有值。
	var remaining: Double? {
		guard let limit, let usage else { return nil }
		return max(0, limit - usage)
	}

	/// 至少有一个数才算"读到了"。一个都没有 = 当作没读到(返回 nil,界面不显示)。
	var hasAnything: Bool { usage != nil || limit != nil }

	/// 界面上那一行字。
	var displayText: String {
		if let remaining, let limit {
			return String(format: "余额 $%.2f / 共 $%.2f", remaining, limit)
		}
		if let limit, usage == nil {
			return String(format: "额度 $%.2f", limit)
		}
		if let usage {
			return String(format: "已用 $%.2f(未读到额度上限)", usage)
		}
		return "余额读不到"
	}
}

enum OpenRouterBalanceFetcher {

	/// 查余额。**读不到就返回 nil**,调用方据此决定不显示那一行。
	///
	/// - Parameters:
	///   - baseURL: 当前配置的服务地址。非 OpenRouter 直接返回 nil(这两个端点是它专有的)。
	///   - apiKey: 用户填的 key。空的话也直接返回 nil。
	static func fetch(baseURL: String, apiKey: String) async -> OpenRouterBalance? {

		guard baseURL.lowercased().contains("openrouter"), !apiKey.isEmpty else { return nil }

		let root = normalizedRoot(baseURL)
		// 两个都试。顺序:credits 语义上更贴"余额",先问它。
		for path in ["/credits", "/auth/key"] {
			guard let url = URL(string: root + path) else { continue }
			guard let data = await get(url, apiKey: apiKey) else { continue }
			if let balance = parse(data), balance.hasAnything {
				return balance
			}
		}
		return nil
	}

	/// 把 "https://openrouter.ai/api/v1/" 这类地址收拾成不带尾斜杠的根。
	private static func normalizedRoot(_ baseURL: String) -> String {
		var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
		while base.hasSuffix("/") {
			base.removeLast()
		}
		return base
	}

	private static func get(_ url: URL, apiKey: String) async -> Data? {
		var request = URLRequest(url: url)
		request.timeoutInterval = 15
		request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
		request.setValue("NetNewsWire AI Translation", forHTTPHeaderField: "User-Agent")
		guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
		guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
		return data
	}

	/// 宽松解析:两个端点的字段名都认一遍,认不出来返回 nil。
	///
	/// 已知(文档上出现过)的字段名:
	/// - `/credits` → `total_credits` / `total_usage`
	/// - `/auth/key` → `limit` / `usage` / `limit_remaining`
	static func parse(_ data: Data) -> OpenRouterBalance? {

		guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
		// 两个端点都把内容包在 data 里;万一哪天不包了,退回顶层再找一遍。
		let payload = (root["data"] as? [String: Any]) ?? root

		let usage = number(payload["total_usage"]) ?? number(payload["usage"])
		var limit = number(payload["total_credits"]) ?? number(payload["limit"])

		// 只给了"剩余"没给"上限"时,反推一个上限出来,好凑出那句 "余额 x / 共 y"
		if limit == nil, let remaining = number(payload["limit_remaining"]), let usage {
			limit = remaining + usage
		}

		let balance = OpenRouterBalance(usage: usage, limit: limit)
		return balance.hasAnything ? balance : nil
	}

	/// 数字可能是 Double、Int,也可能是字符串。null 一律当成"没有"。
	private static func number(_ value: Any?) -> Double? {
		if let double = value as? Double { return double }
		if let int = value as? Int { return Double(int) }
		if let text = value as? String { return Double(text) }
		return nil
	}
}
