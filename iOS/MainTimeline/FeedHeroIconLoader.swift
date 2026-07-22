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
	/// 每个源已经尝试过几次(**成功失败都计数**,保证一定会终止)。
	///
	/// ⚠️ 这里**不能用「失败一次就永久放弃」的负缓存**(2026-07-22 踩过):
	/// 候选地址有一部分来自 `HTMLMetadataDownloader.cachedMetadata`,而那是个
	/// **内存缓存,app 启动时是空的** —— 第一次问必然返回 nil 并异步去取。
	/// 也就是说**第一次抓图时,apple-touch-icon 和 og:image 这两类候选根本还不存在**。
	/// 一次就放弃的话,元数据到货后永远轮不到重试,YouTube / 播客这类
	/// (iconURL、faviconURL 全空,只能靠 og:image)就永远退回纯色渐变。
	/// 所以改成计数,允许在新信息到货时再试几次;上限防止无限重试。
	private var attemptCounts = [String: Int]()
	private static let maxAttempts = 3
	private var inFlight = Set<String>()
	/// 「这一轮抓取还没结束,但期间又有新信息到货」——本轮结束后要再抓一次的源。
	/// ⚠️ 没有它会有一个很隐蔽的竞态(2026-07-22 实测踩到):
	/// 网页元数据是异步取的,它到货的通知**正好落在第一轮抓取进行中**,
	/// 被 inFlight 闸门挡掉;而这轮结束后不会再有通知,于是 og:image 那条路
	/// 永远轮不到 —— YouTube / 播客类源就一直停在纯色渐变。
	private var retryRequested = Set<String>()

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

	/// 需要时发起抓取;抓到**更大的一张**时回调。
	///
	/// ⚠️ 注意这里是「不够好就继续升级」,不是「拿到一张就收工」(2026-07-22 踩过):
	/// 硅谷101 第一轮只能拿到 192px 的 apple-touch-icon(白底,拉满全宽很难看),
	/// 如果把它当最终答案缓存下来,那张 1400×1400 的播客封面就永远轮不到 ——
	/// 因为封面地址来自网页元数据,而元数据是异步到货的,第一轮压根还不存在。
	/// 所以:只要当前手里的图还没到 headerPreferredHeroPixels,就允许再抓(有次数上限)。
	func fetchHeroIfNeeded(for feed: Feed, onSuccess: @escaping @MainActor (UIImage) -> Void) {
		let key = feed.feedID

		// 手里已有的图有多好?已经够好就彻底收工。
		let currentImage: UIImage? = cachedHero(for: feed)
		let currentPixels: CGFloat = currentImage.map { max($0.size.width, $0.size.height) * $0.scale } ?? 0
		let currentUsable: Bool = currentImage.map { Self.isUsableAsHero($0) } ?? false
		let currentScore: CGFloat = Self.heroScore(pixels: currentPixels, squarish: true, usable: currentUsable)
		guard !(currentUsable && currentPixels >= TimelineStyle.headerPreferredHeroPixels) else { return }
		guard (attemptCounts[key] ?? 0) < Self.maxAttempts else { return }

		if inFlight.contains(key) {
			retryRequested.insert(key)	// 等这轮结束再抓一次(见字段说明里的竞态)
			return
		}

		let candidates = candidateURLs(for: feed)
		guard !candidates.isEmpty else {
			attemptCounts[key, default: 0] += 1
			return
		}

		inFlight.insert(key)
		attemptCounts[key, default: 0] += 1	// 成功失败都计数,保证一定会终止

		Task { [weak self] in
			guard let self else { return }

			// ⚠️ 不是「第一个达标的就用」,而是**挑最大的那张**(2026-07-22 用户反馈"太糊"后改)。
			// 原因:候选里常常前面的小、后面的大 —— 比如 WordPress 的 iconURL 给的是
			// 32×32 缩略图,而把尺寸后缀去掉的同一张图有 512×512。先到先得会白白错过大图。
			// 折中:拿到 ≥headerPreferredHeroPixels 的就早停,不必把候选全试一遍。
			var bestImage: UIImage?
			var bestData: Data?
			var bestPixels: CGFloat = 0
			var bestScore: CGFloat = 0
			var bestUsable: Bool = false
			var bestURL: String = ""

			for url in candidates {
				do {
					let response = try await Downloader.shared.download(url)
					guard let data = response.data, !data.isEmpty,
						  let image = UIImage(data: data) else {
						continue
					}
					// UIImage(data:) 的 scale 是 1,size 就是像素数
					let longSide: CGFloat = max(image.size.width, image.size.height)
					let shortSide: CGFloat = max(min(image.size.width, image.size.height), 1)
					let aspect: CGFloat = longSide / shortSide

					// ⚠️ 打分**不能只比大小**,要同时看两件事(2026-07-22 两次踩坑后的版本):
					//
					// ① 非方图打折:og:image 有时是 1200×630 的文章横幅(还会随最新文章变),
					//    那不是这个源的"身份图"。封面 / 头像 / logo 几乎都是方的。
					// ② **这张图当头图能不能用**:Six Colors 的 og:image 有 1910px,
					//    但它是**白底**的(非白像素仅 18%),铺满全宽就是一片白 ——
					//    结果它顶掉了那张 256px、非白像素 39% 的正经 logo,
					//    头图先闪了一下正确的图、又被换成近白的纯色渐变,视觉上等于消失。
					//    所以「能用」是**分类优先**:能用的再小也赢不能用的。
					let isSquarish: Bool = aspect <= TimelineStyle.headerMaxHeroAspect
					let usable: Bool = Self.isUsableAsHero(image)
					let score: CGFloat = Self.heroScore(pixels: longSide, squarish: isSquarish, usable: usable)

					if score > bestScore {
						bestScore = score
						bestPixels = longSide
						bestUsable = usable
						bestImage = image
						bestData = data
						bestURL = url.absoluteString
					}
					if usable, isSquarish, longSide >= TimelineStyle.headerPreferredHeroPixels {
						break	// 又大又方又能用,不用再试剩下的候选
					}
				} catch {
					continue	// 单个候选失败很正常(404 等),静静试下一个
				}
			}

			self.inFlight.remove(key)

			// 只有「够大」且「综合分数比手里那张高」才替换。
			// 分数含可用性 —— 所以一张又大又白的 og 图不会顶掉小而合格的 logo。
			if let image = bestImage, let data = bestData,
			   bestPixels >= TimelineStyle.headerMinHeroPixels, bestScore > currentScore {
				try? data.write(to: self.diskURL(for: key))
				self.memoryCache[key] = image
				let better: String = currentPixels > 0 ? "(替换掉原来的 \(Int(currentPixels))px)" : ""
				_ = bestUsable
				Self.logger.info("[头图] 源「\(feed.nameForDisplay, privacy: .public)」选中 \(Int(bestPixels))px\(better, privacy: .public),\(candidates.count) 个候选里最大:\(bestURL, privacy: .public)")
				onSuccess(image)
			} else {
				let attempts = self.attemptCounts[key] ?? 0
				Self.logger.info("[头图] 源「\(feed.nameForDisplay, privacy: .public)」\(candidates.count) 个候选最大才 \(Int(bestPixels))px,没有更好的(第 \(attempts)/\(Self.maxAttempts) 次)")
			}

			// 这轮进行期间有新信息到货(多半是网页元数据)→ 立刻用新的候选再抓一次。
			// 上面的两道 guard(够好了 / 次数用尽)会让它自然停下。
			if self.retryRequested.remove(key) != nil {
				Self.logger.info("[头图] 源「\(feed.nameForDisplay, privacy: .public)」抓取期间有新信息到货,再抓一次")
				self.fetchHeroIfNeeded(for: feed, onSuccess: onSuccess)
			}
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

		// 5. **主页的 og:image**,放在最后 —— 它常常是这里面最大的一张。
		//    2026-07-22 实测:播客(fireside)的 og:image 就是 1400×1400 的封面本身,
		//    YouTube 频道页的 og:image 就是 900×900 的频道头像。
		//    而这三类源(硅谷101 / Marques Brownlee / Links TV)的 iconURL、faviconURL
		//    **全是空的**,不走这条路就只能退回纯色渐变。
		//    元数据是上游已经缓存在本地的,**不产生任何额外网络请求**。
		//    ⚠️ 放最后 + 上面「≥headerPreferredHeroPixels 就早停」的规则合起来 =
		//    图标够大时根本轮不到 og:image,不会打扰本来就正常的源。
		if let homePage = feed.homePageURL,
		   let metadata = HTMLMetadataDownloader.shared.cachedMetadata(for: homePage) {
			for image in metadata.openGraphImages {
				append(image.secureURL ?? image.url)
			}
		}

		return result
	}

	/// 这张图当整片头图能不能用:非白像素占比够不够(白底 logo 铺满全宽就是一片白)。
	/// 判据和 TimelineFeedHeader 里那条**是同一个**,所以"抓来的图"和"用不用得上"口径一致。
	static func isUsableAsHero(_ image: UIImage) -> Bool {
		guard let analysis = FeedIconColorAnalyzer.analyze(image) else { return false }
		return analysis.coverage >= TimelineStyle.headerMinCoverage
	}

	/// 候选图的综合分数:像素数 × 方图系数 × 可用系数。
	/// 可用系数取 0.05 是**有意压得很狠** —— 让"能用"近乎分类优先:
	/// 一张 1910px 但不能用的图得分 95,输给一张 256px 能用的图。
	static func heroScore(pixels: CGFloat, squarish: Bool, usable: Bool) -> CGFloat {
		pixels * (squarish ? 1.0 : 0.3) * (usable ? 1.0 : 0.05)
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
