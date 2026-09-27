import Foundation
import WebKit

/// 内置浏览器去广告（2026-09-27 用户反馈第 10 条，ADR-047）。
///
/// 用系统自带的内容拦截（WebKit 内容规则表）：不注入脚本、不经过任何服务器，由系统在网页请求发出前直接拦下。
/// 两类规则：
/// 1. **拦请求**：常见广告网络与跟踪器的域名（其中 42 个取自上游 NetNewsWire 的 `ContentRules.json`，MIT 许可，
///    再补上常见的广告联盟），只拦「第三方」请求——直接打开这些网站本身不受影响；
///    规则按域名写（`…//(子域.)域名/`），网址参数里碰巧出现这些字样不会误伤。
/// 2. **收起空位**：广告被拦后页面上常留一块空白，把常见的广告位元素隐藏掉（选择器取得保守，只认广告专用的写法）。
/// 默认开；浏览器右上角「•••」里可以对当前页面临时关掉（不记住，下次打开浏览器又是开的）。
enum Babel2AdBlocker {
	/// 规则有改动时换一个编号，系统会重新编译。
	static let identifier = "babel2.adblock.v1"

	/// 拦截的域名（含所有子域）。
	static let blockedDomains = [
		// 上游 NetNewsWire ContentRules.json（42 个）
		"360yield.com", "3lift.com", "4dex.io", "a-mo.net", "a-mx.com", "adform.net", "adnxs.com", "adsrvr.org",
		"amazon-adsystem.com", "amx1.net", "chartbeat.com", "creativecdn.com", "criteo.com", "criteo.net", "demdex.net",
		"doubleclick.net", "facebook.net", "go-mpulse.net", "google-analytics.com", "googlesyndication.com",
		"googletagmanager.com", "imrworldwide.com", "liadm.com", "lijit.com", "moatads.com", "omtrdc.net",
		"onetag-sys.com", "openx.net", "outbrain.com", "pubmatic.com", "quantserve.com", "r2b2.io", "rezync.com",
		"rlcdn.com", "scorecardresearch.com", "sentry.io", "serving-sys.com", "sharethrough.com", "smartadserver.com",
		"taboola.com", "track.us.org", "yieldmo.com",
		// 补充：常见广告联盟与广告验证
		"googleadservices.com", "adservice.google.com", "2mdn.net", "rubiconproject.com", "casalemedia.com",
		"indexww.com", "bidswitch.net", "adsafeprotected.com", "doubleverify.com", "teads.tv", "media.net", "mgid.com",
		"revcontent.com", "zemanta.com", "adroll.com", "contextweb.com", "33across.com", "sovrn.com", "gumgum.com",
		"yieldlab.net", "adition.com", "spotxchange.com", "smaato.net", "zedo.com", "propellerads.com", "popads.net",
		"exoclick.com", "adskeeper.com",
		// 补充：中文网站常见的广告网络
		"pos.baidu.com", "cpro.baidu.com", "cbjs.baidu.com", "cpro.baidustatic.com", "tanx.com", "mediav.com",
		"miaozhen.com", "admaster.com.cn"
	]

	/// 广告被拦后留下的空位：这些元素直接隐藏。
	static let hiddenSelectors = [
		"ins.adsbygoogle", ".adsbygoogle", "[id^='google_ads_iframe']", "[id^='div-gpt-ad']", "[data-google-query-id]",
		"amp-ad", "amp-embed[type='taboola']", "div[id^='taboola-']", ".trc_related_container", ".OUTBRAIN",
		".ob-widget", "[data-ad-slot]", ".ad-slot", ".ad-container", ".advertisement", "[aria-label='Advertisement']"
	]

	/// 按域名匹配的网址规则：`http(s)://`（可带任意子域）+ 域名 + `/` 或 `:`（端口）。
	static func urlFilter(for domain: String) -> String {
		"^[^:]+://+([^:/]+\\.)?" + domain.replacingOccurrences(of: ".", with: "\\.") + "[:/]"
	}

	/// 规则表（JSON，系统内容拦截格式）。
	static var encodedRules: String {
		var rules: [[String: Any]] = blockedDomains.map { domain in
			["trigger": ["url-filter": urlFilter(for: domain), "load-type": ["third-party"]],
			 "action": ["type": "block"]]
		}
		rules.append(["trigger": ["url-filter": ".*"],
			"action": ["type": "css-display-none", "selector": hiddenSelectors.joined(separator: ", ")]])
		guard let data = try? JSONSerialization.data(withJSONObject: rules),
			let json = String(data: data, encoding: .utf8) else { return "[]" }
		return json
	}

	@MainActor private static var compiled: WKContentRuleList?

	/// 编译好的规则表（每次启动编译一次，之后直接用；编译失败时返回 nil，浏览器照常打开、只是不去广告）。
	@MainActor
	static func ruleList() async -> WKContentRuleList? {
		if let compiled { return compiled }
		guard let store = WKContentRuleListStore.default() else { return nil }
		let list = try? await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: encodedRules)
		compiled = list
		return list
	}
}
