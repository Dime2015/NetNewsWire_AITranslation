//
//  OpenRouterCatalog.swift
//  NetNewsWire — AI 翻译 fork
//
//  [翻译] 本 fork 新增,上游没有这个文件。用户 2026-08-08 第 7 件的地基:
//  **OpenRouter 上全部可用模型的目录**(实测约 400 个 / 58 个厂商),带价格。
//
//  ## 和隔壁 `OpenRouterModelCatalog.swift` 的区别(别搞混)
//
//  | 文件 | 拉的是什么 | 靠不靠谱 |
//  |---|---|---|
//  | `OpenRouterModelCatalog`(旧) | 网站前端自用的**翻译榜**接口 | 内部接口,随时会变 |
//  | 本文件 | **公开的 `/api/v1/models`** | 公开 API,结构稳定 |
//
//  新的模型菜单只用本文件。旧的那个暂时留着不删(它自己有一套防御式解析,
//  将来若想再做"翻译榜"入口可以捡回来),但**已经没有人调它了**。
//
//  ## 价格怎么变成「≈¥X/篇」
//
//  OpenRouter 给的是 `pricing.prompt` / `pricing.completion`,单位是**美元 / token**
//  (字符串,例如 "0.0000001")。用户要看的是"翻一篇文章大概几毛钱",所以按
//  **真实翻译量**折算:一篇文章大约 4000 token 进、4000 token 出(本 fork 的分组
//  翻译会把正文切开多次往返,进出量大致相当)。汇率写死在下面。
//
//  ⚠️ **这是估算,不是账单。** 界面上必须写着"估算"两个字 —— 实际花费受文章长短、
//  重试、思考模式(本 fork 已关,见 T51 #8)影响。写死的汇率也会过期。
//
//  ## 缓存
//
//  拉回来的目录写进系统 Caches 目录,下次开页面**秒开**,后台再悄悄刷一遍。
//  被系统清掉就重拉,无害。
//

import Foundation

/// 目录里的一个模型。
struct OpenRouterCatalogModel: Codable, Sendable, Hashable {

	/// 可直接用于 API 调用的 id,例如 `anthropic/claude-opus-4.8`
	let id: String
	/// OpenRouter 给的展示名,例如 "Anthropic: Claude Opus 4.8"
	let name: String
	/// 美元 / token(输入)
	let promptPrice: Double
	/// 美元 / token(输出)
	let completionPrice: Double
	/// 上下文长度(token)。拿不到就是 0。
	let contextLength: Int
	/// 模型发布时间(Unix 秒)。拿不到就是 0 —— 精选那道「近 12 个月」会把 0 当作"不知道"排掉。
	let created: Double
	/// 能吃什么(text / image / audio / file / video)
	let inputModalities: [String]
	/// 能吐什么。**只留能吐文本的** —— 这一条比按名字猜可靠得多,
	/// 图片生成、音频合成那些一刀就没了。
	let outputModalities: [String]
	/// 流行度:OpenRouter 近 30 天里,这个模型在**各任务分类**的花费占比之和。
	/// 拿不到就是 0 —— ⚠️ **0 的意思是"榜上无名",不是"没人用"**,详见 `OpenRouterRankings`。
	let popularity: Double

	/// 榜上有名(有真实流行度数据)。界面上会标一个「热门」。
	var isPopular: Bool { popularity > 0 }

	/// 厂商 = id 里斜杠前面那一段(`anthropic/claude-opus-4.8` → `anthropic`)。
	///
	/// ⚠️ **带 `~` 的别名归到同一家**(`~openai/gpt-latest` → `openai`)。
	/// 2026-08-08 用户报:「OpenAI 分类底下为什么只有 gpt-latest?」——
	/// 因为那时别名单独成组、还因为 `~` 排到了最前面,6 个别名组挤在厂商列表开头,
	/// 长得和真分组一模一样。用户看到「OpenAI · 始终最新」里只有 2 个,
	/// 就以为 OpenAI 只有这些 —— **真正的 95 个在列表更下面。**
	/// 一个品牌只该有一节,别名是那一节里的一行。
	var vendor: String {
		guard let slash = id.firstIndex(of: "/") else { return "其它" }
		return String(id[..<slash]).replacingOccurrences(of: "~", with: "")
	}

	/// 是不是「始终最新」的别名(`~openai/gpt-latest` 这种)。
	/// ⚠️ OpenRouter **不告诉我们它当前指向哪个具体模型**
	/// (`canonical_slug` 就是别名自己,只有 description 说"always redirects to the latest…"),
	/// 所以界面上只能标出"这是个会自动跟最新的别名",给不出"= 具体哪个"。
	var isLatestAlias: Bool { id.hasPrefix("~") }

