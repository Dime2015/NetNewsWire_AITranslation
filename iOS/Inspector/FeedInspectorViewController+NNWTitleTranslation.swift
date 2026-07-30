//
//  FeedInspectorViewController+NNWTitleTranslation.swift
//  NetNewsWire — AI 翻译 fork
//
//  [翻译] 本 fork 新增,上游没有这个文件。
//
//  给上游的「源简介」页(FeedInspectorViewController)程序化地加一行
//  「标题翻译成中文」开关 —— **不动 Inspector.storyboard**。
//
//  ## 为什么不走 storyboard
//  那页是 storyboard 静态表。往 XML 里加行的 merge 冲突又难读又难解,
//  而"静态表在代码里补一行"是 UIKit 的常规做法:数据源报多一行、
//  cellForRow 拦下这一行自己造 cell、height/indentation 两个方法替它答题
//  (静态表对 storyboard 里不存在的行号问 super 会崩,所以必须拦全)。
//  上游 VC 里只加了几处带 [翻译] 标记的调用,实现全部住在本文件。
//
//  ## 行号为什么写死是 3
//  storyboard 里第 0 区固定是 3 行:名称 / 新文章通知 / 始终使用阅读视图。
//  我们的开关排在它们后面 = 行号 3。上游若往这一区加行,这里要跟着改 ——
//  但那也意味着 merge 时必然会冲突到旁边的标记行,不会静默错位。
//

import UIKit
import Account

extension FeedInspectorViewController {

	/// 我们插的那一行:第 0 区(名称/通知/阅读视图那一区)的末尾
	private static let titleTranslationRow = 3

	/// 这个 indexPath 是不是我们插的开关行
	func nnwIsTitleTranslationRow(_ indexPath: IndexPath) -> Bool {
		indexPath.section == 0 && indexPath.row == Self.titleTranslationRow
	}

	/// 造开关行的 cell。**度量逐项照抄 storyboard 里「始终使用阅读视图」那行**,
	/// 否则和上面几行对不齐(2026-07-29 用户截图指出:初版用 textLabel,左边差了 4pt):
	/// 标签 = 布局边距 + 4pt、body 动态字体;开关 = 尾部 20pt;行高 = 开关上下各 10pt ≈ 51pt。
	func nnwTitleTranslationCell() -> UITableViewCell {
		let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
		cell.selectionStyle = .none

		let label = UILabel()
		label.text = "标题翻译成中文"
		label.font = .preferredFont(forTextStyle: .body)
		label.adjustsFontForContentSizeCategory = true
		label.numberOfLines = 1
		label.translatesAutoresizingMaskIntoConstraints = false
		cell.contentView.addSubview(label)

		let toggle = UISwitch()
		toggle.isOn = nnwTitleTranslationIsEnabled
		toggle.addTarget(self, action: #selector(nnwTitleTranslationToggled(_:)), for: .valueChanged)
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
}
