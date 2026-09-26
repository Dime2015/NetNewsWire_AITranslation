import UIKit

/// 加载中的占位条（ADR-034）：几行轻轻「呼吸」的灰色条，替代「加载中…」文字。
///
/// - 只在加载超过 0.2 秒时才淡入（快的加载根本看不到它，不闪一下）
/// - 呼吸：透明度在 1 与 0.45 之间缓慢往返；减弱动态效果时静止
/// - 不接收点按；读屏时读作「加载中」
@MainActor
final class Babel2SkeletonView: UIView {
	enum Style {
		/// 首页订阅源行：小方块 + 一条名字
		case feedList
		/// 文章行：小方块 + 标题两条 + 摘要一条
		case articleList
	}

	private static let breathKey = "babel2.skeleton.breath"
	private let content = UIView()
	private(set) var isShowing = false

	init(style: Style, accessibilityText: String) {
		super.init(frame: .zero)
		isUserInteractionEnabled = false
		isAccessibilityElement = true
		accessibilityLabel = accessibilityText
		accessibilityIdentifier = "babel2.skeleton"
		alpha = 0
		isHidden = true
		content.translatesAutoresizingMaskIntoConstraints = false
		addSubview(content)
		NSLayoutConstraint.activate([
			content.leadingAnchor.constraint(equalTo: leadingAnchor),
			content.trailingAnchor.constraint(equalTo: trailingAnchor),
			content.topAnchor.constraint(equalTo: topAnchor),
			content.bottomAnchor.constraint(equalTo: bottomAnchor)
		])
		build(style)
	}

	required init?(coder: NSCoder) { nil }

	/// 显示 / 隐藏。显示有 0.2 秒延迟再淡入；隐藏立即淡出。
	func setShowing(_ showing: Bool) {
		guard showing != isShowing else { return }
		isShowing = showing
		layer.removeAllAnimations()
		if showing {
			isHidden = false
			alpha = 0
			Babel2Motion.animate(Babel2Motion.standard, delay: 0.2, { self.alpha = 1 })
			updateBreathing()
		} else {
			Babel2Motion.animate(Babel2Motion.quick, { self.alpha = 0 }, completion: { [weak self] _ in
				guard let self, !self.isShowing else { return }
				self.isHidden = true
				self.updateBreathing()
			})
		}
	}

	override func didMoveToWindow() {
		super.didMoveToWindow()
		updateBreathing()
	}

	private func updateBreathing() {
		content.layer.removeAnimation(forKey: Self.breathKey)
		guard isShowing, window != nil, !Babel2Motion.reduceMotion else { return }
		let breath = CABasicAnimation(keyPath: "opacity")
		breath.fromValue = 1
		breath.toValue = 0.45
		breath.duration = 0.9
		breath.autoreverses = true
		breath.repeatCount = .infinity
		breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
		content.layer.add(breath, forKey: Self.breathKey)
	}

	// MARK: 版式

	private func build(_ style: Style) {
		switch style {
		case .feedList:
			// 与首页订阅源行对齐：行高 44，方块在 x=34（20pt），名字从 x=62 起
			let widths: [CGFloat] = [0.42, 0.55, 0.36, 0.48, 0.3, 0.5]
			for (index, width) in widths.enumerated() {
				let top = CGFloat(index) * 44 + 12
				addBar(x: 34, top: top, width: 20, widthFraction: nil, height: 20, radius: 5)
				addBar(x: 62, top: top + 4, width: 0, widthFraction: width, height: 12, radius: 4)
			}
		case .articleList:
			// 与文章行对齐：图标 x=20（20pt），文字从 x=49 起；每行约 96pt
			let widths: [(CGFloat, CGFloat)] = [(0.78, 0.5), (0.7, 0.62), (0.82, 0.4), (0.66, 0.56)]
			for (index, width) in widths.enumerated() {
				let top = CGFloat(index) * 96 + 16
				addBar(x: 49, top: top, width: 0, widthFraction: 0.28, height: 9, radius: 3)
				addBar(x: 20, top: top + 20, width: 20, widthFraction: nil, height: 20, radius: 5)
				addBar(x: 49, top: top + 22, width: 0, widthFraction: width.0, height: 13, radius: 4)
				addBar(x: 49, top: top + 42, width: 0, widthFraction: width.1, height: 11, radius: 4)
			}
		}
	}

	/// 一条灰色条。widthFraction 不为 nil 时按「屏幕宽 − 左起点 − 20」的比例定宽。
	private func addBar(x: CGFloat, top: CGFloat, width: CGFloat, widthFraction: CGFloat?, height: CGFloat, radius: CGFloat) {
		let bar = UIView()
		bar.backgroundColor = BabelPalette.raisedBackground
		bar.layer.cornerRadius = radius
		bar.layer.cornerCurve = .continuous
		bar.translatesAutoresizingMaskIntoConstraints = false
		content.addSubview(bar)
		var constraints = [
			bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: x),
			bar.topAnchor.constraint(equalTo: content.topAnchor, constant: top),
			bar.heightAnchor.constraint(equalToConstant: height)
		]
		if let widthFraction {
			constraints.append(bar.widthAnchor.constraint(equalTo: content.widthAnchor, multiplier: widthFraction, constant: -(x + 20) * widthFraction))
		} else {
			constraints.append(bar.widthAnchor.constraint(equalToConstant: width))
		}
		NSLayoutConstraint.activate(constraints)
	}
}
