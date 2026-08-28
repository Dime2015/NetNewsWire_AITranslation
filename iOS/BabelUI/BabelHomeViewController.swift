//
//  BabelHomeViewController.swift
//  NetNewsWire
//

import UIKit
import Articles

final class BabelHomeViewController: UIViewController {

	var onSelectSection: ((BabelLibrarySection) -> Void)?
	var onSelectArticle: ((Article) -> Void)?
	var onOpenGenesisV2: (() -> Void)?

	private let scrollView = UIScrollView()
	private let contentStack = UIStackView()
	private let libraryStack = UIStackView()
	private let contextLabel = UILabel()
	private let latestButton = BabelLatestArticleButton()
	private var queueRows = [BabelLibrarySection: BabelQueueRow]()
	private var latestArticle: Article?
	private var loadTask: Task<Void, Never>?

	override func viewDidLoad() {
		super.viewDidLoad()
		configureView()
		startObserving()
		reloadSnapshot()
	}

	deinit {
		loadTask?.cancel()
		NotificationCenter.default.removeObserver(self)
	}

	private func configureView() {
		view.backgroundColor = BabelPalette.background

		navigationItem.largeTitleDisplayMode = .never
		navigationItem.rightBarButtonItem = UIBarButtonItem(
			image: UIImage(systemName: "clock.arrow.circlepath"),
			style: .plain,
			target: self,
			action: #selector(openGenesisV2)
		)
		navigationItem.rightBarButtonItem?.accessibilityLabel = "打开创世版本 2"

		scrollView.alwaysBounceVertical = true
		scrollView.backgroundColor = BabelPalette.background
		view.addSubview(scrollView)
		scrollView.babelPinToEdges(of: view)

		contentStack.axis = .vertical
		contentStack.spacing = 0
		contentStack.translatesAutoresizingMaskIntoConstraints = false
		scrollView.addSubview(contentStack)

		NSLayoutConstraint.activate([
			contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
			contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),
			contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
			contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -48),
			contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48)
		])

		let dateLabel = UILabel()
		dateLabel.text = Self.dateFormatter.string(from: Date()).uppercased()
		dateLabel.font = .preferredFont(forTextStyle: .caption1)
		dateLabel.textColor = BabelPalette.mutedInk
		contentStack.addArrangedSubview(dateLabel)
		contentStack.setCustomSpacing(12, after: dateLabel)

		let titleLabel = UILabel()
		titleLabel.text = Self.greeting
		titleLabel.font = BabelTypography.display(size: 44)
		titleLabel.textColor = BabelPalette.ink
		titleLabel.numberOfLines = 0
		titleLabel.adjustsFontForContentSizeCategory = true
		contentStack.addArrangedSubview(titleLabel)

		let introductionLabel = UILabel()
		introductionLabel.text = "让值得读的内容，安静地排到眼前。"
		introductionLabel.font = .preferredFont(forTextStyle: .body)
		introductionLabel.textColor = BabelPalette.mutedInk
		introductionLabel.numberOfLines = 0
		contentStack.addArrangedSubview(introductionLabel)
		contentStack.setCustomSpacing(42, after: introductionLabel)

		contentStack.addArrangedSubview(makeSectionLabel("接下来读"))
		contentStack.setCustomSpacing(12, after: contentStack.arrangedSubviews.last!)

		latestButton.isHidden = true
		latestButton.addTarget(self, action: #selector(openLatestArticle), for: .touchUpInside)
		contentStack.addArrangedSubview(latestButton)
		contentStack.setCustomSpacing(38, after: latestButton)

		contentStack.addArrangedSubview(makeSectionLabel("阅读队列"))
		contentStack.setCustomSpacing(10, after: contentStack.arrangedSubviews.last!)

		libraryStack.axis = .vertical
		libraryStack.spacing = 0
		libraryStack.layer.cornerRadius = 18
		libraryStack.layer.cornerCurve = .continuous
		libraryStack.clipsToBounds = true
		libraryStack.backgroundColor = BabelPalette.raisedBackground
		contentStack.addArrangedSubview(libraryStack)

		for (index, section) in BabelLibrarySection.allCases.enumerated() {
			let row = BabelQueueRow(section: section)
			row.tag = index
			row.addTarget(self, action: #selector(openQueue(_:)), for: .touchUpInside)
			queueRows[section] = row
			libraryStack.addArrangedSubview(row)

			if index < BabelLibrarySection.allCases.count - 1 {
				let separator = UIView()
				separator.backgroundColor = BabelPalette.hairline
				separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
				libraryStack.addArrangedSubview(separator)
			}
		}

		contextLabel.font = .preferredFont(forTextStyle: .footnote)
		contextLabel.textColor = BabelPalette.mutedInk
		contextLabel.numberOfLines = 0
		contextLabel.textAlignment = .center
		contextLabel.text = "正在读取本地资料库…"
		contentStack.setCustomSpacing(18, after: libraryStack)
		contentStack.addArrangedSubview(contextLabel)
	}

	private func makeSectionLabel(_ title: String) -> UILabel {
		let label = UILabel()
		label.text = title
		label.font = .systemFont(ofSize: 13, weight: .semibold)
		label.textColor = BabelPalette.mutedInk
		return label
	}

	private func startObserving() {
		let names: [Notification.Name] = [
			.UnreadCountDidChange,
			.AccountDidDownloadArticles,
			.UserDidAddAccount,
			.UserDidDeleteAccount,
			.nnwTitleTranslationDidUpdate
		]
		for name in names {
			NotificationCenter.default.addObserver(self, selector: #selector(dataDidChange), name: name, object: nil)
		}
	}

	@objc private func dataDidChange() {
		reloadSnapshot()
	}

	private func reloadSnapshot() {
		loadTask?.cancel()
		loadTask = Task { [weak self] in
			let snapshot = await BabelLibrary.loadHomeSnapshot()
			guard !Task.isCancelled else { return }
			self?.apply(snapshot)
		}
	}

	private func apply(_ snapshot: BabelHomeSnapshot) {
		for section in BabelLibrarySection.allCases {
			queueRows[section]?.setCount(snapshot.counts[section] ?? 0)
		}

		contextLabel.text = "\(snapshot.accountCount) 个账户 · \(snapshot.feedCount) 个订阅源 · 只读预览"

		latestArticle = snapshot.latestUnreadArticle
		if let article = snapshot.latestUnreadArticle {
			latestButton.configure(
				feed: article.feed?.nameForDisplay ?? "订阅文章",
				title: BabelLibrary.displayTitle(for: article),
				date: Self.relativeFormatter.localizedString(for: article.logicalDatePublished, relativeTo: Date())
			)
			latestButton.isHidden = false
		} else {
			latestButton.isHidden = true
		}
	}

	@objc private func openQueue(_ sender: BabelQueueRow) {
		guard BabelLibrarySection.allCases.indices.contains(sender.tag) else { return }
		onSelectSection?(BabelLibrarySection.allCases[sender.tag])
	}

	@objc private func openLatestArticle() {
		guard let latestArticle else { return }
		onSelectArticle?(latestArticle)
	}

	@objc private func openGenesisV2() {
		onOpenGenesisV2?()
	}

	private static let dateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = .current
		formatter.setLocalizedDateFormatFromTemplate("EEEE, MMMM d")
		return formatter
	}()

	private static let relativeFormatter = RelativeDateTimeFormatter()

	private static var greeting: String {
		switch Calendar.current.component(.hour, from: Date()) {
		case 5..<12: "早上好。"
		case 12..<18: "下午好。"
		default: "晚上好。"
		}
	}
}