	/// 去掉厂商前缀的短名。
	var shortID: String {
		guard let slash = id.lastIndex(of: "/") else { return id }
		return String(id[id.index(after: slash)...])
	}

	/// 是不是 OpenRouter 的免费变体(id 以 `:free` 结尾)。实测 400 个里有 14 个。
	var isFreeVariant: Bool { id.hasSuffix(":free") }

	/// 短名切成的"词"。判"名字里带不带某个词"要按**词**比,不能按子串比 ——
	/// ⚠️ 子串比会把 `google/gemini-…` 当成带 `mini` 给排掉(这是实实在在的坑)。
	var nameTokens: Set<String> {
		Set(shortID.lowercased().split(whereSeparator: { "-._ ".contains($0) }).map(String.init))
	}

	/// 名字里带着"小参数量"标记吗(`…-20b`、`…-70b`)。
	/// ⚠️ 带阈值:`550b` / `671b` 那种是旗舰,不算小(见 `smallParameterThresholdB`)。
	var hasSmallParameterTag: Bool {
		nameTokens.contains { token in
			guard token.hasSuffix("b"), let value = Int(token.dropLast()) else { return false }
			return value < OpenRouterCatalog.smallParameterThresholdB
		}
	}

	/// 值不值得摆进"浏览列表"(精选 + 厂商分组的共同底线)。
	///
	/// 排掉的都是**摆出来只会添乱**的:变体重影、小参数线、图片/音频/代码等专用线、
	/// 上下文塞不下一篇文章的、一年前的老版本。
	/// ⚠️ **别名(`~…-latest`)留着** —— 它是"永远跟最新"的入口,有用。
	var isBrowseWorthy: Bool {
		guard !id.contains(":") else { return false }				// :free / :batch 变体
		guard !hasSmallParameterTag else { return false }
		guard nameTokens.isDisjoint(with: OpenRouterCatalog.featuredSmallModelTokens) else { return false }
		guard nameTokens.isDisjoint(with: OpenRouterCatalog.featuredSpecialistTokens) else { return false }
		guard inputModalities.contains("text"), outputModalities.contains("text") else { return false }
		guard contextLength >= OpenRouterCatalog.featuredMinContext else { return false }
		guard created > 0,
			  Date().timeIntervalSince1970 - created <= OpenRouterCatalog.featuredMaxAge else { return false }
		// 未标价 / 动态定价的不进浏览列表 —— 这一页是拿来比价的,"未标价"那一行帮不上任何忙
		guard estimatedUSDPerArticle > 0 else { return false }
		return true
	}

	/// 模型所属的**系列**(`claude-opus-5` / `claude-opus-5-fast` → `claude opus`)。
	///
	/// 做法:把短名切成词,扔掉"版本号那类"的词(数字、`pro` / `fast` / `latest` / `preview`、
	/// 日期戳、参数量标记),剩下的连起来。
	///
	/// ⚠️ 干什么用的:厂商分组里每个系列只留一个。不去重的话 Anthropic 那一节会是
	/// **三行 opus 变体**(实测),而用户要的是"最便宜的、最强的、最平衡的都在" ——
	/// 那三档在这些厂商这里**恰恰就是系列**(haiku / sonnet / opus)。
	var family: String {
		let versionish: Set<String> = ["pro", "fast", "latest", "preview", "exp",
									   "it", "instruct", "thinking", "chat"]
		let parts = shortID.lowercased()
			.split(whereSeparator: { "-._ ".contains($0) })
			.map(String.init)
			.filter { token in
				if versionish.contains(token) { return false }
				// 纯数字 / v3.1 / 0731 这类日期戳 / 235b、a22b 这类参数量标记
				if token.allSatisfy({ $0.isNumber || $0 == "." }) { return false }
				if token.hasPrefix("v"), token.dropFirst().allSatisfy({ $0.isNumber || $0 == "." }) { return false }
				if token.hasSuffix("b"), token.dropLast().allSatisfy({ $0.isNumber || $0 == "a" }) { return false }
				return true
			}
		return parts.isEmpty ? shortID : parts.joined(separator: " ")
	}

	/// 价格是**负数**的那几个(实测:`openrouter/auto`、`openrouter/fusion` 等 5 个路由型模型,
	/// 给的是 `-1`)。它们不是"免费",是"实际价格取决于路由到哪个模型",没法估。
	var hasDynamicPricing: Bool { promptPrice < 0 || completionPrice < 0 }

	/// 价格是 0 的(实测:`google/lyria-3-*` 音频模型、`openrouter/free`)。
	var isUnpriced: Bool { !hasDynamicPricing && promptPrice == 0 && completionPrice == 0 }

