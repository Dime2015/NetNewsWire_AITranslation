//
//  FeedInspectorViewController+NNWTitleTranslation.swift
//  NetNewsWire — AI 翻译 fork
//
//  [翻译][外文] 本 fork 新增,上游没有这个文件。
//
//  给上游的「源简介」页(FeedInspectorViewController)程序化地加**两行开关** ——
//  **不动 Inspector.storyboard**:
//
//  | 行 | 是什么 | 谁在用 |
//  |---|---|---|
//  | 3 | 标题翻译成中文 | T32①(2026-07-29) |
//  | 4 | 这是外文源 | 用户 2026-08-08 第 5 件,给「外文」智能源用 |
//
//  ## 为什么不走 storyboard
//  那页是 storyboard 静态表。往 XML 里加行的 merge 冲突又难读又难解,
//  而"静态表在代码里补几行"是 UIKit 的常规做法:数据源报多几行、
//  cellForRow 拦下这些行自己造 cell、height/indentation 两个方法替它答题
//  (静态表对 storyboard 里不存在的行号问 super 会崩,所以必须拦全)。
//  上游 VC 里只加了几处带 [翻译] 标记的调用,实现全部住在本文件。
//
//  ## 行号为什么从 3 开始
//  storyboard 里第 0 区固定是 3 行:名称 / 新文章通知 / 始终使用阅读视图。
//  我们的开关排在它们后面 = 行号 3、4。上游若往这一区加行,这里要跟着改 ——
//  但那也意味着 merge 时必然会冲突到旁边的标记行,不会静默错位。
//
//  ⚠️ **加第三行的时候只改 `extraRows` 这一个数组**,上游那四处调用一个字都不用动
//  (2026-08-08 加第二行时就是这么做的,净改动 = 上游 0 行)。
//

import UIKit
import Account

extension FeedInspectorViewController {

	/// 本 fork 往第 0 区末尾追加的行,**顺序即行序**。
	fileprivate enum NNWExtraRow: Int, CaseIterable {
		case titleTranslation	// 行 3
		case foreignFeed		// 行 4

		/// storyboard 里第 0 区本来有几行 —— 我们的行从这个数往后排。
		static let storyboardRowCount = 3

		var indexPathRow: Int { Self.storyboardRowCount + rawValue }
	}

	/// 第 0 区一共被我们加了几行。上游 `numberOfRowsInSection` 用它。
	var nnwExtraRowCount: Int { NNWExtraRow.allCases.count }

	/// 这个 indexPath 是不是我们加的行。
	func nnwIsExtraRow(_ indexPath: IndexPath) -> Bool {
		nnwExtraRow(at: indexPath) != nil
	}

	fileprivate func nnwExtraRow(at indexPath: IndexPath) -> NNWExtraRow? {
		guard indexPath.section == 0 else { return nil }
		return NNWExtraRow.allCases.first { $0.indexPathRow == indexPath.row }
	}

	/// 造我们那几行的 cell。不是我们的行返回 nil(上游会去问 super)。
	func nnwExtraRowCell(at indexPath: IndexPath) -> UITableViewCell? {
		switch nnwExtraRow(at: indexPath) {
		case .titleTranslation:
			return nnwSwitchCell(title: "标题翻译成中文",
								 isOn: nnwTitleTranslationIsEnabled,
								 action: #selector(nnwTitleTranslationToggled(_:)))
		case .foreignFeed:
			let cell = nnwSwitchCell(title: "这是外文源",
									 isOn: nnwFeedIsForeign,
									 action: #selector(nnwForeignFeedToggled(_:)))
			return cell
		case nil:
			return nil
		}
	}

	// MARK: - 造 cell

	/// 一行「文字 + 开关」。**度量逐项照抄 storyboard 里「始终使用阅读视图」那行**,
	/// 否则和上面几行对不齐(2026-07-29 用户截图指出:初版用 textLabel,左边差了 4pt):
	/// 标签 = 布局边距 + 4pt、body 动态字体;开关 = 尾部 20pt;行高 = 开关上下各 10pt ≈ 51pt。
	private func nnwSwitchCell(title: String, isOn: Bool, action: Selector) -> UITableViewCell {
		let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
		cell.selectionStyle = .none

		let label = UILabel()
		label.text = title
		label.font = .preferredFont(forTextStyle: .body)
		label.adjustsFontForContentSizeCategory = true
		label.numberOfLines = 1
		label.translatesAutoresizingMaskIntoConstraints = false
		cell.contentView.addSubview(label)

		let toggle = UISwitch()
		toggle.isOn = isOn
		// [外观] 2026-08-08:开关颜色跟着主题色走。这一行原来**从没上过色**(用系统绿),
		// 和全 app 脱节 —— 用户第 9 件点名的两处之一。见 NNWAccentTint。
		toggle.onTintColor = NNWAccentPalette.live
		toggle.addTarget(self, action: action, for: .valueChanged)
		toggle.translatesAutoresizingMaskIntoConstraints = false
		cell.contentView.addSubview(toggle)

		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor, constant: 4),
			label.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
			label.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8),
			toggle.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -20),
			toggle.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 10),
			toggle.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -10)
		])
		return cell
	}

	// MARK: - 标题翻译成中文

	private var nnwTitleTranslationIsEnabled: Bool {
		guard let feed, let accountID = feed.account?.accountID else { return false }
		return NNWTitleTranslationStore.shared.isEnabled(accountID: accountID, feedID: feed.feedID)
	}

	@objc private func nnwTitleTranslationToggled(_ sender: UISwitch) {
		guard let feed, let accountID = feed.account?.accountID else { return }
		NNWTitleTranslationStore.shared.setEnabled(sender.isOn, accountID: accountID, feedID: feed.feedID)
		// 通知开着的列表刷新:开 → 可见行开始排队翻译;关 → 立刻换回原文
		NotificationCenter.default.post(name: .nnwTitleTranslationDidUpdate, object: nil)
	}

	// MARK: - 这是外文源

	/// 开关显示的是**现在的实际结论**(手动定过就是手动的,没定过就是自动认出来的),
	/// 所以用户看到的永远是"这个源现在算不算外文",不用去猜是谁定的。
	private var nnwFeedIsForeign: Bool {
		guard let feed else { return false }
		return NNWForeignFeedStore.shared.isForeign(feed)
	}

	@objc private func nnwForeignFeedToggled(_ sender: UISwitch) {
		guard let feed else { return }
		// 用户一拨就是**明确的决定**,从此压过自动判定(见 NNWForeignFeedStore 文件头)
		NNWForeignFeedStore.shared.setManualOverride(sender.isOn, for: feed)
	}
}
