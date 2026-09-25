//
//  ArticleLongImageExporter.swift
//  NetNewsWire — AI 翻译 fork
//
//  [长图] 把当前文章页导出成一张滚动式长图(T22,2026-07-24)。本 fork 新增,上游没有。
//
//  ## 管线(为什么天然"所见即所得")
//
//  1. 网页侧准备(nnw_snapshot.js):露出被阅读栏藏掉的标题区 + 强制加载全部图片
//  2. `WKWebView.pdf()`:把**整页内容**导出成 PDF —— 截的是当前活着的 DOM,
//     是否翻译、是否阅读模式、深浅色,全都是"现在屏幕上那个样子"
//  3. PDF 逐页栅格化,竖着拼成一张长图(先铺纸色底 —— WebView 是透明的,L60 那套改造)
//  4. 画签名:app 图标 + 「分享自 <品牌名>」(品牌名走 NNWBrand,不写死)。
//     默认在末尾;Babel 2.0 阅读页选择放在顶部并换新图标(见 Signature)
//  5. 网页侧复位(finish),页面回到截图前一模一样
//
//  ## 两个上限(都是内存/兼容性的现实约束)
//
//  - 高度上限约 2.5 万像素:超长文章整体降分辨率,而不是截断 —— 内容完整性优先
//  - 宽度 2 倍点数封顶:分享场景够清晰,内存占用可控
//

#if os(iOS)

import UIKit
import WebKit

@MainActor enum ArticleLongImageExporter {

	enum ExportError: LocalizedError {
		case pageNotReady
		case pdfFailed
		case renderFailed

		var errorDescription: String? {
			switch self {
			case .pageNotReady: return "页面还没准备好,请等文章加载完再试。"
			case .pdfFailed: return "没能截取文章内容,请稍后再试。"
			case .renderFailed: return "生成图片失败,文章可能过长。"
			}
		}
	}

	/// 长图最大像素高(超了整体降分辨率)。再大会撞内存和微信等平台的接收上限。
	private static let maxPixelHeight: CGFloat = 25000
	/// 内容渲染的目标倍率(相对 PDF 的点数)
	private static let targetScale: CGFloat = 2

	/// 「分享自 <品牌名>」签名画在哪、用哪个图标。
	/// 默认 = 旧版:画在长图末尾、用 ShareFooterIcon(1.x 两处阅读页不传,行为不变)。
	/// [Babel2] 2026-09-25:Babel 2.0 阅读页传「顶部 + 新图标」。
	struct Signature {
		var atTop: Bool = false
		/// nil = 用旧资源 ShareFooterIcon
		var icon: UIImage? = nil
	}

	/// 生成长图(一张;超长时整体降分辨率)。**成功失败都会把网页复位**(finish 在 defer 里)。
	// [翻译] 试读 Phase C(2026-07-30):入参从 WebViewController 放宽成 NNWArticlePageHost 协议
	static func export(from webViewController: any NNWArticlePageHost, signature: Signature = Signature()) async throws -> UIImage {
		let pdfData = try await capturePDF(from: webViewController)

		// ④ 栅格化拼接 + 页脚
		guard let image = renderLongImage(from: pdfData,
										  traits: webViewController.traitCollection,
										  signature: signature) else {
			throw ExportError.renderFailed
		}
		return image
	}

	/// [Babel2] 2026-09-25:生成长图,**超长时拆成几张**,每张都保持 2 倍清晰度(ADR-026)。
	/// 短文章仍是 1 张。签名只画一次:顶部模式在第 1 张最上面,底部模式在最后一张末尾。
	/// 每张画完立刻压成 PNG 数据再画下一张 —— 6 张全清晰度位图同时放在内存里约 400 MB,
	/// 手机会直接把 app 杀掉;压缩后的 UIImage 只在真正显示/保存时才解码。
	static func exportImages(from webViewController: any NNWArticlePageHost, signature: Signature = Signature()) async throws -> [UIImage] {
		let pdfData = try await capturePDF(from: webViewController)
		guard let images = renderLongImages(from: pdfData,
											traits: webViewController.traitCollection,
											signature: signature),
			  !images.isEmpty else {
			throw ExportError.renderFailed
		}
		return images
	}

