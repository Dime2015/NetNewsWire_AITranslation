import Foundation
import UIKit
import CryptoKit
import Babel2Core

/// 自定义订阅源图标（2026-09-27 用户反馈第 8 条，ADR-046）。
///
/// 用户在首页长按或文章列表「更多」里点「更换图标…」选一张图：页面先裁成正方形、缩到最长 512 像素，
/// 这里存成 PNG，放在 app 自己的资料夹（Application Support/Babel2CustomFeedIcons），按「账户 + 订阅源」各一张。
/// 设了自定义图标的源，首页、文章列表、阅读页的小图标和文章列表顶部的大图都用它（优先于网站自己的图标）；
/// 「恢复默认图标」删掉这张图。只存在这台手机上，不跟账户同步。
@MainActor
enum Babel2LiveCustomFeedIcons {
	/// 列表用的小图（最长边 96 像素，与图标备份同一规格），第一次用到时从文件做一次。
	private static var compact = [String: Data]()
	/// 查过、确定没有自定义图标的源（不再每次去碰文件）。
	private static var missing = Set<String>()
	/// 仅供自动化测试：换一个存放目录，不碰真实数据。
	static var directoryOverrideForTesting: URL?

	static var directoryURL: URL {
		directoryOverrideForTesting ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("Babel2CustomFeedIcons", isDirectory: true)
	}

	private static func key(_ id: FeedSnapshot.ID) -> String {
		"\(id.accountID)|\(id.feedID)"
	}

	/// 文件名用「账户 + 订阅源编号」的 SHA-256（编号常是完整网址，含斜杠，不能直接当文件名）。
	static func fileURL(for id: FeedSnapshot.ID) -> URL {
		let digest = SHA256.hash(data: Data(key(id).utf8)).map { String(format: "%02x", $0) }.joined()
		return directoryURL.appendingPathComponent(digest + ".png")
	}

	static func hasCustomIcon(_ id: FeedSnapshot.ID) -> Bool {
		iconData(for: id) != nil
	}

	/// 列表、窄栏、阅读页用的小图；没有自定义图标时为 nil。
	static func iconData(for id: FeedSnapshot.ID) -> Data? {
		let key = key(id)
		if let data = compact[key] { return data }
		if missing.contains(key) { return nil }
		guard let data = try? Data(contentsOf: fileURL(for: id)),
			let image = UIImage(data: data),
			let small = Babel2LiveIconCache.compactData(for: image) else {
			missing.insert(key)
			return nil
		}
		compact[key] = small
		return small
	}

	/// 文章列表顶部大图用原图（512 像素）。
	static func image(for id: FeedSnapshot.ID) -> UIImage? {
		guard iconData(for: id) != nil else { return nil }
		return UIImage(contentsOfFile: fileURL(for: id).path)
	}

	/// 存一张新图（data = nil：恢复默认）。成功后通知首页与打开着的页面换图，返回 true。
	@discardableResult
	static func set(_ data: Data?, for id: FeedSnapshot.ID) -> Bool {
		let url = fileURL(for: id)
		do {
			if let data {
				guard UIImage(data: data) != nil else { return false }
				try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
				try data.write(to: url, options: .atomic)
			} else if FileManager.default.fileExists(atPath: url.path) {
				try FileManager.default.removeItem(at: url)
			}
		} catch {
			return false
		}
		compact[key(id)] = nil
		missing.remove(key(id))
		NotificationCenter.default.post(name: .babel2LibraryDidChange, object: nil)
		return true
	}

	/// 仅供自动化测试：清空内存里的记录（模拟重新启动后第一次读）。
	static func forgetCachedForTesting() {
		compact.removeAll()
		missing.removeAll()
	}
}
