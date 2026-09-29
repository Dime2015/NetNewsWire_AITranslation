import UIKit
import Babel2Core

/// 首页顶部的跨源入口（2026-09-27 用户反馈第 5 条，ADR-044）。
///
/// 取代原来那行点不开的「未读 / 全部 / 星标」分组标题：跟随底部档位显示
/// 未读档 = 今日未读 / 全部未读 / 外文源；全部档 = 今天 / 全部文章 / 外文源；星标档 = 全部星标。
/// 点进去是跨订阅源合并的文章列表（与单个订阅源同一个列表页，每篇显示自己的来源）。
extension Babel2SmartFeed {
	/// 在这个档位下叫什么。
	func titleKey(scope: Babel2FeedScope) -> Babel2LocalizationKey {
		switch Babel2SmartFeed.effective(self, scope: scope) {
		case .today: return scope == .unread ? .smartTodayUnread : .smartToday
		case .all: return scope == .unread ? .smartAllUnread : .smartAllArticles
		case .foreign: return .smartForeign
		case .starred: return .smartStarred
		}
	}

	/// 行首图标（统一图标集，ADR-065；与订阅源图标同一位置）。
	var icon: Babel2Icon {
		switch self {
		case .today: return .today
		case .all: return .inbox
		case .foreign: return .globe
		case .starred: return .star
		}
	}
}

/// 一行入口：符号 + 名称 + 篇数，外观与首页的订阅源行一致（44pt 高、图标中心 x=44、名称 x=62、篇数贴右 18pt），
/// 按下时出现与订阅源行相同的圆角底色。
@MainActor
final class Babel2SmartEntryRow: UIControl {
	static let height: CGFloat = 44
	let kind: Babel2SmartFeed
	private let highlight = UIView()
	private let iconView = UIImageView()
	let titleLabel = UILabel()
	let countLabel = UILabel()

	init(kind: Babel2SmartFeed, scope: Babel2FeedScope, bundle: Bundle) {
		self.kind = kind
		super.init(frame: .zero)
		isAccessibilityElement = true
		accessibilityTraits = .button
		accessibilityIdentifier = "babel2.feeds.smart.\(kind.rawValue)"

		highlight.backgroundColor = BabelPalette.raisedBackground
		highlight.layer.cornerRadius = 10
		highlight.layer.cornerCurve = .continuous
		highlight.alpha = 0
		highlight.isUserInteractionEnabled = false

		iconView.image = kind.icon.image(size: Babel2Icon.Size.entry)
		iconView.tintColor = Babel2Icon.tint
		iconView.contentMode = .center

		titleLabel.text = Babel2Localization.text(kind.titleKey(scope: scope), bundle: bundle)
		titleLabel.font = Babel2Type.homeFeed
		titleLabel.textColor = BabelPalette.ink
		titleLabel.lineBreakMode = .byTruncatingTail

		countLabel.font = Babel2Type.homeCount
		countLabel.textColor = BabelPalette.tertiaryInk
		countLabel.textAlignment = .right

		for view in [highlight, iconView, titleLabel, countLabel] {
			view.translatesAutoresizingMaskIntoConstraints = false
			view.isUserInteractionEnabled = false
			addSubview(view)
		}
		NSLayoutConstraint.activate([
			heightAnchor.constraint(equalToConstant: Self.height),
			highlight.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
			highlight.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
			highlight.topAnchor.constraint(equalTo: topAnchor),
			highlight.bottomAnchor.constraint(equalTo: bottomAnchor),
			iconView.centerXAnchor.constraint(equalTo: leadingAnchor, constant: 44),
			iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
			iconView.widthAnchor.constraint(equalToConstant: Babel2Type.homeFeedIcon),
			iconView.heightAnchor.constraint(equalToConstant: Babel2Type.homeFeedIcon),
			titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 62),
			titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -12),
			countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
			countLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
		])
		setCount(nil)
	}

	required init?(coder: NSCoder) { nil }

	override var isHighlighted: Bool {
		didSet {
			guard isHighlighted != oldValue else { return }
			Babel2Motion.animate(Babel2Motion.quick) { self.highlight.alpha = self.isHighlighted ? 1 : 0 }
		}
	}

	/// 篇数：0 或没有数据时不显示。
	func setCount(_ count: Int?) {
		let text = count.flatMap { $0 > 0 ? $0.formatted() : nil }
		countLabel.text = text
		countLabel.isHidden = text == nil
		accessibilityLabel = titleLabel.text
		accessibilityValue = text
	}
}
