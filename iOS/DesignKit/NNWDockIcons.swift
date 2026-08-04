//
//  NNWDockIcons.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增。dock 上 7 个键的**手绘图标**。
//
//  ## 为什么不用 SF Symbols
//
//  参考图那套语言的图标是「粗线 + 圆头 + 几何简化」,笔画比 SF Symbols 明显更粗、
//  转角更圆、细节更少。系统符号混在里面一眼就散(用户 2026-08-04 的原话:
//  "控件也没重绘")。这里按同一套参数自绘,7 个键长在一起。
//
//  ## 统一参数(改这里就整套变)
//
//  - 画布 24×24pt,笔画 2.1pt,圆头圆角
//  - 全部输出为**模板图**,颜色由按钮的 tintColor 决定(未选中墨色、选中橙)
//  - "点亮"状态用**实心**版本,不是换颜色 —— 参考图里选中的房子就是实心橙
//

#if os(iOS)

import UIKit

@MainActor enum NNWDockIcons {

	/// 图标画布边长与笔画宽度。整套统一,别单独改某一个。
	static let canvas: CGFloat = 24
	static let lineWidth: CGFloat = 2.1

	// MARK: - 7 个键

	/// 已读圈:空心 = 已读(点了标未读),实心 = 未读
	static func read(isRead: Bool) -> UIImage {
		draw { ctx, r in
			let c = CGPoint(x: r.midX, y: r.midY)
			let radius: CGFloat = 8
			if isRead {
				strokeCircle(ctx, center: c, radius: radius)
			} else {
				ctx.addArc(center: c, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
				ctx.fillPath()
			}
		}
	}

	/// 星标:空心 / 实心
	static func star(filled: Bool) -> UIImage {
		draw { ctx, r in
			starPath(ctx, center: CGPoint(x: r.midX, y: r.midY), outer: 9.4, inner: 4.1)
			filled ? ctx.fillPath() : ctx.strokePath()
		}
	}

	/// 下一篇未读:向下的箭头
	static func nextUnread() -> UIImage {
		draw { ctx, r in
			let c = CGPoint(x: r.midX, y: r.midY)
			ctx.move(to: CGPoint(x: c.x, y: c.y - 8.5))
			ctx.addLine(to: CGPoint(x: c.x, y: c.y + 7.5))
			ctx.move(to: CGPoint(x: c.x - 6, y: c.y + 1.5))
			ctx.addLine(to: CGPoint(x: c.x, y: c.y + 7.5))
			ctx.addLine(to: CGPoint(x: c.x + 6, y: c.y + 1.5))
			ctx.strokePath()
		}
	}

	/// 分享:箭头从盒子里出来
	static func share() -> UIImage {
		draw { ctx, r in
			let c = CGPoint(x: r.midX, y: r.midY)
			ctx.move(to: CGPoint(x: c.x, y: c.y + 3.5))
			ctx.addLine(to: CGPoint(x: c.x, y: c.y - 8.5))
			ctx.move(to: CGPoint(x: c.x - 4.6, y: c.y - 4))
			ctx.addLine(to: CGPoint(x: c.x, y: c.y - 8.6))
			ctx.addLine(to: CGPoint(x: c.x + 4.6, y: c.y - 4))
			ctx.move(to: CGPoint(x: c.x - 7, y: c.y - 1.5))
			ctx.addLine(to: CGPoint(x: c.x - 7, y: c.y + 7))
			ctx.addLine(to: CGPoint(x: c.x + 7, y: c.y + 7))
			ctx.addLine(to: CGPoint(x: c.x + 7, y: c.y - 1.5))
			ctx.strokePath()
		}
	}

	/// 长图:一张图 + 山峰
	static func longImage() -> UIImage {
		draw { ctx, r in
			let c = CGPoint(x: r.midX, y: r.midY)
			let box = CGRect(x: c.x - 8.5, y: c.y - 7.5, width: 17, height: 15)
			ctx.addPath(UIBezierPath(roundedRect: box, cornerRadius: 4).cgPath)
			ctx.move(to: CGPoint(x: box.minX + 0.6, y: box.maxY - 3.4))
			ctx.addLine(to: CGPoint(x: c.x - 2.6, y: c.y - 0.6))
			ctx.addLine(to: CGPoint(x: c.x + 0.8, y: c.y + 2.4))
			ctx.addLine(to: CGPoint(x: c.x + 3.6, y: c.y - 0.4))
			ctx.addLine(to: CGPoint(x: box.maxX - 0.6, y: box.maxY - 2.2))
			ctx.strokePath()
		}
	}

	/// 阅读模式:一页文字(三条横线);开启时最下面一条变实心块
	static func readerView(isOn: Bool) -> UIImage {
		draw { ctx, r in
			let c = CGPoint(x: r.midX, y: r.midY)
			ctx.move(to: CGPoint(x: c.x - 8, y: c.y - 6.5)); ctx.addLine(to: CGPoint(x: c.x + 8, y: c.y - 6.5))
			ctx.move(to: CGPoint(x: c.x - 8, y: c.y));       ctx.addLine(to: CGPoint(x: c.x + 8, y: c.y))
			ctx.move(to: CGPoint(x: c.x - 8, y: c.y + 6.5)); ctx.addLine(to: CGPoint(x: c.x + (isOn ? 8 : 2), y: c.y + 6.5))
			ctx.strokePath()
		}
	}

	/// 翻译:两个交叠的对话气泡(左上、右下)
	static func translate(filled: Bool) -> UIImage {
		draw { ctx, r in
			let c = CGPoint(x: r.midX, y: r.midY)
			let a = CGRect(x: c.x - 9.2, y: c.y - 8.6, width: 12.6, height: 9.8)
			let b = CGRect(x: c.x - 3.4, y: c.y - 1.2, width: 12.6, height: 9.8)
			if filled {
				ctx.addPath(UIBezierPath(roundedRect: a, cornerRadius: 3.2).cgPath)
				ctx.fillPath()
				// 后一个气泡先挖一圈底色,再填 —— 两个实心块交叠时要看得出前后
				ctx.saveGState()
				ctx.setBlendMode(.clear)
				ctx.addPath(UIBezierPath(roundedRect: b.insetBy(dx: -1.4, dy: -1.4), cornerRadius: 4.4).cgPath)
				ctx.fillPath()
				ctx.restoreGState()
				ctx.addPath(UIBezierPath(roundedRect: b, cornerRadius: 3.2).cgPath)
				ctx.fillPath()
			} else {
				ctx.addPath(UIBezierPath(roundedRect: a, cornerRadius: 3.2).cgPath)
				ctx.strokePath()
				ctx.saveGState()
				ctx.setBlendMode(.clear)
				ctx.setLineWidth(lineWidth + 2.6)
				ctx.addPath(UIBezierPath(roundedRect: b, cornerRadius: 3.2).cgPath)
				ctx.strokePath()
				ctx.restoreGState()
				ctx.addPath(UIBezierPath(roundedRect: b, cornerRadius: 3.2).cgPath)
				ctx.strokePath()
			}
		}
	}

	// MARK: - 画

	private static func draw(_ body: (CGContext, CGRect) -> Void) -> UIImage {
		let rect = CGRect(x: 0, y: 0, width: canvas, height: canvas)
		let image = UIGraphicsImageRenderer(size: rect.size).image { rendererContext in
			let ctx = rendererContext.cgContext
			ctx.setLineWidth(lineWidth)
			ctx.setLineCap(.round)
			ctx.setLineJoin(.round)
			ctx.setStrokeColor(UIColor.black.cgColor)
			ctx.setFillColor(UIColor.black.cgColor)
			body(ctx, rect)
		}
		return image.withRenderingMode(.alwaysTemplate)
	}

	private static func strokeCircle(_ ctx: CGContext, center: CGPoint, radius: CGFloat) {
		ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
		ctx.strokePath()
	}

	private static func starPath(_ ctx: CGContext, center: CGPoint, outer: CGFloat, inner: CGFloat) {
		for i in 0..<10 {
			let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
			let radius = i % 2 == 0 ? outer : inner
			let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
			if i == 0 { ctx.move(to: point) } else { ctx.addLine(to: point) }
		}
		ctx.closePath()
	}
}

#endif
