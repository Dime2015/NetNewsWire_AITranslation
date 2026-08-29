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
    private var isSyncing = true

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: BabelHomeViewController, _) in
            self.updateHomeStatusText()
        }
        startObserving()
        reloadSnapshot()
    }

    deinit {
        loadTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    private func configureView() {
        view.backgroundColor = BabelPalette.background
        navigationController?.setNavigationBarHidden(true, animated: false)

        // Reeder's home has only the compact library toggle and add button in its top row.
        let topBar = UIView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)
        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 0),
            topBar.heightAnchor.constraint(equalToConstant: 48)
        ])
        let libraryButton = UIButton(type: .custom)
        libraryButton.translatesAutoresizingMaskIntoConstraints = false
        libraryButton.accessibilityLabel = "Library"
        libraryButton.accessibilityHint = "Open your feeds and folders"
        libraryButton.addTarget(self, action: #selector(openFeeds), for: .touchUpInside)
        libraryButton.addSubview(ReederLibraryToggle())
        libraryButton.subviews[0].babelPinToEdges(of: libraryButton)
        topBar.addSubview(libraryButton)
        let addButton = navigationButton(image: UIImage(systemName: "plus"), action: #selector(openSubscribe))
        addButton.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .regular), forImageIn: .normal)
        addButton.accessibilityLabel = "Add Subscription"
        addButton.tintColor = BabelPalette.ink
        topBar.addSubview(addButton)
        NSLayoutConstraint.activate([
            libraryButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            libraryButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            libraryButton.widthAnchor.constraint(equalToConstant: 44), libraryButton.heightAnchor.constraint(equalToConstant: 44),
            addButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            addButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor, constant: -2),
            addButton.widthAnchor.constraint(equalToConstant: 44), addButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 8),
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
        logo.heightAnchor.constraint(equalToConstant: 130).isActive = true
        content.addArrangedSubview(logo)

        let separatorContainer = UIView()
        separatorContainer.translatesAutoresizingMaskIntoConstraints = false
        content.addArrangedSubview(separatorContainer)
        let separator = UIView()
        separator.backgroundColor = BabelPalette.hairline
        separator.translatesAutoresizingMaskIntoConstraints = false
        separatorContainer.addSubview(separator)
        NSLayoutConstraint.activate([
            separatorContainer.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            separator.widthAnchor.constraint(equalToConstant: 360),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            separator.centerXAnchor.constraint(equalTo: separatorContainer.centerXAnchor),
            // Reeder places this hairline above the card's vertical midpoint;
            // keep the card position independent while matching that baseline.
            separator.centerYAnchor.constraint(equalTo: separatorContainer.centerYAnchor, constant: -30)
        ])

        feedsButton.backgroundColor = BabelPalette.raisedBackground
        feedsButton.layer.cornerRadius = 12
        feedsButton.translatesAutoresizingMaskIntoConstraints = false
        feedsButton.addTarget(self, action: #selector(openFeeds), for: .touchUpInside)
        feedsButton.accessibilityLabel = "Feeds"
        feedsButton.accessibilityHint = "Open the feed list"
        content.addArrangedSubview(feedsButton)
        NSLayoutConstraint.activate([
            feedsButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            feedsButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            feedsButton.heightAnchor.constraint(equalToConstant: 93)
        ])
        feedsButton.layer.cornerRadius = 10

        let cloudConfiguration = UIImage.SymbolConfiguration(pointSize: 42, weight: .bold)
        let icon = UIImageView(image: UIImage(systemName: "cloud", withConfiguration: cloudConfiguration))
        icon.tintColor = BabelPalette.ink
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let title = UILabel()
        title.text = "Feeds"
        title.font = BabelTypography.title(size: 18, weight: .medium)
        title.textColor = BabelPalette.ink
        syncStatusLabel.text = "Syncing…"
        syncStatusLabel.font = BabelTypography.title(size: 14, weight: .regular)
        syncStatusLabel.textColor = BabelPalette.mutedInk
        countLabel.font = BabelTypography.title(size: 14, weight: .regular)
        countLabel.textColor = BabelPalette.mutedInk
        updateHomeStatusText()
        let labels = UIStackView(arrangedSubviews: [title, syncStatusLabel, countLabel])
        labels.axis = .vertical
        labels.spacing = 1
        labels.alignment = .leading

        let row = UIStackView(arrangedSubviews: [icon, labels])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 4
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        feedsButton.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: feedsButton.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: feedsButton.trailingAnchor, constant: -16),
            // The card's content is vertically centered in Reeder's card.
            row.topAnchor.constraint(equalTo: feedsButton.topAnchor, constant: 15),
            row.bottomAnchor.constraint(equalTo: feedsButton.bottomAnchor, constant: -5)
        ])

        statusLabel.isHidden = true
        content.setCustomSpacing(8, after: logo)
        content.setCustomSpacing(20, after: separatorContainer)

        let star = makeBottomButton("star", label: "已收藏")
        let unread = makeBottomButton("circle.fill", label: "未读")
        let all = makeBottomButton("list.bullet", label: "全部")
        [star, unread, all].forEach { view.addSubview($0) }
        NSLayoutConstraint.activate([
            star.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: -76),
            star.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -22),
            star.widthAnchor.constraint(equalToConstant: 44), star.heightAnchor.constraint(equalToConstant: 36),
            unread.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            unread.centerYAnchor.constraint(equalTo: star.centerYAnchor),
            // Reeder's unread pill is shallower than the 36pt hit target used by
            // the surrounding buttons. Keep the hit area centered while matching
            // the visible 28pt capsule height.
            unread.widthAnchor.constraint(equalToConstant: 76), unread.heightAnchor.constraint(equalToConstant: 28),
            all.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 76),
            all.centerYAnchor.constraint(equalTo: star.centerYAnchor),
            all.widthAnchor.constraint(equalToConstant: 44), all.heightAnchor.constraint(equalToConstant: 36)
        ])
        star.addTarget(self, action: #selector(openSaved), for: .touchUpInside)
        unread.addTarget(self, action: #selector(openUnread), for: .touchUpInside)
        all.addTarget(self, action: #selector(openFeeds), for: .touchUpInside)
    }

    private func makeBottomButton(_ symbol: String, label: String) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        let bottomBarInk = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.78, alpha: 1)
                : UIColor(white: 0.43, alpha: 1)
        }
        configuration.baseForegroundColor = bottomBarInk
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = label
        if label == "未读" {
            var unreadConfiguration = configuration
            unreadConfiguration.background.backgroundColor = BabelPalette.raisedBackground
            unreadConfiguration.background.cornerRadius = 18
            button.configuration = unreadConfiguration

            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.backgroundColor = bottomBarInk
            dot.layer.cornerRadius = 5
            button.addSubview(dot)
            let title = UILabel()
            title.translatesAutoresizingMaskIntoConstraints = false
            title.text = "UNREAD"
            title.textColor = bottomBarInk
            title.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
            title.adjustsFontSizeToFitWidth = true
            title.minimumScaleFactor = 0.8
            button.addSubview(title)
            NSLayoutConstraint.activate([
                dot.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 10),
                dot.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                dot.widthAnchor.constraint(equalToConstant: 10),
                dot.heightAnchor.constraint(equalToConstant: 10),
                title.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
                title.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -5),
                title.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
        } else {
            if symbol == "list.bullet" {
                var listConfiguration = configuration
                // Reeder's compact list glyph is visibly smaller than the default
                // UIButton image box on the 3x iPhone canvas.
                listConfiguration.image = UIImage(systemName: "list.bullet", withConfiguration: UIImage.SymbolConfiguration(pointSize: 7, weight: .regular))
                button.configuration = listConfiguration
                return button
            }
            var starConfiguration = configuration
            starConfiguration.image = UIImage(systemName: "star.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular))
            button.configuration = starConfiguration
        }
        return button
    }

    private func navigationButton(image: UIImage?, action: Selector) -> UIButton {
        let button = UIButton(type: .custom)
        button.preferredBehavioralStyle = .pad
        button.setImage(image, for: .normal)
        button.tintColor = BabelPalette.ink
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
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
    @objc private func syncDidBegin() { isSyncing = true; updateHomeStatusText() }
    @objc private func syncDidFinish() { isSyncing = false; updateHomeStatusText() }

    private func updateHomeStatusText() {
        if traitCollection.userInterfaceStyle == .light {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "h:mm"
            syncStatusLabel.text = "Today at \(formatter.string(from: Date()))"
        } else {
            syncStatusLabel.text = isSyncing ? "Syncing…" : "Up to date"
        }
    }

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

private final class ReederLibraryToggle: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        let color = BabelPalette.ink
        let outer = UIBezierPath(roundedRect: CGRect(x: 13, y: 14, width: 18, height: 12), cornerRadius: 6)
        color.setStroke(); outer.lineWidth = 3; outer.stroke()
        let knob = UIBezierPath(ovalIn: CGRect(x: 25, y: 16, width: 7, height: 8))
        color.setFill(); knob.fill()
    }
}