	/// 翻一篇文章的估算成本(美元)。
	var estimatedUSDPerArticle: Double {
		promptPrice * Double(OpenRouterCatalog.estimatedPromptTokens)
			+ completionPrice * Double(OpenRouterCatalog.estimatedCompletionTokens)
	}

	/// 界面上那句「≈¥0.02/篇(估算)」。
	var priceDescription: String {
		if hasDynamicPricing {
			return "价格随实际路由到的模型浮动"
		}
		if isUnpriced {
			return "未标价"
		}
		let cny = estimatedUSDPerArticle * OpenRouterCatalog.usdToCNY
		if cny <= 0 {
			return "未标价"
		}
		if cny < 0.01 {
			return String(format: "≈¥%.3f/篇(估算)", cny)
		}
		return String(format: "≈¥%.2f/篇(估算)", cny)
	}

	/// 界面上那句「上下文 128K」。拿不到长度就返回 nil。
	var contextDescription: String? {
		guard contextLength > 0 else { return nil }
		if contextLength >= 1000 {
			return "上下文 \(contextLength / 1000)K"
		}
		return "上下文 \(contextLength)"
	}
}

enum OpenRouterCatalog {

	// MARK: - 估算用的常数(改这里,界面自动跟)

	/// 一篇文章大约要送进去多少 token
	static let estimatedPromptTokens = 4000
	/// 一篇文章大约会吐出来多少 token
	static let estimatedCompletionTokens = 4000
	/// 美元兑人民币。⚠️ **写死的,会过期** —— 所以界面上标着"估算"。
	static let usdToCNY = 7.2

	// MARK: - 精选的筛选标准(用户 2026-08-08 定的,改这里就能调)

	/// 上下文至少这么长 —— 翻译要把整段正文塞进去,短上下文的直接出局
	static let featuredMinContext = 128_000
	/// 只留最近这么久发布的。**这一条是最狠的一刀**(实测 400 个里砍掉 74 个),
	/// 也是最有效的去噪:老模型留在目录里能搜到,但不该占着"精选"的位置。
	static let featuredMaxAge: TimeInterval = 365 * 24 * 60 * 60
	/// 每篇估算成本的上限(美元)。再贵就不该出现在"日常主力"的位置上了。
	static let featuredMaxUSD = 0.30
	/// 精选最后留几个(用户 2026-08-08:「选前 15 个」)
	static let featuredCount = 15
	/// 每个厂商分组里最多显示几个(用户 2026-08-08:「多了我觉得也没意义了」)
	static let perVendorLimit = 5

	// ⚠️ **原来这里还有一条 `featuredMinUSD = 0.005`(每篇成本下限),2026-08-08 删掉了。**
	//
	// 它当初的理由是"比这还便宜的基本是小模型,质量不稳"。用户一眼看出这条是错的,
	// 而且举了两个反例 —— 拉真数据一验,两个都成立:
	//
	// | 被误杀的 | 每篇 | 什么货色 |
	// |---|---|---|
	// | `openai/gpt-5.6-luna` | $0.0028 | 旗舰族,1050K 上下文 |
	// | `deepseek/deepseek-v4-flash-0731` | $0.0011 | 用户**当时正在用**的那个 |
	//
	// 判据:**价格不是能力的代理指标。** "排掉小模型"这件事已经有两道更直接的闸门在管 ——
	// 名字规则(`3b/8b/nano/mini/gemma/ministral`)和上下文 ≥128K。
	// 再拿价格兜一遍是重复的,而且会误伤"又强又便宜"这一类 —— 恰恰是最该推荐的那一类。

	/// **知名厂商保底名单**(有序,越靠前越优先占席位)。
	///
	/// ⚠️ 为什么必须手工列(2026-08-08 用户拍板):精选原来纯按价格补齐,结果
	/// **OpenAI / Anthropic / Meta 一个都进不去** —— 中国厂商的模型便宜整整一个数量级
	/// (各家最便宜档:deepseek/minimax/小米/qwen $0.005,而 anthropic $0.024、openai $0.028),
	/// 按价格排 OpenAI 是 27 家里的第 24 名。用户的原话是"又便宜、能力也强、**而且还出名**",
	/// 而"出名"和"能力"这两样 **OpenRouter 一个数据都不给**:
	/// 没有质量指标,流行度榜只覆盖到 4 个候选(见 `OpenRouterRankings`)。
	/// 手工列一份名单是唯一能表达它的办法 —— 诚实地承认这是人工判断,而不是假装算出来的。
	///
	/// ⚠️ **新厂商冒出来要手动加**。这是这份名单的维护成本,写在这儿别忘了。
	static let featuredMajorVendors = [
		"openai", "anthropic", "google", "deepseek", "x-ai", "qwen",
		"moonshotai", "meta", "mistralai", "minimax", "z-ai", "nvidia",
		"microsoft", "amazon", "cohere", "perplexity"
	]

