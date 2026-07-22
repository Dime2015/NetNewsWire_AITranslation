//
//  FeedHeroIconLoader.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 给「单源页顶部头图」抓高清图标。
//
//  为什么需要它:上游的图标管线在**落盘之前**就把一切缩到 144px
//  (IconImage.maxIconPixelSize = 48pt × 3x,见 SingleFaviconDownloader / ImageDownloader),
//  头部区的 logo 要以 ~100pt(300px)显示,144px 放大必糊。
//  本文件绕开那条管线,按**原始分辨率**抓一份,存进本 fork 自己的缓存目录,
//  与上游缓存零交集。
//
//  候选来源,按质量从高到低逐个试(都是查过代码/实测过的常见约定):
//    1. feed.iconURL     —— feed 自己声明的图标(RSS <image> / Atom logo),常见 512px
//    2. apple-touch-icon —— 网页元数据里声明的(HTMLMetadata 模块已经解析好存在库里,
//                           挑面积最大的那个),常见 180px,不少站给到 512/1024
//    3. 根目录约定路径   —— https://站点/apple-touch-icon.png(约定俗成,很多站没声明但文件在)
//    4. feed.faviconURL  —— 原始 favicon(只试 .ico 以外的,ico 基本都是小图)
//
//  收图标准:最长边 ≥ TimelineStyle.headerMinHeroPixels(默认 180px),否则试下一个。
//  全部落空 → 记进负缓存(只在本次会话内有效,下次启动会再试),
//  头部区退回用上游那张 144px 的图(小尺寸下显示,轻微发软可接受)。
//
//  下载走上游 RSWeb 的 Downloader(app 统一下载通道,自带短期缓存与请求合并)——
//  不另起 URLSession,教训见 L33(绕过统一通道的请求会破坏退避/记账)。
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

import UIKit
import os
import CryptoKit
import Account
import HTMLMetadata
import RSWeb

@MainActor final class FeedHeroIconLoader {

	static let shared = FeedHeroIconLoader()

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FeedHeroIconLoader")

	private var memoryCache = [String: UIImage]()
	/// 「这个源确实拿不到高清图」的负缓存。只在内存里 —— 下次启动会重试,
	/// 因为站点随时可能补上图标,而重试的成本被 Downloader 的短期缓存压得很低。
	private var negativeCache = Set<String>()
	private var inFlight = Set<String>()

	/// 磁盘缓存目录:Caches/FeedHeroIcons/。系统清 Caches 时一并回收,丢了就重抓。
	private let diskDirectory: URL

	private init() {
		let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
		diskDirectory = caches.appendingPathComponent("FeedHeroIcons", isDirectory: true)
		try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
	}

