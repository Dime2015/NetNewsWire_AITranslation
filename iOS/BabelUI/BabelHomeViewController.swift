//
//  BabelHomeViewController.swift
//  NetNewsWire
//

import UIKit
import Account
import Articles

final class BabelHomeViewController: UIViewController {
    var onSelectSection: ((BabelLibrarySection) -> Void)?
    var onSelectArticle: ((Article) -> Void)?
    var onOpenFeeds: (() -> Void)?
    var onOpenSubscribe: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenGenesisV2: (() -> Void)?

    private let countLabel = UILabel()
    private let syncStatusLabel = UILabel()
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
        let switcher = UISegmentedControl(items: ["Babel", "旧版"])
        switcher.selectedSegmentIndex = 0
        switcher.addTarget(self, action: #selector(switchInterface(_:)), for: .valueChanged)
        navigationItem.titleView = switcher
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain, target: self, action: #selector(openSettings)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(openSubscribe)
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

        let logo = BabelCubeView()
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
        syncStatusLabel.text = "Syncing…"
        syncStatusLabel.font = BabelTypography.title(size: 17, weight: .regular)
        syncStatusLabel.textColor = BabelPalette.mutedInk
        countLabel.font = BabelTypography.title(size: 17, weight: .regular)
        countLabel.textColor = BabelPalette.mutedInk
        let labels = UIStackView(arrangedSubviews: [title, syncStatusLabel, countLabel])
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
        configuration.imagePlacement = .all
        configuration.baseForegroundColor = BabelPalette.mutedInk
        if label == "未读" {
            configuration.imagePlacement = .leading
            configuration.imagePadding = 8
            configuration.attributedTitle = AttributedString("UNREAD", attributes: AttributeContainer([
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold)
            ]))
            configuration.background = .listPlainCell()
            configuration.background.backgroundColor = BabelPalette.raisedBackground
            configuration.background.cornerRadius = 28
        }
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = label
        button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        return button
    }

    private func startObserving() {
        for name in [Notification.Name.UnreadCountDidChange, .AccountDidDownloadArticles,
                     .UserDidAddAccount, .UserDidDeleteAccount, .nnwTitleTranslationDidUpdate] {
            NotificationCenter.default.addObserver(self, selector: #selector(dataDidChange), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(syncDidBegin), name: .AccountRefreshDidBegin, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(syncDidFinish), name: .AccountRefreshDidFinish, object: nil)
    }

    @objc private func dataDidChange() { reloadSnapshot() }
    @objc private func syncDidBegin() { syncStatusLabel.text = "Syncing…" }
    @objc private func syncDidFinish() { syncStatusLabel.text = "Up to date" }

    private func reloadSnapshot() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let snapshot = await BabelLibrary.loadHomeSnapshot()
            guard !Task.isCancelled else { return }
            self?.countLabel.text = "\((snapshot.counts[.unread] ?? 0).formatted()) Unread Items"
            self?.statusLabel.text = "\(snapshot.accountCount) 个账户 · \(snapshot.feedCount) 个订阅源"
        }
    }

    @objc private func openFeeds() { onOpenFeeds?() }
    @objc private func openUnread() { onSelectSection?(.unread) }
    @objc private func openSaved() { onSelectSection?(.saved) }
    @objc private func openGenesisV2() { onOpenGenesisV2?() }
    @objc private func openSubscribe() { onOpenSubscribe?() }
    @objc private func openSettings() { onOpenSettings?() }

    @objc private func switchInterface(_ sender: UISegmentedControl) {
        if sender.selectedSegmentIndex == 1 { onOpenGenesisV2?() }
    }
}

private final class BabelCubeView: UIView {
	private let cubeLayer = CAShapeLayer()
	private let starLayer = CAShapeLayer()

	override init(frame: CGRect) {
		super.init(frame: frame)
		isUserInteractionEnabled = false
		layer.addSublayer(cubeLayer)
		layer.addSublayer(starLayer)
	}
	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	override func layoutSubviews() {
		super.layoutSubviews()
		let side = min(bounds.width, bounds.height) * 0.34
		let center = CGPoint(x: bounds.midX, y: bounds.midY + 2)
		let top = CGPoint(x: center.x, y: center.y - side * 0.58)
		let left = CGPoint(x: center.x - side * 0.88, y: center.y - side * 0.10)
		let right = CGPoint(x: center.x + side * 0.88, y: center.y - side * 0.10)
		let bottom = CGPoint(x: center.x, y: center.y + side * 0.52)
		let leftBottom = CGPoint(x: left.x + 2, y: left.y + side * 0.94)
		let rightBottom = CGPoint(x: right.x - 2, y: right.y + side * 0.94)
		let seam = CGPoint(x: center.x, y: center.y + side * 0.12)

		let path = UIBezierPath()
		path.move(to: top); path.addLine(to: right); path.addLine(to: seam); path.addLine(to: left); path.close()
		path.move(to: left); path.addLine(to: seam); path.addLine(to: bottom); path.addLine(to: leftBottom); path.close()
		path.move(to: seam); path.addLine(to: right); path.addLine(to: rightBottom); path.addLine(to: bottom); path.close()
		cubeLayer.path = path.cgPath
		cubeLayer.fillColor = UIColor { traits in
			traits.userInterfaceStyle == .dark ? UIColor(white: 0.82, alpha: 1) : UIColor(white: 0.45, alpha: 1)
		}.cgColor
		cubeLayer.strokeColor = BabelPalette.background.cgColor
		cubeLayer.lineWidth = 2

		let star = UIBezierPath()
		let starCenter = CGPoint(x: center.x - side * 0.42, y: center.y + side * 0.25)
		for i in 0..<10 {
			let angle = CGFloat(i) * .pi / 5 - .pi / 2
			let radius = i.isMultiple(of: 2) ? side * 0.26 : side * 0.11
			let point = CGPoint(x: starCenter.x + cos(angle) * radius, y: starCenter.y + sin(angle) * radius)
			if i == 0 { star.move(to: point) } else { star.addLine(to: point) }
		}
		star.close()
		starLayer.path = star.cgPath
		starLayer.fillColor = BabelPalette.background.cgColor
	}
}
