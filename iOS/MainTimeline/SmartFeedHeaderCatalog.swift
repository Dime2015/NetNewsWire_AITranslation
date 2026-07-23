//
//  SmartFeedHeaderCatalog.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 三个智能源(今天 / 全部未读 / 已加星标)的顶部头图配置。
//  本 fork 新增文件,上游没有。
//
//  ## 这是干什么的
//
//  普通订阅源的头图是**抓来的**(源自己的图标/封面,见 FeedHeroIconLoader)。
//  智能源不是真的订阅源,没有图标可抓 —— 所以它们的头图是**手工挑的画**,
//  随 app 一起打包。这个文件就是「哪个智能源用哪张画、标题染什么色」的对照表。
//
//  ## 素材是怎么来的(别直接把原图换进去)
//
//  原图放在 `external resources/headers/`(不进仓库),
//  经 `tools/make-header-assets.swift` 加工后才进资源目录。加工做了四件事,
//  每一件都是量过之后才定的,详见那个脚本的文件头:
//  ①把画里的"纸"对齐到 app 的暖纸 ②三张统一曝光 ③按头图比例挑构图 ④单出一版深色素材。
//
//  **要换图或调效果,改那个脚本再跑一次**,不要手动往资源目录里塞图 ——
//  否则新图和旧图的纸色、明暗对不上,三个智能源之间切换会一亮一暗地跳。
//
//  ## 为什么不碰 Shared/SmartFeeds/
//
//  那是 CLAUDE.md 里的 A 级禁区。这里**只读地**问 `SmartFeedsController.shared`
//  要那三个现成的对象,拿来做身份比对,一行实现都没改。
//

#if os(iOS)

import UIKit
import Account

@MainActor enum SmartFeedHeaderCatalog {

	/// 一个智能源的头图配置
	struct Entry {
		/// 资源目录里的图片名(带浅色 / 深色两版,系统自动选)
		let assetName: String
		/// 标题的品牌色。
		///
		/// ⚠️ 这里给的是**理想色**,不是最终显示的颜色 —— 它还要过一遍
		/// `FeedIconColorAnalyzer.readableTitleColor`,在纸色上压到对比度达标为止
		/// (浅色模式往深里压、深色模式往亮里提)。和普通订阅源走的是同一套规则,
		/// 所以两类页面的标题观感一致。
		let titleColor: UIColor
		/// 只用于日志
		let debugName: String

		/// 滚动停靠之后,标题要不要**换成系统那套**(页面标题 + 副标题)。
		///
		/// 只有**首页**是 true:顶部写 app 名「Babel」当报头,
		/// 滚上去之后换成「Feed / 更新于 x 分钟前」——
		/// 那两行是上游一直在维护的信息(刷新时间),不该被我们的报头长期挡掉。
		/// 用户 2026-07-23 的原话:「让 Babel 一边飞到中间,一边渐变成 Feed 更新于x分钟前」。
		var usesSystemDockedTitle = false
	}

	/// 文件夹页的头图。**所有文件夹共用一张**(书架与文书箱,正是"文件夹"的意象)——
	/// 身份由标题(文件夹名)承担,图只负责给这一类页面一个统一的门面。
	static let folder = Entry(assetName: "HeaderArtFolder",
							  // 书箱与卷册的靛蓝
							  titleColor: UIColor(red: 0x3A / 255, green: 0x58 / 255, blue: 0x78 / 255, alpha: 1),
							  debugName: "文件夹")

	/// 订阅源列表页(首页)的头图。标题是 app 名「Babel」,当报头用。
	static let feedList = Entry(assetName: "HeaderArtFeedList",
								// 杂志封面与人物衣袍的靛蓝
								titleColor: UIColor(red: 0x36 / 255, green: 0x50 / 255, blue: 0x72 / 255, alpha: 1),
								debugName: "订阅列表",
								usesSystemDockedTitle: true)

	/// 首页头图上写的字。**不用页面原名(Feed / 订阅)**,用 app 名当报头 ——
	/// 首页是整个 app 的门面,这是用户 2026-07-23 定的。
	static let feedListTitle = "Babel"

	/// [阅读档] 首页头图**跟着底部三档换**(2026-07-23 用户要求):
	/// 换档时页面本身的变化(哪些源、有没有数字)不够醒目,让头图跟着换,
	/// **一眼就知道自己在哪一档** —— 头图从装饰变成了状态指示。
	///
	/// 三幅画都出自同一套素材:
	/// | 档 | 画的是什么 |
	/// |---|---|
	/// | 未读 | 一个人在读杂志(手上这本 = 还没读完的) |
	/// | 全部 | 一屋子成捆的杂志(全部家当都在这儿) |
	/// | ★ | 那具铠甲 / 一箱珍藏(值得收着的) |
	///
	/// ⚠️ 后两张是**为首页单独裁过**的(`HeaderArtFeedList*`),不是直接借用
	/// 「已加星标」那张 —— 那张按 1/4 屏(比例 1.84)裁,首页是 1/5 屏(2.30),
	/// 直接拿来会被 aspectFill 再切掉两成,正是 L72 那次把主体切没的成因。
	static func feedListEntry(for mode: NNWReadingMode) -> Entry {
		switch mode {
		case .unread:
			return feedList
		case .all:
			return Entry(assetName: "HeaderArtFeedListAll",
						 // 同一间屋子、同一件衣袍的靛蓝,和「未读」那张保持一家
						 titleColor: UIColor(red: 0x36 / 255, green: 0x50 / 255, blue: 0x72 / 255, alpha: 1),
						 debugName: "首页·全部",
						 usesSystemDockedTitle: true)
		case .starred:
			return Entry(assetName: "HeaderArtFeedListStarred",
						 // 器物与花枝的赭金(和「已加星标」页同一个色,它们本来就是同一幅画)
						 titleColor: UIColor(red: 0x8A / 255, green: 0x5A / 255, blue: 0x2B / 255, alpha: 1),
						 debugName: "首页·星标",
						 usesSystemDockedTitle: true)
		}
	}

	/// 当前时间线展示的是不是这三个智能源之一?是就返回它的头图配置。
	///
	/// 用**对象身份**比对(`===`),而不是比名字 —— 名字会随语言变,
	/// 而 `SmartFeedsController` 里那三个是全局单例,一辈子就那三个对象。
	/// (`PseudoFeed` 上游就声明了 `AnyObject`,所以 `===` 是合法的。)
	static func entry(for sidebarItem: SidebarItem?) -> Entry? {
		guard let item = sidebarItem as? PseudoFeed else { return nil }

		let controller = SmartFeedsController.shared
		if item === controller.todayFeed {
			return Entry(assetName: "SmartFeedHeaderToday",
						 // 落日的橙红,正好是 app 的强调色(陶土红)那一族
						 titleColor: UIColor(red: 0xC0 / 255, green: 0x60 / 255, blue: 0x3A / 255, alpha: 1),
						 debugName: "今天")
		}
		if item === controller.unreadFeed {
			return Entry(assetName: "SmartFeedHeaderUnread",
						 // 信使与主人衣服的靛蓝
						 titleColor: UIColor(red: 0x3A / 255, green: 0x58 / 255, blue: 0x78 / 255, alpha: 1),
						 debugName: "全部未读")
		}
		if item === controller.starredFeed {
			return Entry(assetName: "SmartFeedHeaderStarred",
						 // 器物与花枝的赭金
						 titleColor: UIColor(red: 0x8A / 255, green: 0x5A / 255, blue: 0x2B / 255, alpha: 1),
						 debugName: "已加星标")
		}
		return nil
	}
}

#endif