	/// 名字里带这些**词**的一律排掉:小参数线。
	/// ⚠️ 比的是**词**不是子串 —— 子串比会误伤 `gemini`(里面有 `mini`)。
	/// ⚠️ **不要往里加 `lite` / `small`**:2026-08-08 试过,会误伤
	/// `gemini-3.1-flash-lite`、`mistral-small-2603` 这些"又便宜又好用"的档 —— 恰恰是该推荐的。
	static let featuredSmallModelTokens: Set<String> = ["nano", "mini", "micro", "gemma", "ministral"]

	/// 名字里带这些**词**的一律排掉:专用线(不是拿来做通用翻译的)。
	///
	/// ⚠️ `safeguard` / `guard` / `moderation` 是 2026-08-08 补的:
	/// 不补的话 OpenAI 那一档会选中 `gpt-oss-safeguard-20b`(一个内容审核模型),
	/// 而用户等着看的是 `gpt-5.6-luna`。
	static let featuredSpecialistTokens: Set<String> = [
		"image", "vision", "audio", "coder", "safeguard", "guard", "moderation", "embed", "rerank"
	]

	/// 参数量小于这个数(单位 B)的算"小参数线"。
	///
	/// ⚠️ 为什么要有个门槛而不是"带 `\d+b` 就排掉":`nemotron-3-ultra-550b`、
	/// `cogito-v2.1-671b` 这些恰恰是旗舰。100B 是分界线 —— 20b / 70b 出局,120b / 550b 留下。
	static let smallParameterThresholdB = 100

	enum CatalogError: LocalizedError {
		case notOpenRouter
		case network(Error)
		case badResponse(status: Int)
		case unexpectedFormat(String)

		var errorDescription: String? {
			switch self {
			case .notOpenRouter:
				return "模型目录只支持 OpenRouter。当前服务地址不是 OpenRouter,已保留原列表。"
			case .network(let error):
				return "网络请求失败:\(error.localizedDescription)"
			case .badResponse(let status):
				return "OpenRouter 返回了错误状态码 \(status)。"
			case .unexpectedFormat(let detail):
				return "模型目录的数据格式和预期不符(\(detail))。"
			}
		}
	}

	// MARK: - 拉取

	private static let modelsURL = URL(string: "https://openrouter.ai/api/v1/models")!

	static func fetchAll(baseURL: String) async throws -> [OpenRouterCatalogModel] {

		guard baseURL.lowercased().contains("openrouter") else {
			throw CatalogError.notOpenRouter
		}

		var request = URLRequest(url: modelsURL)
		request.timeoutInterval = 30
		request.setValue("NetNewsWire AI Translation", forHTTPHeaderField: "User-Agent")
		// ⚠️ 2026-08-12(用户报"DeepSeek 调价了,刷新模型列表看不出来"):
		// 价格是**跟着这个接口一起回来的**(pricing.prompt / pricing.completion),
		// 所以解析逻辑没问题 —— 问题在**这一层根本没真的去拿**。
		// URLSession 默认走 `.useProtocolCachePolicy`,OpenRouter 给这个接口带了缓存头,
		// 于是"刷新模型目录"很可能只是把 URLCache 里的旧 JSON 又读了一遍,
		// 模型数量、名字都对得上,唯独价格是上次的 —— 一个不会报错的假刷新。
		// 用户按下刷新就是明确要最新的,这里绕开本地与代理缓存。
		request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

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

		let models = try parse(data)
		guard !models.isEmpty else {
			throw CatalogError.unexpectedFormat("一个模型都没解析出来")
		}

		// 流行度是**顺带拿的,拿不到不算失败** —— 它走的是 OpenRouter 网站自用的内部接口,
		// 随时可能改结构或下线。失败时所有模型的 popularity 都是 0,精选自动退回"按价格挑"。
		let scores = await OpenRouterRankings.fetchScores(canonicalMap: canonicalMap(from: data))
		let merged = models.map { model in
			OpenRouterCatalogModel(id: model.id, name: model.name,
								   promptPrice: model.promptPrice, completionPrice: model.completionPrice,
								   contextLength: model.contextLength, created: model.created,
								   inputModalities: model.inputModalities, outputModalities: model.outputModalities,
								   popularity: scores[model.id] ?? 0)
		}

		save(merged)
		return merged
	}

