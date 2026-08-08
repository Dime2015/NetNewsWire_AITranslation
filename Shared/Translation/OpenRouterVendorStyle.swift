//
//  OpenRouterVendorStyle.swift
//  NetNewsWire — AI 翻译 fork
//
//  [翻译] 本 fork 新增。模型列表里**厂商那一行**长什么样。
//
//  ## 为什么不是真 logo(2026-08-08 查过才放弃的,别再试同一条路)
//
//  用户问「能不能把厂商 logo 加在前面,替代那个 ~」。查证结果:
//
//  | 想拿 logo | 实测 |
//  |---|---|
//  | `/api/v1/models` 里有图片地址吗 | ❌ 一个都没有(字段全查过) |
//  | OpenRouter 自己的图标 | ✅ 有,但**只有 SVG**(`/images/icons/Anthropic.svg`) |
//  | 有 PNG / WebP 吗 | ❌ 404;`_next/image` 转换接口 400 |
//  | 文件名能从 slug 推出来吗 | ❌ `deepseek` → `DeepSeek.svg`、`google` → `GoogleGemini.svg`,58 家得手工维护 |
//
//  而 **iOS 运行时加载不了 SVG**(只有编译进资源目录的能用)。要显示就得自己写个
//  SVG 路径解析器,或者拿 WKWebView 去截 58 张图 —— 为了装饰做这个不划算,
//  而且那个图标路径没有文档,随时会变。
//
//  ## 所以改成两件都能自己掌控的事
//
//  1. **厂商名写成正经品牌名**:`z-ai` → `Z.AI`、`x-ai` → `xAI`、
//     `bytedance-seed` → `ByteDance Seed`;中文品牌直接用中文(`moonshotai` → 月之暗面)。
//     ⚠️ 用户嫌弃的那个 `~` 就此消失 —— 它是 OpenRouter 的**别名命名空间**
//     (`~anthropic/claude-opus-latest` 永远指向最新的 Opus),是有意义的,
//     所以不是删掉了事,而是翻译成人话:「Anthropic · 始终最新」。
//  2. **自绘一颗字母徽标**放在厂商名前面,给列表一个 logo 那样的视觉节奏。
//     用主题色 + 白字,和全 app 同源;不下载、不依赖第三方素材、不会 404。
//

#if os(iOS)

import UIKit

enum OpenRouterVendorStyle {

	// MARK: - 厂商显示名

	/// OpenRouter 的别名命名空间前缀。`~anthropic/claude-opus-latest` 这种,
	/// 指向"这一家当前最新的那个",不是某个具体版本。
	private static let aliasPrefix = "~"

	/// slug → 品牌名。**没列进来的走下面的通用美化**(首字母大写 + 连字符换空格),
	/// 所以漏一个也不会难看,只是不够正式。
	private static let displayNames: [String: String] = [
		"ai21": "AI21", "aion-labs": "Aion Labs", "allenai": "AllenAI",
		"anthracite-org": "Anthracite", "arcee-ai": "Arcee AI",
		"baidu": "百度", "bytedance": "字节跳动", "bytedance-seed": "字节跳动 Seed",
		"cognitivecomputations": "Cognitive Computations", "deepcogito": "Deep Cogito",
		"deepseek": "DeepSeek", "ibm-granite": "IBM Granite", "inclusionai": "InclusionAI",
		"kwaipilot": "快手 KwaiPilot", "meituan": "美团", "meta-llama": "Meta Llama",
		"minimax": "MiniMax", "mistralai": "Mistral AI", "moonshotai": "月之暗面 Moonshot",
		"nex-agi": "Nex AGI", "nousresearch": "Nous Research", "nvidia": "NVIDIA",
		"openai": "OpenAI", "openrouter": "OpenRouter", "qwen": "通义千问 Qwen",
		"rekaai": "Reka AI", "sakana": "Sakana AI", "sao10k": "Sao10K",
		"stepfun": "阶跃星辰 StepFun", "tencent": "腾讯", "thedrummer": "TheDrummer",
		"thinkingmachines": "Thinking Machines", "x-ai": "xAI",
		"xiaomi": "小米", "z-ai": "智谱 Z.AI"
	]