	/// ①–③:网页侧准备 → 等图片 → 整页导出 PDF。返回前把网页复位。
	private static func capturePDF(from webViewController: any NNWArticlePageHost) async throws -> Data {

		guard let webView = webViewController.nnwHostWebView else {
			throw ExportError.pageNotReady
		}

		// ① 网页侧准备:露出标题区、强制加载图片
		guard (try? await webViewController.nnwSnapshotPrepare()) == true else {
			throw ExportError.pageNotReady
		}
		defer {
			// 复位不能省:标题区露出来的状态和阅读栏是叠着的,留着就是"双标题"
			Task { _ = try? await webViewController.nnwSnapshotFinish() }
		}

		// ② 等图片到齐(带超时:一张挂掉的图不该吊死整个导出)
		let imageDeadline = Date().addingTimeInterval(5)
		while Date() < imageDeadline {
			let pending = (try? await webViewController.nnwSnapshotPendingImageCount()) ?? 0
			if pending == 0 { break }
			try await Task.sleep(for: .milliseconds(250))
		}
		// 布局沉降一拍(图片装进来后行高会变)
		try await Task.sleep(for: .milliseconds(350))

		// ③ 整页导出 PDF
		do {
			return try await webView.pdf(configuration: WKPDFConfiguration())
		} catch {
			throw ExportError.pdfFailed
		}
	}

	// MARK: - PDF → 长图

	/// 签名条高度(点)
	private static let footerHeight: CGFloat = 76

	private static func renderLongImage(from pdfData: Data, traits: UITraitCollection, signature: Signature) -> UIImage? {

		guard let provider = CGDataProvider(data: pdfData as CFData),
			  let document = CGPDFDocument(provider), document.numberOfPages >= 1 else {
			return nil
		}

		// 量总尺寸(逐页;WKWebView 通常给一整页,但别赌 —— 有几页拼几页)
		var pageSizes: [CGSize] = []
		var totalHeight: CGFloat = 0
		var maxWidth: CGFloat = 0
		for index in 1...document.numberOfPages {
			guard let page = document.page(at: index) else { continue }
			let box = page.getBoxRect(.mediaBox)
			pageSizes.append(box.size)
			totalHeight += box.height
			maxWidth = max(maxWidth, box.width)
		}
		guard totalHeight > 0, maxWidth > 0 else { return nil }

		// 倍率:目标 2x,超高就整体压到上限内(内容完整性优先于清晰度)
		var scale = targetScale
		if (totalHeight + footerHeight) * scale > maxPixelHeight {
			scale = maxPixelHeight / (totalHeight + footerHeight)
		}

		let canvasSize = CGSize(width: maxWidth * scale,
								height: (totalHeight + footerHeight) * scale)

		// 纸色底:WebView 自己是透明的(纸色由 UIKit 铺,L60 那套),PDF 里没有底色。
		// 按**当前深浅色**解析 —— "和屏幕一模一样"包括底色。
		let paper = AppAppearance.paperBackground.resolvedColor(with: traits)

		let format = UIGraphicsImageRendererFormat()
		format.scale = 1		// 尺寸就是像素,不再叠设备倍率(否则 3x 设备直接内存翻三倍)
		format.opaque = true

		let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
		return renderer.image { context in
			let cg = context.cgContext

			paper.setFill()
			cg.fill(CGRect(origin: .zero, size: canvasSize))

			// 签名在顶部时,正文整体往下让出签名条的高度
			let contentTop: CGFloat = signature.atTop ? footerHeight * scale : 0

			// 逐页画。PDF 坐标系原点在左下,要翻转
			var offsetY: CGFloat = contentTop
			for index in 1...document.numberOfPages {
				guard let page = document.page(at: index) else { continue }
				let box = page.getBoxRect(.mediaBox)
				cg.saveGState()
				// [Babel2] 2026-09-25:只许画在这一页自己的格子里。网页导出的每页 PDF 都自带
				// 一块远大于本页的背景色,不限定的话后画的页会把前面已画好的页整片盖掉——
				// 超过 14400 点被分成多页的长文章,长图就只剩最后一页(实测一整张底色)
				cg.clip(to: CGRect(x: 0, y: offsetY, width: canvasSize.width, height: box.height * scale))
				cg.translateBy(x: 0, y: offsetY + box.height * scale)
				cg.scaleBy(x: scale, y: -scale)
				cg.translateBy(x: -box.origin.x, y: -box.origin.y)
				cg.drawPDFPage(page)
				cg.restoreGState()
				offsetY += box.height * scale
			}

			// 底部:签名条在正文之后,细线画在签名条上边;顶部:签名条在最上面,细线画在它下边
			let footerTop = signature.atTop ? 0 : offsetY
			drawSignature(in: cg, bandTop: footerTop, lineAtBandBottom: signature.atTop,
						  canvasWidth: canvasSize.width, scale: scale, signature: signature, traits: traits)
		}
	}