	/// 榜单给的 id 带日期后缀(`anthropic/claude-4.8-opus-20260528`),不能直接当调用参数用;
	/// `/models` 里的 `canonical_slug` 就是那个带日期的写法,拿它建一张映射表。
	/// (同样的坑在 `OpenRouterModelCatalog.swift` 里记过,这里是同一件事。)
	private static func canonicalMap(from data: Data) -> [String: String] {
		guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let list = root["data"] as? [[String: Any]] else { return [:] }
		var map = [String: String]()
		for item in list {
			guard let id = item["id"] as? String else { continue }
			map[id] = id
			if let canonical = item["canonical_slug"] as? String { map[canonical] = id }
		}
		return map
	}

	/// 逐层检查、逐个模型 compactMap:**单个模型解析失败只丢它自己**,
	/// 不让一条脏数据把整份目录毁掉(400 个里坏一个是很正常的事)。
	static func parse(_ data: Data) throws -> [OpenRouterCatalogModel] {

		guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw CatalogError.unexpectedFormat("顶层不是 JSON 对象")
		}
		guard let list = root["data"] as? [[String: Any]] else {
			throw CatalogError.unexpectedFormat("缺少 data")
		}

		return list.compactMap { item -> OpenRouterCatalogModel? in
			guard let id = item["id"] as? String, !id.isEmpty else { return nil }
			let pricing = item["pricing"] as? [String: Any] ?? [:]
			let architecture = item["architecture"] as? [String: Any] ?? [:]
			return OpenRouterCatalogModel(
				id: id,
				name: (item["name"] as? String) ?? id,
				promptPrice: price(pricing["prompt"]),
				completionPrice: price(pricing["completion"]),
				contextLength: (item["context_length"] as? Int) ?? 0,
				created: (item["created"] as? Double) ?? Double((item["created"] as? Int) ?? 0),
				inputModalities: (architecture["input_modalities"] as? [String]) ?? [],
				outputModalities: (architecture["output_modalities"] as? [String]) ?? [],
				popularity: 0)		// 流行度另拉一次(见 fetchAll),这里先留 0
		}
	}

	/// 价格字段可能是字符串("0.0000001")也可能是数字,两种都收。
	private static func price(_ value: Any?) -> Double {
		if let number = value as? Double { return number }
		if let text = value as? String { return Double(text) ?? 0 }
		return 0
	}

	// MARK: - 分组与精选

	/// 精选:从 400 个里挑出一小撮**值得当日常主力**的。
	///
	/// ## 第一步:过筛(把噪音去掉)
	///
	/// | 规则 | 实测砍掉 |
	/// |---|---|
	/// | 排除 `~` 别名 | 11 |
	/// | 排除含 `:` 的变体(`:free` / `:batch`) | 75 |
	/// | 排除名字带 `3b/8b/nano/mini/gemma/ministral` | 37 |
	/// | 排除名字带 `image/vision/audio/coder` | 18 |
	/// | 只留文本进、文本出 | — |
	/// | 只留上下文 ≥ 128K | 31 |
	/// | **只留近 12 个月发布的** | **74 ← 最狠的一刀** |
	/// | 只留每篇估算 ≤ $0.30 | — |
	///
	/// ## 第二步:挑 15 个,**每家厂商最多 1 个**
	///
	/// **每一席挑的都是"该家最便宜的合格档"**,只是占位顺序不同:
	/// 1. **榜上有名的那几家**(`popularity > 0`,真数据,见 `OpenRouterRankings`)
	/// 2. **知名厂商保底**(`featuredMajorVendors`,按名单顺序)
	/// 3. **剩余名额按价格补**(各家最便宜的那档,从低到高)
	///
	/// ⚠️ 三步都取"该家最便宜的" —— 精选是**每家的性价比之选**,
	/// 想看那家更强的档,厂商分组里一眼就有(那边专门保证"最便宜/最平衡/最强"都在)。
	///
	/// ⚠️ 「每家最多 1 个」是这一步的关键:不设的话 deepseek / minimax 会各占两档,
	/// 15 个名额被几家便宜厂商吃光 —— 那正是 2026-08-08 用户报的那个问题。
	///
	/// ⚠️ 摆放顺序仍然是**每篇估算成本升序**(用户最早定的),和挑选顺序无关。
	///
	/// ⚠️ 被排掉的模型**没有消失** —— 厂商分组和搜索里都还在。
	static func featured(from models: [OpenRouterCatalogModel]) -> [OpenRouterCatalogModel] {

		let qualified = models.filter { model in
			guard model.isBrowseWorthy else { return false }		// 共同底线,见那个属性的注释
			guard !model.isLatestAlias else { return false }		// 精选要指名道姓,不要"永远最新"那种
			// ⚠️ 只剩上限,**没有下限了** —— 理由见上面 featuredMinUSD 那段墓志铭
			let cost = model.estimatedUSDPerArticle
			return cost > 0 && cost <= featuredMaxUSD
		}

		let byVendor = Dictionary(grouping: qualified, by: { $0.vendor })
		/// 某一家最便宜的那档
		func cheapest(of vendor: String) -> OpenRouterCatalogModel? {
			byVendor[vendor]?.min { $0.estimatedUSDPerArticle < $1.estimatedUSDPerArticle }
		}

		var picked = [OpenRouterCatalogModel]()
		var takenVendors = Set<String>()
		func take(_ model: OpenRouterCatalogModel) {
			guard picked.count < featuredCount, !takenVendors.contains(model.vendor) else { return }
			takenVendors.insert(model.vendor)
			picked.append(model)
		}

		// ① 榜上有名的先占位。
		//
		// ⚠️ **占位的是"那一家",挑出来的型号仍然取该家最便宜的合格档**(2026-08-08 用户第三次追问后改的)。
		// 第一版挑的是"上榜的那个模型本身",结果 DeepSeek 的唯一席位被 `deepseek-v4-pro`(¥0.038)占掉,
		// 而用户等着看的 `deepseek-v4-flash-0731`(¥0.008,他正在用的那个)进不来 ——
		// 因为 0731 太新,还没进那份 30 天花费榜。
		//
		// 判据:**精选是"每家的性价比之选",不是"每家最多人花钱的那个"。**
		// 流行度数据只覆盖 4 个候选(见 `OpenRouterRankings`),拿它决定"选哪个型号"太弱;
		// 拿它决定"哪家先占位"刚好 —— 那是它唯一撑得住的用途。
		// 「热门」标记照旧按每一行自己的数据显示,不受这里影响。
		for model in qualified.filter(\.isPopular).sorted(by: { $0.popularity > $1.popularity }) {
			if let pick = cheapest(of: model.vendor) { take(pick) }
		}
		// ② 知名厂商保底,按名单顺序,取该家最便宜的合格档
		for vendor in featuredMajorVendors {
			if let pick = cheapest(of: vendor) { take(pick) }
		}
		// ③ 剩余名额:各家最便宜的那档,从低到高补
		for model in byVendor.keys.compactMap({ cheapest(of: $0) })
			.sorted(by: { $0.estimatedUSDPerArticle < $1.estimatedUSDPerArticle }) {
			take(model)
		}

		return picked.sorted { lhs, rhs in
			if lhs.estimatedUSDPerArticle != rhs.estimatedUSDPerArticle {
				return lhs.estimatedUSDPerArticle < rhs.estimatedUSDPerArticle
			}
			return lhs.id < rhs.id
		}
	}

	/// 按厂商分组。厂商名按字母序,组内按价格从低到高,**每家最多 5 个**。
	///
	/// 返回值里的 `total` 是这一家过滤前的真实数量 —— 界面要拿它说明"还有多少没显示",
	/// **不许静默截断**。
	///
	/// ## 为什么要砍到 5 个(用户 2026-08-08)
	///
	/// 原来是把 400 个原样铺开,光 OpenAI 就 95 行、Anthropic 28 行,里面大半是
	/// `:batch` 变体和陈年老版本。用户的原话:「多了我觉得也没意义了,
	/// 保证最便宜的、最强的、最平衡的都在,其实就可以了」。
	///
	/// ## 那 5 个怎么挑
	///
	/// 先扔掉 `:batch` / `:free` 这类**变体**(它们是同一个模型的另一种计费/时延,
	/// 摆在一起纯属重影),然后:
	///
	/// | 席位 | 取谁 | 对应用户说的 |
	/// |---|---|---|
	/// | 1 | 最便宜 | 「最便宜的」 |
	/// | 2 | 上限内最贵 | 「最强的」 |
	/// | 3 | 价格中位 | 「最平衡的」 |
	/// | 4–5 | 先补**上过榜**的,再补**最新发布**的 | 顺带把热门和新款捞进来 |
	///
	/// ⚠️ **拿价格当"强弱"的代理指标,这是明知故犯的近似。** OpenRouter
	/// 一个质量数据都不给(见 `OpenRouterRankings`),而同一家内部价格和档位确实高度相关
	/// (opus > sonnet > haiku)。**跨厂商比就完全不成立** —— 所以这个近似**只在一家之内用**,
	/// 精选那边挑跨厂商的时候没用它。
	///
	/// ⚠️ 被砍掉的**搜索里全都还在**(`search` 走的是完整目录,不经过这里)。
	static func grouped(_ models: [OpenRouterCatalogModel])
		-> [(vendor: String, models: [OpenRouterCatalogModel], total: Int)] {

		Dictionary(grouping: models, by: { $0.vendor })
			.map { (vendor, all) in
				(vendor: vendor, models: pickHighlights(from: all), total: all.count)
			}
			.sorted { $0.vendor.localizedCaseInsensitiveCompare($1.vendor) == .orderedAscending }
	}

	/// 从一家的全部模型里挑出最多 `perVendorLimit` 个代表。规则见 `grouped` 的注释。
	static func pickHighlights(from all: [OpenRouterCatalogModel]) -> [OpenRouterCatalogModel] {

		// 先按"值不值得摆出来"过一遍(变体重影、小参数线、专用线、老版本、未标价一律不进,
		// **搜索仍然找得到**)。
		//
		// ⚠️ **兜底要分两层。** 有些厂商(实测:Cohere、字节跳动、Cognitive Computations)
		// 名下全是老模型或小参数线,过滤完是空的 —— 那一节不能就此空掉,得退回去。
		// 但退回时**仍然不要 `:free` / `:batch` 变体**:第一版一步退到底,
		// Cohere 那一节的头一行就成了「north-mini-code:free · 未标价」,难看且没用。
		let strict = all.filter(\.isBrowseWorthy)
		let loose = all.filter { !$0.id.contains(":") }
		let candidates = !strict.isEmpty ? strict : (!loose.isEmpty ? loose : all)

		// ⚠️ **没超上限就原样全给,不做任何删减。**
		// 第一版一上来就系列去重,结果「Aion Labs」名下 aion-2.0 / aion-3.0 两个
		// 被合成一个 —— 明明一屏放得下,却把"最强的那档"藏了。
		// 判据:**删减是为了治"多得没意义",不是为了整齐。不多就别删。**
		let sorted = candidates.sorted(by: isCheaper)
		guard sorted.count > perVendorLimit else { return sorted }

		// 超了才**每个系列只留一个**(取该系列最便宜的那个)。
		// 不这么做的话 Anthropic 那一节实测是三行 opus 变体,而 sonnet 根本不出现。
		var bestOfFamily = [String: OpenRouterCatalogModel]()
		for model in sorted where bestOfFamily[model.family] == nil {
			bestOfFamily[model.family] = model
		}
		let families = bestOfFamily.values.sorted(by: isCheaper)
		guard families.count > perVendorLimit else { return families }

		var picked = [OpenRouterCatalogModel]()
		var taken = Set<String>()
		func take(_ model: OpenRouterCatalogModel?) {
			guard let model, picked.count < perVendorLimit, !taken.contains(model.id) else { return }
			taken.insert(model.id)
			picked.append(model)
		}

		take(families.first)						// 最便宜
		take(families.last)							// 最强(以价格为代理)
		take(families[families.count / 2])			// 最平衡(价格中位)
		for model in families.sorted(by: { $0.created > $1.created }) { take(model) }	// 补:最新发布的

		return picked.sorted(by: isCheaper)
	}

	/// 排序用:先比每篇成本;同价时**偏好"正名"** ——
	/// 不要别名、不要 `-pro` 这种后缀更长的写法(`gpt-5.6-luna` 优先于 `gpt-5.6-luna-pro`)。
	private static func isCheaper(_ lhs: OpenRouterCatalogModel, _ rhs: OpenRouterCatalogModel) -> Bool {
		if lhs.estimatedUSDPerArticle != rhs.estimatedUSDPerArticle {
			return lhs.estimatedUSDPerArticle < rhs.estimatedUSDPerArticle
		}
		if lhs.isLatestAlias != rhs.isLatestAlias { return !lhs.isLatestAlias }
		if lhs.id.count != rhs.id.count { return lhs.id.count < rhs.id.count }
		return lhs.id < rhs.id
	}

	/// 搜索:模型 id 和展示名都匹配,不分大小写。
	static func search(_ query: String, in models: [OpenRouterCatalogModel]) -> [OpenRouterCatalogModel] {
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return [] }
		return models
			.filter { $0.id.localizedCaseInsensitiveContains(trimmed) || $0.name.localizedCaseInsensitiveContains(trimmed) }
			.sorted { $0.estimatedUSDPerArticle < $1.estimatedUSDPerArticle }
	}

	// MARK: - 磁盘缓存

	/// ⚠️ **文件名带版本号,加字段时必须 +1。**
	/// `OpenRouterCatalogModel` 是 `Codable`,加了新字段之后**旧缓存解不出来**
	/// (少字段 → 整份解码失败 → 目录变空)。换个文件名 = 旧缓存自然被无视,
	/// 而页面在"目录是空的"时会自动去拉一次 —— **自愈,不用用户做任何事**。
	/// (v2:2026-08-08 精选改用新标准,加了 created / 模态两组字段。
	///  v3:同日,加了 popularity。)
	private static var cacheURL: URL {
		let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
		return caches.appendingPathComponent("nnw-openrouter-models-v3.json")
	}

	private static let cacheDateKey = "nnwOpenRouterCatalogDateV3"

	/// 上次成功拉取的时间。没拉过就是 nil。
	static var lastRefreshed: Date? {
		UserDefaults.standard.object(forKey: cacheDateKey) as? Date
	}

	static func cached() -> [OpenRouterCatalogModel] {
		guard let data = try? Data(contentsOf: cacheURL),
			  let models = try? JSONDecoder().decode([OpenRouterCatalogModel].self, from: data) else {
			return []
		}
		return models
	}

	private static func save(_ models: [OpenRouterCatalogModel]) {
		guard let data = try? JSONEncoder().encode(models) else { return }
		try? data.write(to: cacheURL, options: .atomic)
		UserDefaults.standard.set(Date(), forKey: cacheDateKey)
	}
}