private final class BabelQueueRow: UIControl {

	private let countLabel = UILabel()

	init(section: BabelLibrarySection) {
		super.init(frame: .zero)
		backgroundColor = .clear
		accessibilityTraits = .button

		let icon = UIImageView(image: UIImage(systemName: section.symbolName))
		icon.tintColor = BabelPalette.accent
		icon.contentMode = .scaleAspectFit
		icon.translatesAutoresizingMaskIntoConstraints = false
		icon.widthAnchor.constraint(equalToConstant: 22).isActive = true

		let titleLabel = UILabel()
		titleLabel.text = section.title
		titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
		titleLabel.textColor = BabelPalette.ink

		let subtitleLabel = UILabel()
		subtitleLabel.text = section.subtitle
		subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
		subtitleLabel.textColor = BabelPalette.mutedInk

		let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
		labels.axis = .vertical
		labels.spacing = 3

		countLabel.text = "—"
		countLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .medium)
		countLabel.textColor = BabelPalette.ink
		countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

		let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
		chevron.tintColor = BabelPalette.mutedInk
		chevron.contentMode = .scaleAspectFit

		let row = UIStackView(arrangedSubviews: [icon, labels, countLabel, chevron])
		row.alignment = .center
		row.spacing = 14
		row.isUserInteractionEnabled = false
		row.translatesAutoresizingMaskIntoConstraints = false
		addSubview(row)

		NSLayoutConstraint.activate([
			row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
			row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
			row.topAnchor.constraint(equalTo: topAnchor, constant: 17),
			row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -17)
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func setCount(_ count: Int) {
		countLabel.text = count.formatted()
		accessibilityValue = "\(count)"
	}

	override var isHighlighted: Bool {
		didSet {
			alpha = isHighlighted ? 0.55 : 1
		}
	}
}

private final class BabelLatestArticleButton: UIControl {

	private let feedLabel = UILabel()
	private let titleLabel = UILabel()
	private let dateLabel = UILabel()

	override init(frame: CGRect) {
		super.init(frame: frame)
		backgroundColor = BabelPalette.raisedBackground
		layer.cornerRadius = 22
		layer.cornerCurve = .continuous
		accessibilityTraits = .button

		feedLabel.font = .systemFont(ofSize: 12, weight: .semibold)
		feedLabel.textColor = BabelPalette.accent

		titleLabel.font = BabelTypography.title(size: 23)
		titleLabel.textColor = BabelPalette.ink
		titleLabel.numberOfLines = 3

		dateLabel.font = .preferredFont(forTextStyle: .caption1)
		dateLabel.textColor = BabelPalette.mutedInk

		let arrow = UIImageView(image: UIImage(systemName: "arrow.up.right"))
		arrow.tintColor = BabelPalette.mutedInk
		arrow.setContentHuggingPriority(.required, for: .horizontal)

		let topRow = UIStackView(arrangedSubviews: [feedLabel, UIView(), arrow])
		topRow.alignment = .center

		let stack = UIStackView(arrangedSubviews: [topRow, titleLabel, dateLabel])
		stack.axis = .vertical
		stack.spacing = 12
		stack.isUserInteractionEnabled = false
		stack.translatesAutoresizingMaskIntoConstraints = false
		addSubview(stack)

		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
			stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
			stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
			stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18)
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(feed: String, title: String, date: String) {
		feedLabel.text = feed.uppercased()
		titleLabel.text = title
		dateLabel.text = date
		accessibilityLabel = "\(feed)，\(title)，\(date)"
	}

	override var isHighlighted: Bool {
		didSet {
			transform = isHighlighted ? CGAffineTransform(scaleX: 0.985, y: 0.985) : .identity
			alpha = isHighlighted ? 0.7 : 1
		}
	}
}
