//
//  NNWProgressCard.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增,上游没有这个文件。
//
//  自绘的「进度卡片」—— 屏幕正中一张小暖纸卡,转圈 + 一句话,
//  用来取代系统 UIAlertController 拼出来的转圈提示(长图「正在生成…」那种)。
//  和 NNWMenu 长一个样(同一套卡片底色/圆角/描边),只是没有可点的行、也不能点外面关掉 ——
//  它代表"正在干活,请稍等",只能由代码在活干完时收掉。
//
//  ## 怎么用
//
//      let progress = NNWProgressCard.present(in: self, text: "正在生成长图…")
//      ...活干完后:
//      progress.finish { /* 收掉之后要做的事(弹预览、报错……) */ }
//

#if os(iOS)

import UIKit

@MainActor
enum NNWProgressCard {

	/// 弹出进度卡片,返回控制柄(干完活调它的 finish)。
	static func present(in host: UIViewController, text: String) -> NNWProgressCardController {
		let card = NNWProgressCardController(text: text)
		card.modalPresentationStyle = .overFullScreen
		host.present(card, animated: false)		// 动画自己做(浮现),理由同 NNWMenu
		return card
	}
}

@MainActor
final class NNWProgressCardController: UIViewController {

	private let text: String
	private let dim = UIView()
	private let card = UIView()

	init(text: String) {
		self.text = text
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) { fatalError("不走 storyboard") }

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = .clear

		// 压暗层(**不**装点按手势 —— 进度卡不允许点外面关掉,活没干完关了没意义)
		dim.backgroundColor = UIColor.black.withAlphaComponent(0.2)
		dim.frame = view.bounds
		dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		view.addSubview(dim)

		// 卡片(样式与 NNWMenu 一致;没有滚动内容,阴影直接画在卡片上即可,不用拆层)
		card.backgroundColor = AppAppearance.menuCardBackground
		card.layer.cornerRadius = 22
		card.layer.cornerCurve = .continuous
		card.layer.borderWidth = 1.0 / max(view.traitCollection.displayScale, 1)
		card.layer.borderColor = AppAppearance.menuSeparator.cgColor
		card.layer.shadowColor = UIColor.black.cgColor
		card.layer.shadowOpacity = 0.22
		card.layer.shadowRadius = 24
		card.layer.shadowOffset = CGSize(width: 0, height: 8)
		card.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(card)

		let spinner = UIActivityIndicatorView(style: .medium)
		spinner.color = AppAppearance.inkSecondary
		spinner.startAnimating()

		let label = UILabel()
		label.text = text
		label.font = .preferredFont(forTextStyle: .body)
		label.adjustsFontForContentSizeCategory = true
		label.textColor = AppAppearance.inkPrimary
		label.numberOfLines = 0
		label.textAlignment = .center

		let stack = UIStackView(arrangedSubviews: [spinner, label])
		stack.axis = .vertical
		stack.alignment = .center
		stack.spacing = 14
		stack.translatesAutoresizingMaskIntoConstraints = false
		card.addSubview(stack)

		// 卡片吊在安全区正中,大小由内容撑(转圈 + 一两行字,不会超屏,不需要滚动那套)
		NSLayoutConstraint.activate([
			card.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
			card.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
			card.widthAnchor.constraint(lessThanOrEqualToConstant: 260),

			stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
			stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),
			stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 28),
			stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -28)
		])

		// VoiceOver 播报"正在干活"
		view.accessibilityViewIsModal = true
		card.isAccessibilityElement = true
		card.accessibilityLabel = text

		// 浮现动画的起点
		card.alpha = 0
		dim.alpha = 0
		if !UIAccessibility.isReduceMotionEnabled {
			card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
		}
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		UIView.animate(withDuration: 0.2) {
			self.card.alpha = 1
			self.dim.alpha = 1
			self.card.transform = .identity
		}
	}

	/// 活干完了:收掉卡片,收完执行 completion(在里面弹预览 / 报错都安全,不会撞模态)。
	func finish(completion: (() -> Void)? = nil) {
		UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseIn]) {
			self.card.alpha = 0
			self.dim.alpha = 0
		} completion: { _ in
			self.dismiss(animated: false) { completion?() }
		}
	}
}

#endif
