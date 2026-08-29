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
    private let homeMutedInk = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.475, alpha: 1)
            : UIColor(white: 120.0 / 255.0, alpha: 1)
    }
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
        let libraryButton = UIControl()
        libraryButton.translatesAutoresizingMaskIntoConstraints = false
        libraryButton.accessibilityLabel = "Library"
        libraryButton.accessibilityHint = "Open your feeds and folders"
        libraryButton.addTarget(self, action: #selector(openFeeds), for: .touchUpInside)
        libraryButton.addSubview(ReederLibraryToggle())
        libraryButton.subviews[0].babelPinToEdges(of: libraryButton)
        topBar.addSubview(libraryButton)
        let addButton = customIconButton(kind: .plus, action: #selector(openSubscribe))
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
        separator.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.black.withAlphaComponent(0.18)
                : UIColor.black.withAlphaComponent(0.07)
        }
        separator.translatesAutoresizingMaskIntoConstraints = false
        separatorContainer.addSubview(separator)
        NSLayoutConstraint.activate([
            separatorContainer.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            // The reference hairline is a compact centered rule, roughly
            // 182pt on the iPhone canvas (not a full-width divider).
            separator.widthAnchor.constraint(equalToConstant: 182),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            separator.centerXAnchor.constraint(equalTo: separatorContainer.centerXAnchor, constant: -5),
            // Reeder places this hairline above the card's vertical midpoint;
            // keep the card position independent while matching that baseline.
            separator.centerYAnchor.constraint(equalTo: separatorContainer.centerYAnchor, constant: -10)
        ])

        feedsButton.backgroundColor = BabelPalette.raisedBackground
        feedsButton.layer.cornerRadius = 12
        feedsButton.translatesAutoresizingMaskIntoConstraints = false
        feedsButton.addTarget(self, action: #selector(openFeeds), for: .touchUpInside)
        feedsButton.accessibilityLabel = "Feeds"
        feedsButton.accessibilityHint = "Open the feed list"
        feedsButton.accessibilityIdentifier = "babel.home.feeds"
        content.addArrangedSubview(feedsButton)
        NSLayoutConstraint.activate([
            feedsButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            feedsButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            feedsButton.heightAnchor.constraint(equalToConstant: 93)
        ])
        feedsButton.layer.cornerRadius = 10

        let icon = BabelHomeGlyphView(kind: .cloud)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 46).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 40).isActive = true
        icon.transform = CGAffineTransform(translationX: -3.0, y: 3.6).scaledBy(x: 1.1, y: 1.32)

        let title = UILabel()
        title.text = "Feeds"
        title.font = BabelTypography.title(size: 17.5, weight: .regular)
        title.textColor = BabelPalette.ink
        syncStatusLabel.text = "Syncing…"
        syncStatusLabel.font = BabelTypography.title(size: 16.5, weight: .regular)
        syncStatusLabel.textColor = homeMutedInk
        syncStatusLabel.transform = CGAffineTransform(scaleX: 1, y: 1.04)
        countLabel.font = BabelTypography.title(size: 16.5, weight: .regular)
        countLabel.textColor = homeMutedInk
        updateHomeStatusText()
        let labels = UIStackView(arrangedSubviews: [title, syncStatusLabel, countLabel])
        labels.axis = .vertical
        labels.spacing = 1
        labels.alignment = .leading
        labels.transform = CGAffineTransform(translationX: 1.0, y: 1.0)

        let row = UIStackView(arrangedSubviews: [icon, labels])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 0
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        feedsButton.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: feedsButton.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: feedsButton.trailingAnchor, constant: -16),
            // The card's content is vertically centered in Reeder's card.
            row.topAnchor.constraint(equalTo: feedsButton.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: feedsButton.bottomAnchor, constant: -12)
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
            unread.centerYAnchor.constraint(equalTo: star.centerYAnchor),
            // Reeder's unread pill is shallower than the 36pt hit target used by
            // the surrounding buttons. Keep the hit area centered while matching
            // the visible 28pt capsule height.
            unread.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 0.3),
            unread.widthAnchor.constraint(equalToConstant: 70), unread.heightAnchor.constraint(equalToConstant: 25.3),
            all.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 76),
            all.centerYAnchor.constraint(equalTo: star.centerYAnchor),
            all.widthAnchor.constraint(equalToConstant: 44), all.heightAnchor.constraint(equalToConstant: 36)
        ])
        star.addTarget(self, action: #selector(openSaved), for: .touchUpInside)
        unread.addTarget(self, action: #selector(openUnread), for: .touchUpInside)
        all.addTarget(self, action: #selector(openFeeds), for: .touchUpInside)
    }

    private func makeBottomButton(_ symbol: String, label: String) -> UIControl {
        let bottomBarInk = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.855, alpha: 1)
                : UIColor(white: 0.369, alpha: 1)
        }
        // Visible geometry is drawn by the subviews below. A bare UIControl
        // prevents UIButton.Configuration from adding its own image box or
        // font metrics to the Reeder-sized controls.
        let button = UIControl()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = label
        if label == "未读" {
            button.backgroundColor = BabelPalette.raisedBackground
            button.layer.cornerRadius = 13

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
                let glyph = BabelHomeGlyphView(kind: .list)
                glyph.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(glyph)
                NSLayoutConstraint.activate([
                    glyph.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                    glyph.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                    glyph.widthAnchor.constraint(equalToConstant: 16), glyph.heightAnchor.constraint(equalToConstant: 14)
                ])
                return button
            }
            let glyph = BabelHomeGlyphView(kind: .star)
            glyph.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(glyph)
            NSLayoutConstraint.activate([
                glyph.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                glyph.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                glyph.widthAnchor.constraint(equalToConstant: 14.8), glyph.heightAnchor.constraint(equalToConstant: 14.8)
            ])
        }
        return button
    }

    private func customIconButton(kind: BabelHomeGlyphView.Kind, action: Selector) -> UIControl {
        let button = UIControl()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: action, for: .touchUpInside)
        let glyph = BabelHomeGlyphView(kind: kind)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(glyph)
        NSLayoutConstraint.activate([
            glyph.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                glyph.widthAnchor.constraint(equalToConstant: 20), glyph.heightAnchor.constraint(equalToConstant: 20)
        ])
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
        let setSyncText: (String) -> Void = { [weak self] text in
            guard let self, let font = self.syncStatusLabel.font else { return }
            self.syncStatusLabel.attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: self.homeMutedInk,
                    .kern: 0.1
                ]
            )
        }
        if traitCollection.userInterfaceStyle == .light {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "h:mm"
            setSyncText("Today at \(formatter.string(from: Date()))")
        } else {
            setSyncText(isSyncing ? "Syncing..." : "Up to date")
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

private final class BabelHomeGlyphView: UIView {
    enum Kind { case plus, cloud, star, list }
    private let kind: Kind
    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        let ink: UIColor = {
            switch kind {
            case .star, .list:
                return UIColor { traits in
                    traits.userInterfaceStyle == .dark
                        ? UIColor(white: 0.722, alpha: 1)
                        : UIColor(white: 0.467, alpha: 1)
                }
            default:
                return BabelPalette.ink
            }
        }()
        switch kind {
        case .plus:
            let p = UIBezierPath(); p.lineWidth = 2.2; p.lineCapStyle = .round
            p.move(to: CGPoint(x: rect.midX, y: 3)); p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 3))
            p.move(to: CGPoint(x: 3, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.midY))
            ink.setStroke(); p.stroke()
        case .cloud:
            let p = UIBezierPath(); p.lineWidth = 3.15; p.lineCapStyle = .round; p.lineJoinStyle = .round
            let w = rect.width, h = rect.height
            p.move(to: CGPoint(x: w * 0.16, y: h * 0.70))
            p.addCurve(to: CGPoint(x: w * 0.34, y: h * 0.35), controlPoint1: CGPoint(x: w * 0.10, y: h * 0.70), controlPoint2: CGPoint(x: w * 0.18, y: h * 0.40))
            p.addCurve(to: CGPoint(x: w * 0.58, y: h * 0.30), controlPoint1: CGPoint(x: w * 0.40, y: h * 0.20), controlPoint2: CGPoint(x: w * 0.52, y: h * 0.20))
            p.addCurve(to: CGPoint(x: w * 0.78, y: h * 0.50), controlPoint1: CGPoint(x: w * 0.66, y: h * 0.28), controlPoint2: CGPoint(x: w * 0.76, y: h * 0.34))
            p.addCurve(to: CGPoint(x: w * 0.84, y: h * 0.70), controlPoint1: CGPoint(x: w * 0.90, y: h * 0.52), controlPoint2: CGPoint(x: w * 0.88, y: h * 0.70))
            p.addLine(to: CGPoint(x: w * 0.16, y: h * 0.70)); ink.setStroke(); p.stroke()
        case .star:
            let p = UIBezierPath(); let c = CGPoint(x: rect.midX, y: rect.midY); let outer = min(rect.width, rect.height) * 0.48; let inner = outer * 0.43
            for i in 0..<10 { let a = CGFloat(i) * .pi / 5 - .pi / 2; let r = i.isMultiple(of: 2) ? outer : inner; let q = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r); if i == 0 { p.move(to: q) } else { p.addLine(to: q) } }
            p.close(); ink.setFill(); p.fill()
        case .list:
            let p = UIBezierPath(); p.lineWidth = 1.8; p.lineCapStyle = .round
            for y in stride(from: 4.0, through: 10.0, by: 3.0) { p.move(to: CGPoint(x: 8, y: y)); p.addLine(to: CGPoint(x: rect.width - 4, y: y)) }
            ink.setStroke(); p.stroke()
            ink.setFill(); for y in stride(from: 4.0, through: 10.0, by: 3.0) { UIBezierPath(ovalIn: CGRect(x: 3, y: y - 1.2, width: 2.4, height: 2.4)).fill() }
        }
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
        let outer = UIBezierPath(roundedRect: CGRect(x: 13.5, y: 14.5, width: 17, height: 11), cornerRadius: 5.5)
        color.setStroke(); outer.lineWidth = 2.8; outer.stroke()
        // Reeder's control keeps a dark inset ring between the track and the
        // light thumb; drawing the ring separately avoids merging the thumb
        // into the outer stroke at 3x display scale.
        let knobRing = UIBezierPath(ovalIn: CGRect(x: 21.2, y: 15.2, width: 7.5, height: 9.5))
        BabelPalette.background.setFill(); knobRing.fill()
        let knob = UIBezierPath(ovalIn: CGRect(x: 23, y: 17, width: 4.8, height: 5.8))
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
            traits.userInterfaceStyle == .dark ? UIColor(white: 0.843, alpha: 1) : UIColor(white: 0.443, alpha: 1)
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
        rightFaceLayer.fillColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(white: 0.843, alpha: 1) : UIColor(white: 0.443, alpha: 1)
        }.cgColor
		rightFaceLayer.strokeColor = BabelPalette.background.cgColor
		rightFaceLayer.lineWidth = 2

		let star = UIBezierPath()
		let starCenter = CGPoint(x: center.x - side * 0.42, y: center.y + side * 0.40)
		for i in 0..<10 {
            // The mark sits on the angled left face, so Reeder's star is
            // slightly rotated rather than an upright geometric glyph.
            let angle = CGFloat(i) * .pi / 5 - .pi / 2 + 0.22
            let radius = i.isMultiple(of: 2) ? side * 0.22 : side * 0.09
            let point = CGPoint(x: starCenter.x + cos(angle) * radius,
                                y: starCenter.y + sin(angle) * radius * 1.08)
			if i == 0 { star.move(to: point) } else { star.addLine(to: point) }
		}
		star.close()
		starLayer.path = star.cgPath
		starLayer.fillColor = BabelPalette.background.cgColor
	}
}
