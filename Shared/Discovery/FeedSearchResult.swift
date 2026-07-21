//
//  FeedSearchResult.swift
//  NetNewsWire
//
//  [发现] 本 fork 新增,上游没有这个文件。
//

import Foundation

/// 搜索出来的一条「可订阅的东西」。
///
/// 不管是播客、Reddit 子版、YouTube 频道还是普通网站,搜到之后都装进这个结构,
/// 界面只认这一种东西 —— 以后再加新的内容类型,界面一行都不用改。
struct FeedSearchResult: Identifiable, Hashable {

	/// 内容类型。目前只有前两种在用(Phase A),后两种是 Phase B 的位置。
	enum Kind: String {
		case podcast
		case reddit
		case youtube
		case website

		/// 显示在结果行右侧的小标签
		var label: String {
			switch self {
			case .podcast: return "播客"
			case .reddit: return "Reddit"
			case .youtube: return "YouTube"
			case .website: return "网站"
			}
		}
	}

	let kind: Kind

	/// 订阅后显示的名字
	let title: String

	/// 第二行的说明(播客是作者名,Reddit 是订阅人数和排序方式)
	let subtitle: String?

	/// **可以直接拿去订阅的地址**。这是整个结构里最重要的一个字段。
	let feedURL: String

	/// 节目/子版的主页,目前只用于展示,没有它也不影响订阅
	let homePageURL: String?

	/// Apple Podcasts 的节目 ID。Phase B 做「跳转到播客 app」时要用,
	/// 现在先带着,免得以后还要重新搜一遍。
	let appleCollectionID: String?

	/// 结果行左边那个小图标的地址。没有就为 nil,界面会退回按类型显示的符号。
	///
	/// **这两处都是白拿的,没有为它多发任何请求**:
	///   · 播客 —— iTunes 搜索返回里本来就带 `artworkUrl100`
	///   · YouTube —— 频道头像就在我们为了取 channelId 而抓的那张页面里
	/// Reddit 拿不到(它的接口 403),普通网站也没有可靠的免费来源,
	/// 这两类退回类型符号即可。
	let iconURL: String?

	/// 没有图标时,按类型显示的 SF Symbol 名。
	var fallbackSymbolName: String {
		switch kind {
		case .podcast: return "mic.fill"
		case .reddit: return "bubble.left.and.bubble.right.fill"
		case .youtube: return "play.rectangle.fill"
		case .website: return "globe"
		}
	}

	/// 用地址做唯一标识 —— 同一个 feed 不管从哪条路搜出来都算同一条
	var id: String { feedURL }

	init(kind: Kind,
		 title: String,
		 subtitle: String? = nil,
		 feedURL: String,
		 homePageURL: String? = nil,
		 appleCollectionID: String? = nil,
		 iconURL: String? = nil) {
		self.kind = kind
		self.title = title
		self.subtitle = subtitle
		self.feedURL = feedURL
		self.homePageURL = homePageURL
		self.appleCollectionID = appleCollectionID
		self.iconURL = iconURL
	}
}

/// 搜索过程中可能出的错。
///
/// 每一条都要能直接说给用户听 —— 用户读不懂代码,错误信息是他唯一的线索。
enum FeedSearchError: LocalizedError {

	case network(Error)
	case badResponse(Int)
	case notAFeed
	case emptyInput
	case badSubredditName
	case youTubeChannelNotFound
	case keywordNotSupported(hint: String)
	case websiteFeedNotFound
	/// Reddit 单独一条:它对不同的失败给的状态码含义很明确,
	/// 而「限流」和「版块不存在」对用户来说是完全不同的两件事 ——
	/// 一个该等一下重试,一个该改名字重输。混成一句话会让人白折腾。
	case reddit(statusCode: Int)

	var errorDescription: String? {
		switch self {
		case .network:
			return "连不上网络,请检查网络后重试。"
		case .badResponse(let code):
			return "对方服务器返回了错误(\(code))。稍后再试试。"
		case .notAFeed:
			return "这个地址取不到内容,可能名字拼错了,或者这个版块不存在。"
		case .emptyInput:
			return "请先输入要搜索的内容。"
		case .badSubredditName:
			return "认不出版块名。可以直接输入版块名(例如 apple)、r/apple,或者粘一个 Reddit 链接。"
		case .keywordNotSupported(let hint):
			return hint
		case .websiteFeedNotFound:
			return "这个网站上没找到 RSS 地址。\n\n"
				+ "已经试过:读网页里的 RSS 声明,以及 /feed/、/rss、/index.xml 等常见地址。\n\n"
				+ "有些网站确实不提供 RSS。如果你知道它的 RSS 地址,可以直接把那个地址粘进来订阅。"
		case .youTubeChannelNotFound:
			return "没能从这个地址找出 YouTube 频道。可以粘频道主页地址(youtube.com/@名字),或者直接输入 @名字。注意:视频播放页的地址不行,要频道的地址。"
		case .reddit(let code):
			switch code {
			case 429:
				return "Reddit 暂时限制了访问频率,等一两分钟再试。"
			case 403:
				return "Reddit 拒绝了这次请求。这个版块可能是私密的。"
			case 404:
				return "没找到这个版块,检查一下名字拼写。"
			default:
				return "Reddit 返回了错误(\(code))。稍后再试试。"
			}
		}
	}
}
