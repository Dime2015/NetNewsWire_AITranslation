//
//  BabelHomeViewController.swift
//  NetNewsWire
//

import UIKit
import Articles

final class BabelHomeViewController: UIViewController {
    var onSelectSection: ((BabelLibrarySection) -> Void)?
    var onSelectArticle: ((Article) -> Void)?
    var onOpenFeeds: (() -> Void)?
    var onOpenGenesisV2: (() -> Void)?

    private let countLabel = UILabel()
    private let statusLabel = UILabel()
    private let feedsButton = UIControl()
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
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "eye.slash"),
            style: .plain, target: self, action: #selector(openGenesisV2)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(openGenesisV2)
        )

        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let content = UIStackView()
        content.axis = .vertical
        content.alignment = .fill
        content.spacing = 0
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])

        let logo = UIImageView(image: UIImage(systemName: "cube"))
        logo.tintColor = BabelPalette.ink
        logo.contentMode = .scaleAspectFit
        logo.heightAnchor.constraint(equalToConstant: 150).isActive = true
        content.addArrangedSubview(logo)

        feedsButton.backgroundColor = BabelPalette.raisedBackground
        feedsButton.layer.cornerRadius = 12
        feedsButton.translatesAutoresizingMaskIntoConstraints = false
        feedsButton.addTarget(self, action: #selector(openFeeds), for: .touchUpInside)
        content.addArrangedSubview(feedsButton)
        NSLayoutConstraint.activate([
            feedsButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            feedsButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            feedsButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 118)
        ])

        let icon = UIImageView(image: UIImage(systemName: "cloud"))
        icon.tintColor = BabelPalette.ink
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 52).isActive = true

        let title = UILabel()
        title.text = "Feeds"
        title.font = BabelTypography.title(size: 24)
        title.textColor = BabelPalette.ink
        let today = UILabel()
        today.text = "Today"
        today.font = BabelTypography.title(size: 17, weight: .regular)
        today.textColor = BabelPalette.mutedInk
        countLabel.font = BabelTypography.title(size: 17, weight: .regular)
        countLabel.textColor = BabelPalette.mutedInk
        let labels = UIStackView(arrangedSubviews: [title, today, countLabel])
        labels.axis = .vertical
        labels.spacing = 1
        labels.alignment = .leading

        let row = UIStackView(arrangedSubviews: [icon, labels])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 16
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        feedsButton.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: feedsButton.leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: feedsButton.trailingAnchor, constant: -18),
            row.topAnchor.constraint(equalTo: feedsButton.topAnchor, constant: 16),
            row.bottomAnchor.constraint(equalTo: feedsButton.bottomAnchor, constant: -16)
        ])

        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.font = UIFont.systemFont(ofSize: 11)
        statusLabel.textColor = BabelPalette.mutedInk
        content.addArrangedSubview(statusLabel)
        content.setCustomSpacing(44, after: feedsButton)
        content.setCustomSpacing(14, after: logo)

        let bottom = UIStackView()
        bottom.axis = .horizontal
        bottom.distribution = .equalCentering
        bottom.alignment = .center
        bottom.layoutMargins = UIEdgeInsets(top: 12, left: 56, bottom: 18, right: 56)
        bottom.isLayoutMarginsRelativeArrangement = true
        let star = makeBottomButton("star", label: "已收藏")
        let unread = makeBottomButton("circle.fill", label: "未读")
        let all = makeBottomButton("list.bullet", label: "全部")
        bottom.addArrangedSubview(star)
        bottom.addArrangedSubview(unread)
        bottom.addArrangedSubview(all)
        content.addArrangedSubview(bottom)
        star.addTarget(self, action: #selector(openSaved), for: .touchUpInside)
        unread.addTarget(self, action: #selector(openUnread), for: .touchUpInside)
        all.addTarget(self, action: #selector(openFeeds), for: .touchUpInside)
    }

    private func makeBottomButton(_ symbol: String, label: String) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePlacement = .top
        configuration.imagePadding = 3
        configuration.baseForegroundColor = BabelPalette.mutedInk
        configuration.attributedTitle = AttributedString(label, attributes: AttributeContainer([
            .font: UIFont.systemFont(ofSize: 10)
        ]))
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = label
        return button
    }

    private func startObserving() {
        for name in [Notification.Name.UnreadCountDidChange, .AccountDidDownloadArticles,
                     .UserDidAddAccount, .UserDidDeleteAccount, .nnwTitleTranslationDidUpdate] {
            NotificationCenter.default.addObserver(self, selector: #selector(dataDidChange), name: name, object: nil)
        }
    }

    @objc private func dataDidChange() { reloadSnapshot() }

    private func reloadSnapshot() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let snapshot = await BabelLibrary.loadHomeSnapshot()
            guard !Task.isCancelled else { return }
            self?.countLabel.text = "\(snapshot.counts[.unread] ?? 0) Unread Items"
            self?.statusLabel.text = "\(snapshot.accountCount) 个账户 · \(snapshot.feedCount) 个订阅源"
        }
    }

    @objc private func openFeeds() { onOpenFeeds?() }
    @objc private func openUnread() { onSelectSection?(.unread) }
    @objc private func openSaved() { onSelectSection?(.saved) }
    @objc private func openGenesisV2() { onOpenGenesisV2?() }
}
