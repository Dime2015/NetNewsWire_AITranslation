//
//  NNWTranslateIcon.swift
//  NetNewsWire — AI 翻译 fork
//
//  [翻译] 本 fork 新增,上游没有这个文件。
//
//  翻译按钮的图标。多轮选型后 2026-07-30 定案(设计稿用户已确认,别推倒重来):
//  - 图标本体:系统 SF「translate」符号(A/文 双气泡),14.5pt(宽字形,和邻居的
//    17pt 视觉等大 —— 用户三轮微调出来的数)
//  - 状态由**右下角的小角标**表达,图标本体四态不变:
//      未翻译       → 纯图标
//      已翻译       → 小勾
//      有完整缓存   → 实心小圆
//      有未完成缓存 → 空心小圆
//  - 角标外圈是一层**挖出来的透明晕圈**(destinationOut):把被压住的气泡描边断开,
//    小尺寸下角标才认得出;因为是真透明,摆在毛玻璃/任何底色上都成立
//  - 整体输出为模板图:勾/圆点和图标同色,跟随 tintColor 与深浅色
//
//  历史方案(都被用户否掉,记档防走回头路):单气泡「字」→ 自绘双气泡 →
//  实心方块+镂空字形(已翻译态)→ 淡色底衬(已翻译态)。
//

#if os(iOS)

import UIKit

@MainActor enum NNWTranslateIcon {

	/// 和按钮的 preferredSymbolConfiguration 同一份字号 —— 纯符号态(未翻译/失败)
	/// 靠按钮的配置缩放,合成态在这里烘焙,两边必须一个数,图标才不会状态间跳大小。
	static let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14.5, weight: .medium)

	/// 未翻译:纯 translate 符号(万一系统没有这个名字就退回单气泡,不崩)
	static let outline: UIImage = baseSymbol

	/// 已翻译:右下角小勾
	static let withCheck: UIImage = compose(badge: .check)

	/// 有完整缓存:右下角实心小圆
	static let withSolidDot: UIImage = compose(badge: .solidDot)

	/// 有未完成缓存:右下角空心小圆
	static let withHollowDot: UIImage = compose(badge: .hollowDot)

	// MARK: - 合成

	private enum Badge {
		case check, solidDot, hollowDot
	}

	private static var baseSymbol: UIImage {
		UIImage(systemName: "translate", withConfiguration: symbolConfiguration)
			?? UIImage(systemName: "character.bubble", withConfiguration: symbolConfiguration)!
	}

	private static func compose(badge: Badge) -> UIImage {

		// 拿黑色实体版来画(符号默认是模板,直接 draw 拿不到笔画)
		let icon = baseSymbol.withTintColor(.black, renderingMode: .alwaysOriginal)

		// 画布四周对称留白:角标的晕圈会探出图标右下角 ~3.7pt,留 4.5pt 装得下;
		// **对称**留白是为了图标在按钮里仍然居中,四个状态的图标位置一个像素不差
		let pad: CGFloat = 4.5
		let size = CGSize(width: icon.size.width + pad * 2,
						  height: icon.size.height + pad * 2)

		let renderer = UIGraphicsImageRenderer(size: size)
		let image = renderer.image { rendererContext in
			let context = rendererContext.cgContext

			icon.draw(at: CGPoint(x: pad, y: pad))

			// 角标中心:压着图标右下角、往里收 1.5pt(设计稿定的位置)
			let center = CGPoint(x: pad + icon.size.width - 1.5,
								 y: pad + icon.size.height - 1.5)

			// 晕圈:把角标脚下的笔画挖掉(真透明,任何背景上都成立)
			context.setBlendMode(.destinationOut)
			context.fillEllipse(in: CGRect(x: center.x - 5.2, y: center.y - 5.2,
										   width: 10.4, height: 10.4))
			context.setBlendMode(.normal)

			UIColor.black.setStroke()
			UIColor.black.setFill()
			switch badge {
			case .check:
				// 勾比圆点略大(笔画细,同尺寸显小)—— 设计稿 ③ 的要点
				let path = UIBezierPath()
				path.move(to: CGPoint(x: center.x - 3, y: center.y + 0.2))
				path.addLine(to: CGPoint(x: center.x - 0.8, y: center.y + 2.4))
				path.addLine(to: CGPoint(x: center.x + 3.4, y: center.y - 2.6))
				path.lineWidth = 2
				path.lineCapStyle = .round
				path.lineJoinStyle = .round
				path.stroke()
			case .solidDot:
				context.fillEllipse(in: CGRect(x: center.x - 3.1, y: center.y - 3.1,
											   width: 6.2, height: 6.2))
			case .hollowDot:
				let ring = UIBezierPath(ovalIn: CGRect(x: center.x - 2.3, y: center.y - 2.3,
													   width: 4.6, height: 4.6))
				ring.lineWidth = 1.6
				ring.stroke()
			}
		}
		return image.withRenderingMode(.alwaysTemplate)
	}
}

#endif
