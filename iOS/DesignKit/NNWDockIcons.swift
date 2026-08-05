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

	// MARK: - 首页那一批(2026-08-04 用户要求:这一页的控件全部重绘 + 橙色)

	/// 搜索:圆 + 手柄
	static func search() -> UIImage {
		draw { ctx, r in
			let c = CGPoint(x: r.midX - 1, y: r.midY - 1)
			ctx.addArc(center: c, radius: 6.8, startAngle: 0, endAngle: .pi * 2, clockwise: false)
			ctx.strokePath()
			ctx.move(to: CGPoint(x: c.x + 4.9, y: c.y + 4.9))
			ctx.addLine(to: CGPoint(x: c.x + 9.4, y: c.y + 9.4))
			ctx.strokePath()
		}
	}

	/// 编辑订阅:方框 + 从右上角伸出的铅笔(沿用用户 2026-07-28 拍板的样子)
	static func edit() -> UIImage {
		draw { ctx, r in
			let c = CGPoint(x: r.midX, y: r.midY)
			// 方框缺右上角一块,给铅笔让位
			ctx.move(to: CGPoint(x: c.x + 2.5, y: c.y - 8))
			ctx.addLine(to: CGPoint(x: c.x - 5, y: c.y - 8))
			ctx.addArc(tangent1End: CGPoint(x: c.x - 8.5, y: c.y - 8),
					   tangent2End: CGPoint(x: c.x - 8.5, y: c.y - 4.5), radius: 3.5)
			ctx.addLine(to: CGPoint(x: c.x - 8.5, y: c.y + 5))
			ctx.addArc(tangent1End: CGPoint(x: c.x - 8.5, y: c.y + 8.5),
					   tangent2End: CGPoint(x: c.x - 5, y: c.y + 8.5), radius: 3.5)
			ctx.addLine(to: CGPoint(x: c.x + 5, y: c.y + 8.5))
			ctx.addArc(tangent1End: CGPoint(x: c.x + 8.5, y: c.y + 8.5),
					   tangent2End: CGPoint(x: c.x + 8.5, y: c.y + 5), radius: 3.5)
			ctx.addLine(to: CGPoint(x: c.x + 8.5, y: c.y - 2.5))
			ctx.strokePath()
			// 铅笔:一根斜杆 + 笔尖
			ctx.move(to: CGPoint(x: c.x + 1.5, y: c.y - 1.5))
			ctx.addLine(to: CGPoint(x: c.x + 8.2, y: c.y - 8.2))
			ctx.strokePath()
			ctx.move(to: CGPoint(x: c.x + 4.6, y: c.y - 4.6))
			ctx.addLine(to: CGPoint(x: c.x + 7.4, y: c.y - 1.8))
			ctx.strokePath()
		}
	}

	/// 设置:齿轮(环 + 8 颗圆头齿)
	static func gear() -> UIImage {
		draw { ctx, r in
			let c = CGPoint(x: r.midX, y: r.midY)
			// 齿轮的关键是**齿要粗且短** —— 细长的齿会读成太阳光芒(第一版就画成了太阳)
			ctx.addArc(center: c, radius: 5.6, startAngle: 0, endAngle: .pi * 2, clockwise: false)
			ctx.strokePath()
			ctx.setLineWidth(3.4)
			for i in 0..<8 {
				let a = CGFloat(i) * .pi / 4
				ctx.move(to: CGPoint(x: c.x + cos(a) * 7.2, y: c.y + sin(a) * 7.2))
				ctx.addLine(to: CGPoint(x: c.x + cos(a) * 8.9, y: c.y + sin(a) * 8.9))
			}
			ctx.strokePath()
			ctx.setLineWidth(lineWidth)
		}
	}

	/// 添加订阅:加号
	static func plus() -> UIImage {
		draw { ctx, r in
			let c = CGPoint(x: r.midX, y: r.midY)
			ctx.move(to: CGPoint(x: c.x - 8, y: c.y)); ctx.addLine(to: CGPoint(x: c.x + 8, y: c.y))
			ctx.move(to: CGPoint(x: c.x, y: c.y - 8)); ctx.addLine(to: CGPoint(x: c.x, y: c.y + 8))
			ctx.strokePath()
		}
	}

	/// 展开 / 折叠的三角(向下 = 展开)
	static func chevron(expanded: Bool) -> UIImage {
		draw { ctx, r in
			let c = CGPoint(x: r.midX, y: r.midY)
			if expanded {
				ctx.move(to: CGPoint(x: c.x - 5.5, y: c.y - 2.6))
				ctx.addLine(to: CGPoint(x: c.x, y: c.y + 2.8))
				ctx.addLine(to: CGPoint(x: c.x + 5.5, y: c.y - 2.6))
			} else {
				ctx.move(to: CGPoint(x: c.x - 2.6, y: c.y - 5.5))
				ctx.addLine(to: CGPoint(x: c.x + 2.8, y: c.y))
				ctx.addLine(to: CGPoint(x: c.x - 2.6, y: c.y + 5.5))
			}
			ctx.strokePath()
		}
	}

	/// 文件夹
	/// 文件夹。**2026-08-05 按用户提供的参考图重画**(上一版是折线拼的,转角全是尖的,
	/// 和这套 dock 图标"粗线 + 圆头"的语言对不上,用户的评价是"和上一次区别不大")。
	///
	/// 形状要点(比例取自参考图 512px 原图,已归一到 24pt 画布):
	/// - 机身几乎占满画布,**宽高比约 1 : 0.83**(不是正方形,矮一点才像文件夹)
	/// - 左上是**抬高的页签**,占宽度约 1/3;从页签右端**斜下**到机身上缘,
	///   斜边两端各有一个**小圆角**(参考图那两处是圆的,不是尖角)——这是最像不像的地方
	/// - 四角大圆角 2.4,斜边两端小圆角 1.2
	///
	/// ⚠️ 输出是**模板图**(`draw` 帮手负责),所以颜色由宿主的 tintColor 决定 ——
	/// 用户要求"能够随主题色变色",靠的就是这一点:装配点设 `NNWSoftMaterial.accent`。
	/// **别改成烘焙好颜色的位图**,那样就跟不了主题色了。
	static func folder() -> UIImage {
		draw { ctx, r in
			// [外观] 2026-08-05 二版:整体**收小到八成**(用户:「再小一些,显得高级一点」)。
			// 一起把线宽从整套的 2.1 收到 1.9 —— 图形缩小而线宽不变的话,
			// 笔画占比会相对变粗,反而更"壮"、不是要的那个轻。
			ctx.setLineWidth(1.9)
			let left = r.minX + 4.4, right = r.maxX - 4.4
			let top = r.minY + 6.0					// 页签上缘
			let shoulder = r.minY + 8.6				// 机身上缘(比页签低)
			let bottom = r.maxY - 5.2
			let tabRight = left + (right - left) * 0.34		// 页签右端
			let notchRight = left + (right - left) * 0.52	// 斜边落到机身上缘的位置
			let big: CGFloat = 2.0, small: CGFloat = 1.0	// 缩小后圆角同比收

			ctx.move(to: CGPoint(x: left, y: (top + bottom) / 2))
			ctx.addArc(tangent1End: CGPoint(x: left, y: top),
					   tangent2End: CGPoint(x: tabRight, y: top), radius: big)
			ctx.addArc(tangent1End: CGPoint(x: tabRight, y: top),
					   tangent2End: CGPoint(x: notchRight, y: shoulder), radius: small)
			ctx.addArc(tangent1End: CGPoint(x: notchRight, y: shoulder),
					   tangent2End: CGPoint(x: right, y: shoulder), radius: small)
			ctx.addArc(tangent1End: CGPoint(x: right, y: shoulder),
					   tangent2End: CGPoint(x: right, y: bottom), radius: big)
			ctx.addArc(tangent1End: CGPoint(x: right, y: bottom),
					   tangent2End: CGPoint(x: left, y: bottom), radius: big)
			ctx.addArc(tangent1End: CGPoint(x: left, y: bottom),
					   tangent2End: CGPoint(x: left, y: top), radius: big)
			ctx.closePath()
			ctx.strokePath()
		}
	}
}

#endif