// MARK: - 流行度(OpenRouter 的任务榜单)

/// 从 OpenRouter 的任务榜单算一个"流行度"分数。
///
/// ## ⚠️ 先说清楚这份数据有多大用(2026-08-08 实测,别高估它)
///
/// 用户要「按流行度/调用次数选前 15」。**OpenRouter 没有公开调用次数**,
/// 唯一能拿到的只有网站自用的这个榜单:`/api/frontend/v1/rankings/task-spend`。它给的是
///
/// > **近 30 天**里,某个模型在**某个任务分类**下占了多少**花费**
///
/// 实测:29 个任务分类,**每个只给 10 条**,去重之后**全站只有 29 个模型有数据**。
/// 而这 29 个里大多在精选那几道筛子里就被排掉了(旧版本、`:free` 变体……),
/// **真正落到精选候选池里的只有 4 个**。
///
/// 所以这份分数的正确用法是:**"上过榜"当成一个加分项**,让那几个确实很多人在用的排前面;
/// 剩下的仍然按价格排。**不要**把 0 分解读成"没人用" —— 它只是"没进那 10 条"。
///
/// ⚠️ 还有一层偏差:榜单按**花费**排,不是按次数 —— **贵的模型天然靠前**。
/// (同一句话在 `OpenRouterModelCatalog.swift` 里也写过,是同一个接口。)
///
/// ⚠️ 这是**内部接口**,随时可能改结构或下线。所以整条链路是 best-effort:
/// 任何一步不对就返回空表,精选自动退回"按价格挑",页面不会因此坏掉。
enum OpenRouterRankings {