private final class BabelCubeView: UIView {
	private let cubeLayer = CAShapeLayer()
	private let rightFaceLayer = CAShapeLayer()
	private let starLayer = CAShapeLayer()

	override init(frame: CGRect) {
		super.init(frame: frame)
		isUserInteractionEnabled = false
		layer.addSublayer(cubeLayer)
		layer.addSublayer(rightFaceLayer)
		layer.addSublayer(starLayer)
	}
	required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

	override func layoutSubviews() {
		super.layoutSubviews()
		let side = min(bounds.width, bounds.height) * 0.30
		let center = CGPoint(x: bounds.midX - 5, y: bounds.midY - 30)
		let top = CGPoint(x: center.x, y: center.y - side * 0.58)
		let left = CGPoint(x: center.x - side * 0.88, y: center.y - side * 0.10)
		let right = CGPoint(x: center.x + side * 0.88, y: center.y - side * 0.10)
		let bottom = CGPoint(x: center.x, y: center.y + side * 1.24)
		let leftBottom = CGPoint(x: left.x + 2, y: left.y + side * 0.94)
		let rightBottom = CGPoint(x: right.x - 2, y: right.y + side * 0.94)
		let seam = CGPoint(x: center.x, y: center.y + side * 0.12)

		let path = UIBezierPath()
		path.move(to: top); path.addLine(to: right); path.addLine(to: seam); path.addLine(to: left); path.close()
		path.move(to: left); path.addLine(to: seam); path.addLine(to: bottom); path.addLine(to: leftBottom); path.close()
		path.move(to: seam); path.addLine(to: right); path.addLine(to: rightBottom); path.addLine(to: bottom); path.close()
		cubeLayer.path = path.cgPath
		cubeLayer.fillRule = .evenOdd
		cubeLayer.fillColor = UIColor { traits in
			traits.userInterfaceStyle == .dark ? UIColor(white: 0.82, alpha: 1) : UIColor(white: 0.45, alpha: 1)
		}.cgColor
		cubeLayer.strokeColor = BabelPalette.background.cgColor
		cubeLayer.lineWidth = 2
		let rightFace = UIBezierPath()
		rightFace.move(to: seam)
		rightFace.addLine(to: right)
		rightFace.addLine(to: rightBottom)
		rightFace.addLine(to: bottom)
		rightFace.close()
		rightFaceLayer.path = rightFace.cgPath
		rightFaceLayer.fillColor = UIColor(white: 0.82, alpha: 1).cgColor
		rightFaceLayer.strokeColor = BabelPalette.background.cgColor
		rightFaceLayer.lineWidth = 2

		let star = UIBezierPath()
		let starCenter = CGPoint(x: center.x - side * 0.42, y: center.y + side * 0.40)
		for i in 0..<10 {
			let angle = CGFloat(i) * .pi / 5 - .pi / 2
			let radius = i.isMultiple(of: 2) ? side * 0.22 : side * 0.09
			let point = CGPoint(x: starCenter.x + cos(angle) * radius, y: starCenter.y + sin(angle) * radius)
			if i == 0 { star.move(to: point) } else { star.addLine(to: point) }
		}
		star.close()
		starLayer.path = star.cgPath
		starLayer.fillColor = BabelPalette.background.cgColor
	}
}
