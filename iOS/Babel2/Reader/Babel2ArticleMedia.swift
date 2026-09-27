import Foundation

/// 阅读页正文上方的播放器（2026-09-27 用户反馈第 1 条，ADR-041）。
///
/// - YouTube：文章链接就是视频地址，直接认出视频编号，在正文上方放一个 16:9、贴满屏幕两边的播放器，
///   在文章里原地播放（也可以点全屏）。视频简介不在文章数据里（上游解析订阅源时丢掉了），
///   由接入层重新读一次订阅源拿到，正文为空时填进正文（可以翻译）。
/// - 播客：音频地址同样不在文章数据里（上游数据库不存附件），由接入层重新读一次订阅源找到
///   （复用 1.x 的 PodcastEpisodeLocator，按订阅源缓存，包括「这个源没有音频」的结论），
///   找到后在正文上方放一个居中的音频条。
/// 离开文章或锁屏后声音会停（后台播放不在这次范围）。
struct Babel2ArticleMediaExtras: Equatable, Sendable {
	/// YouTube 视频简介（纯文本）
	var youTubeDescription: String?
	/// 播客单集的音频地址
	var audioURL: URL?

	var isEmpty: Bool { youTubeDescription == nil && audioURL == nil }
}

enum Babel2ArticleMedia {
	/// 认 YouTube 视频地址：watch?v=、youtu.be/、shorts/、live/、embed/。认不出返回 nil。
	/// 编号固定 11 位（字母、数字、- 和 _），不合规的一律不认，免得拼出坏地址。
	static func youTubeVideoID(from url: URL?) -> String? {
		guard let url, let host = url.host?.lowercased() else { return nil }
		let isYouTube = host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com")
		var candidate: String?
		if host == "youtu.be" {
			candidate = url.pathComponents.dropFirst().first
		} else if isYouTube {
			let components = url.pathComponents.dropFirst()
			if components.first == "watch" {
				candidate = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
			} else if let first = components.first, ["shorts", "live", "embed", "v"].contains(first) {
				candidate = components.dropFirst().first
			}
		}
		guard let candidate, isValidVideoID(candidate) else { return nil }
		return candidate
	}

	static func isValidVideoID(_ id: String) -> Bool {
		id.count == 11 && id.unicodeScalars.allSatisfy { scalar in
			CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII || scalar == "-" || scalar == "_"
		}
	}

	/// YouTube 文章的网页身份换成中性地址（1.x 2026-07-21 对照实验证实：页面自称 youtube.com、
	/// 却没有 YouTube 会话时，嵌入的播放器拒绝播放，报「错误代码 152」）。用 app 自己对外声明的身份
	/// （Info.plist 的 User-Agent 里写的就是这个地址）。YouTube 文章正文本来就是空的，没有相对链接受影响。
	static let neutralBaseURL = URL(string: "https://netnewswire.com/")

	/// 排版正文时用的网页身份：YouTube 文章用中性地址，其它照旧用原文地址（解析正文里的相对链接）。
	static func baseURL(for articleURL: URL?) -> URL? {
		youTubeVideoID(from: articleURL) == nil ? articleURL : neutralBaseURL
	}
}