	private static let url = URL(string: "https://openrouter.ai/api/frontend/v1/rankings/task-spend")!

	/// - Parameter canonicalMap: `canonical_slug`(榜单用的带日期 id)→ 可调用 id
	/// - Returns: 可调用 id → 分数(各任务分类的花费占比之和)。拿不到就是空表。
	static func fetchScores(canonicalMap: [String: String]) async -> [String: Double] {

		guard !canonicalMap.isEmpty else { return [:] }

		var request = URLRequest(url: url)
		request.timeoutInterval = 20
		request.setValue("NetNewsWire AI Translation", forHTTPHeaderField: "User-Agent")

		guard let (data, response) = try? await URLSession.shared.data(for: request),
			  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
			return [:]
		}
		return parse(data, canonicalMap: canonicalMap)
	}

	/// 逐层检查,任何一层缺失就返回空表(结构变了宁可没有分数,也不要一份错的)。
	static func parse(_ data: Data, canonicalMap: [String: String]) -> [String: Double] {

		guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let payload = root["data"] as? [String: Any],
			  let spend = payload["spend"] as? [String: Any],
			  let tasks = spend["tasks"] as? [[String: Any]] else {
			return [:]
		}

		var scores = [String: Double]()
		for task in tasks {
			guard let entries = task["models"] as? [[String: Any]] else { continue }
			for entry in entries {
				guard let rawID = entry["model"] as? String,
					  let usableID = canonicalMap[rawID] else { continue }
				// 跨任务累加:一个模型在越多任务里占花费,说明它被用得越广
				scores[usableID, default: 0] += (entry["share"] as? Double) ?? 0
			}
		}
		return scores
	}
}
