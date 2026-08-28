//
//  SettingsViewController+AccentColor.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增。设置 → 外观 → 「强调色」那一行点开之后的事。
//
//  实现放在这个扩展文件里,上游的 `SettingsViewController.swift` 只多了四处标记行
//  (行数 +1、cellForRow 一个 case、didSelect 一个 case、一个行号属性)。
//

#if os(iOS)

import UIKit

extension SettingsViewController {

	/// 弹出配色选单。用本 fork 自绘的 `NNWMenu`,不用系统动作单。
	func nnwShowAccentColorPicker(from indexPath: IndexPath) {

		let rect = tableView.rectForRow(at: indexPath)
		let items = NNWAccentPalette.Choice.allCases.map { choice in
			NNWMenu.Item(title: choice.displayName,
						 image: Self.nnwSwatch(NNWAccentPalette.color(for: choice),
											   isCurrent: choice == NNWAccentPalette.choice)) {
				NNWAccentPalette.setChoice(choice)
			}
		}

		NNWMenu.show(in: self, anchor: .rect(rect, within: tableView),
					 title: "强调色", sections: [items])
	}

	/// 每一行右边那颗色块。当前选中的那颗多一圈墨色描边(自绘选单没有"打勾"这个位)。
	private static func nnwSwatch(_ color: UIColor, isCurrent: Bool) -> UIImage {
		let side: CGFloat = 22
		return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
			let traits = UITraitCollection.current
			let rect = CGRect(x: 2, y: 2, width: side - 4, height: side - 4)
			let dot = UIBezierPath(ovalIn: rect)
			color.resolvedColor(with: traits).setFill()
			dot.fill()
			if isCurrent {
				let ring = UIBezierPath(ovalIn: rect.insetBy(dx: -2, dy: -2))
				ring.lineWidth = 1.6
				NNWSoftMaterial.menuInk.resolvedColor(with: traits).setStroke()
				ring.stroke()
			}
		}.withRenderingMode(.alwaysOriginal)
	}
}

// MARK: - 换色之后,把"烘焙成图片"的那几颗控件重画

extension UIViewController {

	/// [外观] 首页那两颗工具栏圆钮(齿轮 / 加号)的面板是**画进图片**里的,
	/// 图片不会自己跟着强调色变 —— 换色后必须重画一遍。
	///
	/// ⚠️ 和深浅色那条是同一个病(见 L105 第 2 条):凡是烘焙成位图的东西,
	/// **任何会改变它外观的输入变化,都要有人叫它重画**。
	@MainActor
	func nnwObserveAccentChanges(_ handler: @MainActor @Sendable @escaping () -> Void) {
		NotificationCenter.default.addObserver(forName: NNWAccentPalette.didChangeNotification,
											   object: nil, queue: .main) { _ in
			MainActor.assumeIsolated { handler() }
		}
	}
}

#endif