	/// 同步查缓存(内存 → 磁盘)。没有就返回 nil,**不会**触发网络。
	func cachedHero(for feed: Feed) -> UIImage? {
		let key = feed.feedID
		if let image = memoryCache[key] {
			return image
		}
		let fileURL = diskURL(for: key)
		if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
			memoryCache[key] = image
			return image
		}
		return nil
	}

	/// 需要时发起抓取;抓到(且够大)时回调一次。已有缓存 / 负缓存 / 正在抓,都不重复干活。
	func fetchHeroIfNeeded(for feed: Feed, onSuccess: @escaping @MainActor (UIImage) -> Void) {
		let key = feed.feedID
		guard cachedHero(for: feed) == nil,
			  !negativeCache.contains(key),
			  !inFlight.contains(key) else {
			return
		}
		inFlight.insert(key)

		let candidates = candidateURLs(for: feed)
		guard !candidates.isEmpty else {
			negativeCache.insert(key)
			inFlight.remove(key)
			return
		}

		Task { [weak self] in
			guard let self else { return }
			defer { self.inFlight.remove(key) }

			// ⚠️ 不是「第一个达标的就用」,而是**挑最大的那张**(2026-07-22 用户反馈"太糊"后改)。
			// 原因:候选里常常前面的小、后面的大 —— 比如 WordPress 的 iconURL 给的是
			// 32×32 缩略图,而把尺寸后缀去掉的同一张图有 512×512。先到先得会白白错过大图。
			// 折中:拿到 ≥headerPreferredHeroPixels 的就早停,不必把候选全试一遍。
			var bestImage: UIImage?
			var bestData: Data?
			var bestPixels: CGFloat = 0
			var bestURL: String = ""

			for url in candidates {
				do {
					let response = try await Downloader.shared.download(url)
					guard let data = response.data, !data.isEmpty,
						  let image = UIImage(data: data) else {
						continue
					}
					// UIImage(data:) 的 scale 是 1,size 就是像素数
					let px = max(image.size.width, image.size.height)
					if px > bestPixels {
						bestPixels = px
						bestImage = image
						bestData = data
						bestURL = url.absoluteString
					}
					if px >= TimelineStyle.headerPreferredHeroPixels {
						break	// 已经够好,不用再试剩下的候选
					}
				} catch {
					continue	// 单个候选失败很正常(404 等),静静试下一个
				}
			}

			if let image = bestImage, let data = bestData, bestPixels >= TimelineStyle.headerMinHeroPixels {
				try? data.write(to: self.diskURL(for: key))
				self.memoryCache[key] = image
				Self.logger.info("[头图] 源「\(feed.nameForDisplay, privacy: .public)」选中 \(Int(bestPixels))px(\(candidates.count) 个候选里最大):\(bestURL, privacy: .public)")
				onSuccess(image)
				return
			}

			Self.logger.info("[头图] 源「\(feed.nameForDisplay, privacy: .public)」\(candidates.count) 个候选最大才 \(Int(bestPixels))px,不够用,退回小图")
			self.negativeCache.insert(key)
		}
	}

	// MARK: - 候选地址

	private func candidateURLs(for feed: Feed) -> [URL] {
		var result = [URL]()
		var seen = Set<String>()

		func append(_ urlString: String?) {
			guard let urlString, !urlString.isEmpty,
				  let url = URL(string: urlString),
				  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
				  !seen.contains(url.absoluteString) else {
				return
			}
			seen.insert(url.absoluteString)
			result.append(url)
		}

		// 1. feed 自己声明的图标 —— 先放它的「原图变体」,再放原样地址。
		//    因为很多站给的是缩略版(实测:Marginal Revolution 给 32×32,
		//    去掉 -32x32 后缀的同一张图是 512×512;Jetpack 的 ?fit=32,32 改成
		//    ?fit=1024,1024 同样能拿到 512×512)。变体拿不到就自动落回原样地址。
		for upgraded in Self.upscaledVariants(of: feed.iconURL) {
			append(upgraded)
		}
		append(feed.iconURL)

		// 2. 网页元数据里的 apple-touch-icon(挑面积最大的;上游已解析入库,零网络请求)
		if let homePage = feed.homePageURL,
		   let metadata = HTMLMetadataDownloader.shared.cachedMetadata(for: homePage) {
			let best = metadata.appleTouchIcons
				.max { ($0.width * $0.height) < ($1.width * $1.height) }
			if let iconURLString = best?.urlString {
				// 元数据里的地址可能是相对路径,相对主页解析
				if let base = URL(string: homePage), let resolved = URL(string: iconURLString, relativeTo: base) {
					append(resolved.absoluteString)
				} else {
					append(iconURLString)
				}
			}
		}

		// 3. 根目录的约定路径(很多站没声明但文件真的在)。
		//    大的排前面 —— 上面的挑选逻辑会取最大的那张。
		if let homePage = feed.homePageURL, let base = URL(string: homePage) {
			let conventionalPaths = [
				"/apple-touch-icon-180x180.png",
				"/apple-touch-icon-precomposed.png",
				"/apple-touch-icon.png"
			]
			for path in conventionalPaths {
				if let root = URL(string: path, relativeTo: base) {
					append(root.absoluteString)
				}
			}
		}

		// 4. 原始 favicon(.ico 基本都是 32px,不值得下,跳过)
		if let favicon = feed.faviconURL, !favicon.lowercased().hasSuffix(".ico") {
			for upgraded in Self.upscaledVariants(of: favicon) {
				append(upgraded)
			}
			append(favicon)
		}

		return result
	}

	/// 把「缩略图地址」还原成「原图地址」的几种常见变体(都是 2026-07-22 curl 实测过的)。
	/// 返回的地址不保证存在 —— 拿不到就自动落回原样地址,没有副作用。
	///
	/// | 站点类型 | 缩略图地址长什么样 | 变体 | 实测收益 |
	/// |---|---|---|---|
	/// | WordPress | `cropped-logo-32x32.png` | 去掉 `-32x32` | 32px → 512px |
	/// | Jetpack/Photon | `...?fit=32%2C32&ssl=1` | `fit` 改大 | 32px → 512px |
	/// | 通用 | `...?w=64` / `?resize=64,64` | 数字改大 | 视站点 |
	static func upscaledVariants(of urlString: String?) -> [String] {
		guard let urlString, !urlString.isEmpty else { return [] }
		var result = [String]()

		// WordPress 的 `-宽x高` 尺寸后缀:cropped-foo-32x32.png → cropped-foo.png
		if let range = urlString.range(of: "-[0-9]{2,4}x[0-9]{2,4}(?=\\.[a-zA-Z]{3,4})", options: .regularExpression) {
			result.append(urlString.replacingCharacters(in: range, with: ""))
		}

		// 查询参数里的尺寸:fit / resize / w / h,统统调到 1024
		if urlString.contains("?") {
			var bumped = urlString
			let patterns: [(String, String)] = [
				("fit=[0-9]+(%2C|,)[0-9]+", "fit=1024%2C1024"),
				("resize=[0-9]+(%2C|,)[0-9]+", "resize=1024%2C1024"),
				("[?&]w=[0-9]+", "w=1024"),
				("[?&]h=[0-9]+", "h=1024")
			]
			var changed = false
			for (pattern, replacement) in patterns {
				if let range = bumped.range(of: pattern, options: .regularExpression) {
					// 保留原来的 ? 或 & 前缀
					let matched = String(bumped[range])
					let prefix = matched.hasPrefix("?") ? "?" : (matched.hasPrefix("&") ? "&" : "")
					bumped = bumped.replacingCharacters(in: range, with: prefix + replacement)
					changed = true
				}
			}
			if changed {
				result.append(bumped)
			}
		}

		return result
	}

	private func diskURL(for feedID: String) -> URL {
		// feedID 是个 URL,不能直接当文件名;取 SHA256 前 16 字节的十六进制,稳定且不碰撞
		let digest = SHA256.hash(data: Data(feedID.utf8))
		let name = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
		return diskDirectory.appendingPathComponent(name + ".png")
	}
}
