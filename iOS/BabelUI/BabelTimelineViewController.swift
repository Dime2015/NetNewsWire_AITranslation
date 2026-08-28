//
//  BabelTimelineViewController.swift
//  NetNewsWire
//

import UIKit
import Articles

final class BabelTimelineViewController: UIViewController {

	private let section: BabelLibrarySection
	private let tableView = UITableView(frame: .zero, style: .plain)
	private let emptyLabel = UILabel()
	private var articles = [Article]()
	private var loadTask: Task<Void, Never>?

	init(section: BabelLibrarySection) {
		self.section = section
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		configureView()
		reloadArticles()
		startObserving()
	}

	deinit {
		loadTask?.cancel()
		NotificationCenter.default.removeObserver(self)
	}

	private func configureView() {
		title = section.title
		view.backgroundColor = BabelPalette.background
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            style: .plain, target: self, action: #selector(showActions)
        )

		tableView.backgroundColor = BabelPalette.background
		tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: 2, left: 0, bottom: 62, right: 0)
		tableView.rowHeight = UITableView.automaticDimension
		tableView.estimatedRowHeight = 154
		tableView.register(BabelTimelineCell.self, forCellReuseIdentifier: BabelTimelineCell.reuseIdentifier)
		tableView.dataSource = self
		tableView.delegate = self
		view.addSubview(tableView)
		tableView.babelPinToEdges(of: view)

		emptyLabel.text = "这里暂时没有文章"
		emptyLabel.font = BabelTypography.reading(size: 19)
		emptyLabel.textColor = BabelPalette.mutedInk
		emptyLabel.textAlignment = .center
		emptyLabel.isHidden = true
		emptyLabel.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(emptyLabel)
		NSLayoutConstraint.activate([
			emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
			emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
		])

		let refreshControl = UIRefreshControl()
		refreshControl.addTarget(self, action: #selector(refreshFromControl), for: .valueChanged)
        tableView.refreshControl = refreshControl

        let bottom = UIStackView()
        bottom.axis = .horizontal
        bottom.distribution = .equalCentering
        bottom.alignment = .center
        bottom.backgroundColor = BabelPalette.background
        bottom.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottom)
        for (symbol, label) in [("checkmark.circle", "已读"), ("star", "星标"),
                                ("circle.fill", "未读"), ("magnifyingglass", "搜索")] {
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: symbol)
            config.imagePlacement = .top
            config.imagePadding = 2
            config.baseForegroundColor = BabelPalette.mutedInk
            config.attributedTitle = AttributedString(label, attributes: AttributeContainer([
                .font: UIFont.systemFont(ofSize: 10)
            ]))
            bottom.addArrangedSubview(UIButton(configuration: config))
        }
        NSLayoutConstraint.activate([
            bottom.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottom.heightAnchor.constraint(equalToConstant: 54)
        ])
	}

	private func startObserving() {
		let names: [Notification.Name] = [
			.UnreadCountDidChange,
			.AccountDidDownloadArticles,
			.nnwTitleTranslationDidUpdate
		]
		for name in names {
			NotificationCenter.default.addObserver(self, selector: #selector(dataDidChange), name: name, object: nil)
		}
	}

	@objc private func dataDidChange() {
		reloadArticles()
	}

    @objc private func refreshFromControl() {
        reloadArticles()
    }

    @objc private func showActions() {
        let alert = UIAlertController(title: section.title, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "标记全部已读", style: .default))
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

	private func reloadArticles() {
		loadTask?.cancel()
		loadTask = Task { [weak self] in
			guard let self else { return }
			let loaded = await BabelLibrary.loadArticles(for: section)
			guard !Task.isCancelled else { return }
			articles = loaded
			tableView.reloadData()
			tableView.refreshControl?.endRefreshing()
			emptyLabel.isHidden = !loaded.isEmpty
		}
	}
}

extension BabelTimelineViewController: UITableViewDataSource, UITableViewDelegate {

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		articles.count
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: BabelTimelineCell.reuseIdentifier, for: indexPath) as! BabelTimelineCell
		cell.configure(article: articles[indexPath.row])
		return cell
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		navigationController?.pushViewController(BabelReaderViewController(article: articles[indexPath.row]), animated: true)
	}
}

private final class BabelTimelineCell: UITableViewCell {

	static let reuseIdentifier = "BabelTimelineCell"

	private let unreadDot = UIView()
	private let feedLabel = UILabel()
	private let dateLabel = UILabel()
	private let titleLabel = UILabel()
	private let summaryLabel = UILabel()
	private let separator = UIView()

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		backgroundColor = .clear
		selectedBackgroundView = {
			let view = UIView()
			view.backgroundColor = BabelPalette.raisedBackground
			return view
		}()

		unreadDot.backgroundColor = BabelPalette.accent
		unreadDot.layer.cornerRadius = 3
		unreadDot.translatesAutoresizingMaskIntoConstraints = false

        feedLabel.font = .systemFont(ofSize: 11, weight: .semibold)
		feedLabel.textColor = BabelPalette.mutedInk
		feedLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

		dateLabel.font = .preferredFont(forTextStyle: .caption1)
		dateLabel.textColor = BabelPalette.mutedInk
		dateLabel.textAlignment = .right
		dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.font = BabelTypography.title(size: 17)
		titleLabel.textColor = BabelPalette.ink
		titleLabel.numberOfLines = 3

        summaryLabel.font = .systemFont(ofSize: 12)
		summaryLabel.textColor = BabelPalette.mutedInk
		summaryLabel.numberOfLines = 2

		let metaRow = UIStackView(arrangedSubviews: [unreadDot, feedLabel, UIView(), dateLabel])
		metaRow.alignment = .center
		metaRow.spacing = 8

		let stack = UIStackView(arrangedSubviews: [metaRow, titleLabel, summaryLabel])
		stack.axis = .vertical
		stack.spacing = 9
		stack.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(stack)

		separator.backgroundColor = BabelPalette.hairline
		separator.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(separator)

		NSLayoutConstraint.activate([
			unreadDot.widthAnchor.constraint(equalToConstant: 6),
			unreadDot.heightAnchor.constraint(equalToConstant: 6),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -12),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
			separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
		])
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func configure(article: Article) {
		feedLabel.text = (article.feed?.nameForDisplay ?? "订阅文章").uppercased()
		dateLabel.text = Self.relativeFormatter.localizedString(for: article.logicalDatePublished, relativeTo: Date())
		titleLabel.text = BabelLibrary.displayTitle(for: article)
		summaryLabel.text = BabelLibrary.summary(for: article)
		summaryLabel.isHidden = summaryLabel.text == nil
		unreadDot.isHidden = article.status.read
		accessibilityLabel = "\(feedLabel.text ?? "")，\(titleLabel.text ?? "")，\(dateLabel.text ?? "")"
	}

	private static let relativeFormatter = RelativeDateTimeFormatter()
}
