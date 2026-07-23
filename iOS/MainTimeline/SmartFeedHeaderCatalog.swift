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