	/// 厂商行上显示的名字。
	///
	/// ⚠️ 2026-08-08 起**别名已经并进对应厂商**(见 `OpenRouterCatalogModel.vendor`),
	/// 所以这里正常情况下收不到带 `~` 的 slug 了 —— 但还是留着这一手,
	/// 万一哪天分组规则又变,至少不会把 `~` 原样摆到屏幕上。
	static func displayName(for vendor: String) -> String {
		guard vendor.hasPrefix(aliasPrefix) else { return baseName(for: vendor) }
		return "\(baseName(for: String(vendor.dropFirst()))) · 始终最新"
	}

	private static func baseName(for slug: String) -> String {
		if let known = displayNames[slug] { return known }
		// 通用美化:`some-vendor` → `Some Vendor`
		return slug.split(separator: "-")
			.map { $0.prefix(1).uppercased() + $0.dropFirst() }
			.joined(separator: " ")
	}

	// MARK: - 字母徽标

	/// 圆角方块的边长(pt)。和行里的文字比例试出来的:再大就喧宾夺主。
	private static let badgeSize: CGFloat = 22

	/// 画好的徽标缓存。⚠️ 键要带**颜色**:换主题色之后同一个厂商得重画一张,
	/// 只用 slug 当键的话换色后还是旧图(这个项目为"烘焙成图片的东西不会自己跟随"
	/// 栽过好几次,见 L105/L119)。
	@MainActor private static var cache: [String: UIImage] = [:]

	/// 厂商图标:**有真 logo 就用真的,没有才画字母徽标**。
	///
	/// 25 家有真 logo(资源目录里的 `vendor-<slug>`,来源与校验和见 README-vendor-icons.md),
	/// 另外 27 家 OpenRouter 和 Simple Icons 都没有,继续用字母徽标 —— 用户 2026-08-08
	/// 看过对照表后选的方案 A(接受两者混排)。
	@MainActor static func icon(for vendor: String, traits: UITraitCollection) -> UIImage? {
		let slug = vendor.hasPrefix(aliasPrefix) ? String(vendor.dropFirst()) : vendor
		// ⚠️ 资源目录里的 SVG 是**矢量**的,没有分辨率概念 —— 任何尺寸都清晰,
		// 而且 25 个加起来才 24KB。不需要、也不该再存一份"高清大图"。
		if let logo = UIImage(named: "vendor-\(slug)") {
			return logo
		}
		return badge(for: vendor, traits: traits)
	}

	/// 字母徽标:主题色圆角方块 + 白色首字母。**没有真 logo 的厂商用它兜底。**
	///
	/// 首字母取自 **slug**(一定是拉丁字母),不取显示名 —— 显示名可能是中文,
	/// 画在 22pt 的方块里既挤又认不出。
	@MainActor static func badge(for vendor: String, traits: UITraitCollection) -> UIImage? {

		let slug = vendor.hasPrefix(aliasPrefix) ? String(vendor.dropFirst()) : vendor
		guard let letter = slug.first(where: { $0.isLetter })?.uppercased() else { return nil }

		let color = NNWAccentPalette.live.resolvedColor(with: traits)
		let key = "\(letter)|\(color.description)"
		if let cached = cache[key] { return cached }

		let size = CGSize(width: badgeSize, height: badgeSize)
		let image = UIGraphicsImageRenderer(size: size).image { context in
			let rect = CGRect(origin: .zero, size: size)
			color.setFill()
			UIBezierPath(roundedRect: rect, cornerRadius: badgeSize * 0.28).fill()

			let font = UIFont.systemFont(ofSize: badgeSize * 0.55, weight: .semibold)
			let attributes: [NSAttributedString.Key: Any] = [
				.font: font,
				.foregroundColor: UIColor.white
			]
			let text = letter as NSString
			let textSize = text.size(withAttributes: attributes)
			text.draw(at: CGPoint(x: (size.width - textSize.width) / 2,
								  y: (size.height - textSize.height) / 2),
					  withAttributes: attributes)
			_ = context
		}
		cache[key] = image
		return image
	}

	/// 换主题色 / 换深浅色之后叫一次,不然徽标停在旧颜色上。
	@MainActor static func invalidateBadgeCache() {
		cache.removeAll()
	}
}

#endif
