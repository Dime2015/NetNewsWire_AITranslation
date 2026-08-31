//
//  BabelArticleSearchViewController.swift
//  NetNewsWire
//
//  搜索保持在当前时间线内：作为子控制器覆盖列表，而不是跳到新的导航路由。
//

import UIKit
import Articles

final class BabelArticleSearchViewController: UIViewController, UITextFieldDelegate, UITableViewDataSource, UITableViewDelegate {

	var onDismiss: (() -> Void)?
	var onSelectArticle: ((Article) -> Void)?

	private let sourceTitle: String
	private let sourceArticles: [Article]
	private let searchField = UITextField()
	private let tableView = UITableView(frame: .zero, style: .plain)
	private let emptyLabel = UILabel()
	private var results = [Article]()

	init(sourceTitle: String, articles: [Article]) {
		self.sourceTitle = sourceTitle
		self.sourceArticles = articles
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	override func viewDidLoad() {
		super.viewDidLoad()
		view.backgroundColor = BabelPalette.background
		configureHeader()
		configureResults()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		searchField.becomeFirstResponder()
	}

	private func configureHeader() {
		let nav = UIView()
		nav.backgroundColor = BabelPalette.background
		nav.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(nav)
		let close = UIButton(type: .custom)
		close.tintColor = BabelPalette.ink
		close.setImage(UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
		close.accessibilityLabel = "取消搜索"
		close.addTarget(self, action: #selector(dismissSearch), for: .touchUpInside)
		close.translatesAutoresizingMaskIntoConstraints = false
		nav.addSubview(close)
		let title = UILabel()
		title.text = "搜索"
		title.font = .systemFont(ofSize: 24, weight: .semibold)
		title.textColor = BabelPalette.ink
		title.translatesAutoresizingMaskIntoConstraints = false
		nav.addSubview(title)
		let separator = UIView()
		separator.backgroundColor = BabelPalette.hairline
		separator.translatesAutoresizingMaskIntoConstraints = false
		nav.addSubview(separator)

		let placeholder = "搜索 " + sourceTitle
		searchField.placeholder = placeholder
		searchField.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: BabelPalette.tertiaryInk])
		searchField.font = .systemFont(ofSize: 16, weight: .regular)
		searchField.textColor = BabelPalette.ink
		searchField.backgroundColor = BabelPalette.raisedBackground
		searchField.layer.cornerRadius = 8
		searchField.clearButtonMode = .whileEditing
		searchField.returnKeyType = .search
		searchField.autocorrectionType = .no
		searchField.delegate = self
		searchField.addTarget(self, action: #selector(searchTextChanged), for: .editingChanged)
		searchField.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(searchField)

		NSLayoutConstraint.activate([
			nav.leadingAnchor.constraint(equalTo: view.leadingAnchor), nav.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			// Timeline already owns its top safe-area treatment; search replaces that chrome in place.
			nav.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), nav.heightAnchor.constraint(equalToConstant: 58),
			close.leadingAnchor.constraint(equalTo: nav.leadingAnchor, constant: 10), close.centerYAnchor.constraint(equalTo: nav.topAnchor, constant: 24), close.widthAnchor.constraint(equalToConstant: 44), close.heightAnchor.constraint(equalToConstant: 44),
			title.leadingAnchor.constraint(equalTo: nav.leadingAnchor, constant: 58), title.topAnchor.constraint(equalTo: nav.topAnchor, constant: 7),
			separator.leadingAnchor.constraint(equalTo: nav.leadingAnchor), separator.trailingAnchor.constraint(equalTo: nav.trailingAnchor), separator.bottomAnchor.constraint(equalTo: nav.bottomAnchor), separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
			searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), searchField.topAnchor.constraint(equalTo: nav.bottomAnchor, constant: 14), searchField.heightAnchor.constraint(equalToConstant: 44)
		])
	}

	private func configureResults() {
		tableView.backgroundColor = BabelPalette.background
		tableView.separatorStyle = .none
		tableView.rowHeight = 86
		tableView.estimatedRowHeight = 86
		tableView.dataSource = self
		tableView.delegate = self
		tableView.register(BabelSearchResultCell.self, forCellReuseIdentifier: BabelSearchResultCell.reuseIdentifier)
		tableView.translatesAutoresizingMaskIntoConstraints = false
		view.addSubview(tableView)
		emptyLabel.text = "输入关键词，搜索当前列表"
		emptyLabel.font = .systemFont(ofSize: 16, weight: .regular)
		emptyLabel.textColor = BabelPalette.mutedInk
		emptyLabel.textAlignment = .center
		tableView.backgroundView = emptyLabel
		NSLayoutConstraint.activate([
			tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
			tableView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14), tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
		])
	}

	@objc private func searchTextChanged() {
		let query = searchField.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
		guard !query.isEmpty else {
			results = []
			emptyLabel.text = "输入关键词，搜索当前列表"
			tableView.reloadData()
			return
		}
		results = sourceArticles.filter { article in
			[article.title, article.summary, article.contentText, article.feed?.nameForDisplay]
				.compactMap { $0?.lowercased() }
				.joined(separator: " ")
				.contains(query)
		}
		emptyLabel.text = "没有匹配的文章"
		tableView.reloadData()
	}

	func numberOfSections(in tableView: UITableView) -> Int { results.isEmpty ? 0 : 1 }
	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { results.count }
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: BabelSearchResultCell.reuseIdentifier, for: indexPath) as! BabelSearchResultCell
		cell.configure(article: results[indexPath.row])
		return cell
	}
	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		onSelectArticle?(results[indexPath.row])
	}
	func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); return true }
	@objc private func dismissSearch() { onDismiss?() }
}

private final class BabelSearchResultCell: UITableViewCell {
	static let reuseIdentifier = "BabelSearchResultCell"
	private let feedLabel = UILabel()
	private let titleLabel = UILabel()
	private let summaryLabel = UILabel()
	private let line = UIView()

	override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
		super.init(style: style, reuseIdentifier: reuseIdentifier)
		backgroundColor = .clear
		selectedBackgroundView = { let view = UIView(); view.backgroundColor = BabelPalette.raisedBackground; return view }()
		feedLabel.font = .systemFont(ofSize: 10, weight: .regular)
		feedLabel.textColor = BabelPalette.mutedInk
		feedLabel.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(feedLabel)
		titleLabel.font = .systemFont(ofSize: 16, weight: .regular)
		titleLabel.textColor = BabelPalette.ink
		titleLabel.numberOfLines = 2
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(titleLabel)
		summaryLabel.font = .systemFont(ofSize: 13, weight: .regular)
		summaryLabel.textColor = BabelPalette.mutedInk
		summaryLabel.numberOfLines = 1
		summaryLabel.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(summaryLabel)
		line.backgroundColor = BabelPalette.hairline
		line.translatesAutoresizingMaskIntoConstraints = false
		contentView.addSubview(line)
		NSLayoutConstraint.activate([
			feedLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), feedLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), feedLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
			titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), titleLabel.topAnchor.constraint(equalTo: feedLabel.bottomAnchor, constant: 3),
			summaryLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), summaryLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), summaryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
			line.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), line.trailingAnchor.constraint(equalTo: contentView.trailingAnchor), line.bottomAnchor.constraint(equalTo: contentView.bottomAnchor), line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
		])
	}

	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
	func configure(article: Article) {
		feedLabel.text = article.feed?.nameForDisplay.uppercased() ?? "订阅文章"
		titleLabel.text = article.title ?? "未命名文章"
		summaryLabel.text = article.summary ?? article.contentText
	}
}