	/// 超长文章拆成几张(ADR-026)。
	/// - 每张最高 maxPixelHeight 像素,倍率保持 2x;最多 maxImageCount 张,再长才整体降分辨率
	/// - 尽量切在两行字之间的空白处(见 findCut),不把一行字劈成两半
	private static let maxImageCount = 10

	private static func renderLongImages(from pdfData: Data, traits: UITraitCollection, signature: Signature) -> [UIImage]? {

		guard let provider = CGDataProvider(data: pdfData as CFData),
			  let document = CGPDFDocument(provider), document.numberOfPages >= 1 else {
			return nil
		}

		// 各页在整篇里的上下位置(点)
		var pages: [(page: CGPDFPage, top: CGFloat, box: CGRect)] = []
		var totalHeight: CGFloat = 0
		var maxWidth: CGFloat = 0
		for index in 1...document.numberOfPages {
			guard let page = document.page(at: index) else { continue }
			let box = page.getBoxRect(.mediaBox)
			pages.append((page, totalHeight, box))
			totalHeight += box.height
			maxWidth = max(maxWidth, box.width)
		}
		guard totalHeight > 0, maxWidth > 0 else { return nil }

		// 倍率:目标 2x;连 maxImageCount 张都装不下时才整体降
		var scale = targetScale
		let budget = CGFloat(maxImageCount) * maxPixelHeight
		if (totalHeight + footerHeight) * scale > budget {
			scale = budget / (totalHeight + footerHeight)
		}
		let capacity = maxPixelHeight / scale		// 每张能装多少点(含签名条)

		// 切分:[起点, 终点) 的列表
		var ranges: [(start: CGFloat, end: CGFloat)] = []
		var start: CGFloat = 0
		while start < totalHeight {
			let isFirst = ranges.isEmpty
			// 签名条占的地方要扣掉(顶部模式在第 1 张;底部模式保守地每张都扣,最后一张才真画)
			let room = capacity - ((signature.atTop && !isFirst) ? 0 : footerHeight)
			if start + room >= totalHeight {
				ranges.append((start, totalHeight))
				break
			}
			let cut = findCut(near: start + room, notBefore: start + room / 2, pages: pages, width: maxWidth)
			ranges.append((start, cut))
			start = cut
		}

		let paper = AppAppearance.paperBackground.resolvedColor(with: traits)
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		format.opaque = true

		var images: [UIImage] = []
		for (index, range) in ranges.enumerated() {
			let hasBand = signature.atTop ? index == 0 : index == ranges.count - 1
			let contentTop: CGFloat = (hasBand && signature.atTop) ? footerHeight * scale : 0
			let contentHeight = (range.end - range.start) * scale
			let canvasSize = CGSize(width: maxWidth * scale,
									height: contentHeight + (hasBand ? footerHeight * scale : 0))

			let encoded: Data? = autoreleasepool {
				let image = UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
					let cg = context.cgContext
					paper.setFill()
					cg.fill(CGRect(origin: .zero, size: canvasSize))
					drawContent(pages, from: range.start, to: range.end, scale: scale, top: contentTop, width: canvasSize.width, in: cg)
					if hasBand {
						let bandTop = signature.atTop ? 0 : contentTop + contentHeight
						drawSignature(in: cg, bandTop: bandTop, lineAtBandBottom: signature.atTop,
									  canvasWidth: canvasSize.width, scale: scale, signature: signature, traits: traits)
					}
				}
				return image.pngData()
			}
			guard let encoded, let compressed = UIImage(data: encoded) else { return nil }
			images.append(compressed)
		}
		return images
	}

	/// 把整篇 [from, to) 这一段(点)画到画布上 top 处。每页都限定在自己的格子和这一段之内。
	private static func drawContent(_ pages: [(page: CGPDFPage, top: CGFloat, box: CGRect)],
									from: CGFloat, to: CGFloat, scale: CGFloat, top: CGFloat, width: CGFloat,
									in cg: CGContext) {
		for item in pages where item.top < to && item.top + item.box.height > from {
			let pageY = top + (item.top - from) * scale
			let pageRect = CGRect(x: 0, y: pageY, width: width, height: item.box.height * scale)
			let segmentRect = CGRect(x: 0, y: top, width: width, height: (to - from) * scale)
			cg.saveGState()
			cg.clip(to: pageRect.intersection(segmentRect))
			cg.translateBy(x: 0, y: pageY + item.box.height * scale)
			cg.scaleBy(x: scale, y: -scale)
			cg.translateBy(x: -item.box.origin.x, y: -item.box.origin.y)
			cg.drawPDFPage(item.page)
			cg.restoreGState()
		}
	}

	/// 在 target 往上 400 点的范围里,找最靠下的一整行「全是同一个颜色」的位置(两行字之间的空隙)。
	/// 找不到(比如正好是一张大图)就直接在 target 处切。只读取像素,不改任何内容。
	private static func findCut(near target: CGFloat, notBefore floor: CGFloat,
								pages: [(page: CGPDFPage, top: CGFloat, box: CGRect)], width: CGFloat) -> CGFloat {
		let bandStart = max(floor, target - 400)
		let bandHeight = Int(target - bandStart)
		let pixelWidth = Int(width)
		guard bandHeight > 1, pixelWidth > 0,
			  let cg = CGContext(data: nil, width: pixelWidth, height: bandHeight, bitsPerComponent: 8, bytesPerRow: pixelWidth * 4,
								 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
			return target
		}
		// 翻成「原点在左上」,和上面画长图同一套坐标
		cg.translateBy(x: 0, y: CGFloat(bandHeight))
		cg.scaleBy(x: 1, y: -1)
		drawContent(pages, from: bandStart, to: target, scale: 1, top: 0, width: CGFloat(pixelWidth), in: cg)
		guard let data = cg.data?.assumingMemoryBound(to: UInt8.self) else { return target }

		// 内存里第 0 行是位图最上面一行(已翻转坐标)。从下往上找
		for row in stride(from: bandHeight - 1, through: 0, by: -1) {
			let base = row * pixelWidth * 4
			var uniform = true
			for x in 1..<pixelWidth {
				let offset = base + x * 4
				if abs(Int(data[offset]) - Int(data[base])) > 2
					|| abs(Int(data[offset + 1]) - Int(data[base + 1])) > 2
					|| abs(Int(data[offset + 2]) - Int(data[base + 2])) > 2 {
					uniform = false
					break
				}
			}
			if uniform { return bandStart + CGFloat(row) }
		}
		return target
	}

	/// 签名条:细线 + 圆角图标 + 「分享自 <品牌名>」。
	/// lineAtBandBottom = true:细线画在签名条下边(签名在顶部);否则画在上边(签名在末尾)。
	private static func drawSignature(in cg: CGContext, bandTop: CGFloat, lineAtBandBottom: Bool,
									  canvasWidth: CGFloat, scale: CGFloat, signature: Signature, traits: UITraitCollection) {
		let inkSecondary = UIColor.secondaryLabel.resolvedColor(with: traits)
		let hairline = UIColor.separator.resolvedColor(with: traits)

		let lineHeight = max(1, 0.5 * scale)
		let lineY = lineAtBandBottom ? bandTop + footerHeight * scale - lineHeight : bandTop
		hairline.setFill()
		cg.fill(CGRect(x: 24 * scale, y: lineY,
					   width: canvasWidth - 48 * scale, height: lineHeight))

		let iconSide = 40 * scale
		let footerCenterY = bandTop + footerHeight * scale / 2

		let brandText = "分享自 \(NNWBrand.displayName)" as NSString
		let font = UIFont.systemFont(ofSize: 15 * scale, weight: .medium)
		let textSize = brandText.size(withAttributes: [.font: font])

		let blockWidth = iconSide + 10 * scale + textSize.width
		let iconX = (canvasWidth - blockWidth) / 2
		let iconRect = CGRect(x: iconX, y: footerCenterY - iconSide / 2,
							  width: iconSide, height: iconSide)

		if let icon = signature.icon ?? UIImage(named: "ShareFooterIcon") {
			let path = UIBezierPath(roundedRect: iconRect, cornerRadius: iconSide * 0.22)
			cg.saveGState()
			path.addClip()
			icon.draw(in: iconRect)
			cg.restoreGState()
		}

		brandText.draw(at: CGPoint(x: iconRect.maxX + 10 * scale,
								   y: footerCenterY - textSize.height / 2),
					   withAttributes: [.font: font, .foregroundColor: inkSecondary])
	}
}

#endif
