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
//  4. 末尾画页脚:app 图标 + 「分享自 <品牌名>」(品牌名走 NNWBrand,不写死)
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

	/// 生成长图。**成功失败都会把网页复位**(finish 在 defer 里)。
	// [翻译] 试读 Phase C(2026-07-30):入参从 WebViewController 放宽成 NNWArticlePageHost 协议
	static func export(from webViewController: any NNWArticlePageHost) async throws -> UIImage {

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
		let pdfData: Data
		do {
			pdfData = try await webView.pdf(configuration: WKPDFConfiguration())
		} catch {
			throw ExportError.pdfFailed
		}

		// ④ 栅格化拼接 + 页脚
		guard let image = renderLongImage(from: pdfData,
										  traits: webViewController.traitCollection) else {
			throw ExportError.renderFailed
		}
		return image
	}

	// MARK: - PDF → 长图

	private static func renderLongImage(from pdfData: Data, traits: UITraitCollection) -> UIImage? {

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
		let footerHeight: CGFloat = 76		// 页脚高度(点)
		if (totalHeight + footerHeight) * scale > maxPixelHeight {
			scale = maxPixelHeight / (totalHeight + footerHeight)
		}

		let canvasSize = CGSize(width: maxWidth * scale,
								height: (totalHeight + footerHeight) * scale)

		// 纸色底:WebView 自己是透明的(纸色由 UIKit 铺,L60 那套),PDF 里没有底色。
		// 按**当前深浅色**解析 —— "和屏幕一模一样"包括底色。
		let paper = AppAppearance.paperBackground.resolvedColor(with: traits)
		let inkSecondary = UIColor.secondaryLabel.resolvedColor(with: traits)
		let hairline = UIColor.separator.resolvedColor(with: traits)

		let format = UIGraphicsImageRendererFormat()
		format.scale = 1		// 尺寸就是像素,不再叠设备倍率(否则 3x 设备直接内存翻三倍)
		format.opaque = true

		let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
		return renderer.image { context in
			let cg = context.cgContext

			paper.setFill()
			cg.fill(CGRect(origin: .zero, size: canvasSize))

			// 逐页画。PDF 坐标系原点在左下,要翻转
			var offsetY: CGFloat = 0
			for index in 1...document.numberOfPages {
				guard let page = document.page(at: index) else { continue }
				let box = page.getBoxRect(.mediaBox)
				cg.saveGState()
				cg.translateBy(x: 0, y: offsetY + box.height * scale)
				cg.scaleBy(x: scale, y: -scale)
				cg.translateBy(x: -box.origin.x, y: -box.origin.y)
				cg.drawPDFPage(page)
				cg.restoreGState()
				offsetY += box.height * scale
			}

			// —— 页脚:细线 + 圆角图标 + 「分享自 <品牌名>」 ——
			let footerTop = offsetY
			hairline.setFill()
			cg.fill(CGRect(x: 24 * scale, y: footerTop,
						   width: canvasSize.width - 48 * scale, height: max(1, 0.5 * scale)))

			let iconSide = 40 * scale
			let footerCenterY = footerTop + footerHeight * scale / 2

			let brandText = "分享自 \(NNWBrand.displayName)" as NSString
			let font = UIFont.systemFont(ofSize: 15 * scale, weight: .medium)
			let textSize = brandText.size(withAttributes: [.font: font])

			let blockWidth = iconSide + 10 * scale + textSize.width
			let iconX = (canvasSize.width - blockWidth) / 2
			let iconRect = CGRect(x: iconX, y: footerCenterY - iconSide / 2,
								  width: iconSide, height: iconSide)

			if let icon = UIImage(named: "ShareFooterIcon") {
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
}

#endif
