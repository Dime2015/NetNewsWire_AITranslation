//
//  BabelDesignSystem.swift
//  NetNewsWire
//
//  Reeder Classic 参考母版的基础令牌。只描述壳和静态页面。
//

import UIKit

enum BabelPalette {
    static let background = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 28.0 / 255.0, green: 28.0 / 255.0, blue: 28.0 / 255.0, alpha: 1)
            : UIColor(red: 245.0 / 255.0, green: 242.0 / 255.0, blue: 241.0 / 255.0, alpha: 1)
    }
    static let raisedBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 46.0 / 255.0, green: 46.0 / 255.0, blue: 46.0 / 255.0, alpha: 1)
            : UIColor(red: 216.0 / 255.0, green: 213.0 / 255.0, blue: 214.0 / 255.0, alpha: 1)
    }
    static let ink = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 216.0 / 255.0, green: 216.0 / 255.0, blue: 216.0 / 255.0, alpha: 1)
            : UIColor(red: 58.0 / 255.0, green: 58.0 / 255.0, blue: 58.0 / 255.0, alpha: 1)
    }
    static let mutedInk = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 108.0 / 255.0, green: 108.0 / 255.0, blue: 108.0 / 255.0, alpha: 1)
            : UIColor(red: 120.0 / 255.0, green: 120.0 / 255.0, blue: 120.0 / 255.0, alpha: 1)
    }
    static let tertiaryInk = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 142.0 / 255.0, green: 142.0 / 255.0, blue: 142.0 / 255.0, alpha: 1)
            : UIColor(red: 163.0 / 255.0, green: 160.0 / 255.0, blue: 161.0 / 255.0, alpha: 1)
    }
    static let hairline = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor(red: 224.0 / 255.0, green: 221.0 / 255.0, blue: 221.0 / 255.0, alpha: 1)
    }
    /// The user-selected theme colour is intentionally reserved for settings
    /// switches and the reader progress ring. Selection elsewhere uses the
    /// neutral raised/muted palette instead of introducing coloured states.
    static var themeAccent: UIColor { NNWAccentPalette.live }
}

enum BabelTypography {
    static func display(size: CGFloat) -> UIFont { UIFont.systemFont(ofSize: size, weight: .bold) }
    static func title(size: CGFloat = 20, weight: UIFont.Weight = .semibold) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }
    static func reading(size: CGFloat = 18) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: .regular)
    }
}

enum BabelChromeMetrics {
    static let referenceCanvasWidth: CGFloat = 402
    static let topControlCenterY: CGFloat = 22
    static let bottomToolbarHeight: CGFloat = 72
    static let bottomControlCenterY: CGFloat = 24
    static let topSlots: [CGFloat] = [32, 201, 290, 330, 370]
    static let bottomSlots: [CGFloat] = [32, 104, 201, 290.5, 362]
    static let minimumHitTarget: CGFloat = 44
    static let bottomIconPointSize: CGFloat = 20
    static let selectionDuration: TimeInterval = 0.18

    static func bottomSymbol(_ name: String, weight: UIImage.SymbolWeight = .regular) -> UIImage? {
        UIImage(
            systemName: name,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: bottomIconPointSize, weight: weight)
        )
    }
}

enum BabelArticleFilter: CaseIterable, Hashable {
    case starred
    case unread
    case all

    var title: String {
        switch self {
        case .starred: "STARRED"
        case .unread: "UNREAD"
        case .all: "ALL"
        }
    }

    var selectedWidth: CGFloat {
        switch self {
        case .starred: 90
        case .unread: 78
        case .all: 68
        }
    }
}

final class BabelFilterControl: UIControl {
    let filter: BabelArticleFilter
	var usesExternalSelectionPill = false {
		didSet { updateAppearance() }
	}

    private let pillView = UIView()
    private let imageView = UIImageView()
    private let dotView = UIView()
    private let titleLabel = UILabel()
    private var pillWidthConstraint: NSLayoutConstraint!
    private var unselectedGlyphCenterConstraint: NSLayoutConstraint!
    private var selectedGlyphLeadingConstraint: NSLayoutConstraint!
    private var selectedTitleLeadingConstraint: NSLayoutConstraint!

    init(filter: BabelArticleFilter) {
        self.filter = filter
        super.init(frame: .zero)

        isAccessibilityElement = true
        accessibilityLabel = filter.title.capitalized
        accessibilityIdentifier = "babel.filter.\(filter.title.lowercased())"

        pillView.isUserInteractionEnabled = false
        pillView.layer.cornerRadius = 13
        pillView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pillView)

        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = BabelPalette.mutedInk
        imageView.isUserInteractionEnabled = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        dotView.backgroundColor = BabelPalette.mutedInk
        dotView.layer.cornerRadius = 5
        dotView.isUserInteractionEnabled = false
        dotView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dotView)

        titleLabel.text = filter.title
        titleLabel.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textColor = BabelPalette.mutedInk
        titleLabel.isUserInteractionEnabled = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        pillWidthConstraint = pillView.widthAnchor.constraint(equalToConstant: filter.selectedWidth)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: BabelChromeMetrics.minimumHitTarget),
            pillView.centerXAnchor.constraint(equalTo: centerXAnchor),
            pillView.centerYAnchor.constraint(equalTo: centerYAnchor),
            pillWidthConstraint,
            pillView.heightAnchor.constraint(equalToConstant: 26),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 10),
            dotView.heightAnchor.constraint(equalToConstant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        // The selected component has an explicit 26 pt pill.  The visible
        // glyph remains compact while the enclosing UIControl keeps the
        // Figma-required 44 pt hit target.
        switch filter {
        case .starred:
            imageView.widthAnchor.constraint(equalToConstant: BabelChromeMetrics.bottomIconPointSize).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: BabelChromeMetrics.bottomIconPointSize).isActive = true
            unselectedGlyphCenterConstraint = imageView.centerXAnchor.constraint(equalTo: centerXAnchor)
            selectedGlyphLeadingConstraint = imageView.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 10)
            selectedTitleLeadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5)
        case .unread:
            unselectedGlyphCenterConstraint = dotView.centerXAnchor.constraint(equalTo: centerXAnchor)
            selectedGlyphLeadingConstraint = dotView.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 8)
            selectedTitleLeadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 7)
        case .all:
            imageView.widthAnchor.constraint(equalToConstant: BabelChromeMetrics.bottomIconPointSize).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: BabelChromeMetrics.bottomIconPointSize).isActive = true
            unselectedGlyphCenterConstraint = imageView.centerXAnchor.constraint(equalTo: centerXAnchor)
            selectedGlyphLeadingConstraint = imageView.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 9)
            selectedTitleLeadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6)
        }
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isSelected: Bool {
        didSet {
            guard oldValue != isSelected else { return }
            updateAppearance()
        }
    }

    func setSelected(_ selected: Bool, animated: Bool) {
        guard isSelected != selected else { return }
        if animated {
            UIView.transition(
                with: self,
                duration: BabelChromeMetrics.selectionDuration,
                options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState]
            ) {
                self.isSelected = selected
            }
        } else {
            isSelected = selected
        }
    }

    private func updateAppearance() {
		pillView.isHidden = usesExternalSelectionPill || !isSelected
        pillView.backgroundColor = BabelPalette.raisedBackground.withAlphaComponent(0.62)
        titleLabel.isHidden = !isSelected
        dotView.isHidden = filter != .unread
        unselectedGlyphCenterConstraint.isActive = !isSelected
        selectedGlyphLeadingConstraint.isActive = isSelected
        selectedTitleLeadingConstraint.isActive = isSelected

        switch filter {
        case .starred:
            imageView.image = BabelChromeMetrics.bottomSymbol(isSelected ? "star.fill" : "star")
            imageView.isHidden = false
        case .unread:
            imageView.isHidden = true
        case .all:
            imageView.image = BabelChromeMetrics.bottomSymbol("line.3.horizontal")
            imageView.isHidden = false
        }

        if isSelected {
            accessibilityTraits.insert(.selected)
        } else {
            accessibilityTraits.remove(.selected)
        }
    }

}

final class BabelTranslationToggleControl: UIControl {
    enum Display {
        case original
        case translation
        case translating
    }

    private let primaryLabel = UILabel()
    private let secondaryLabel = UILabel()

    var display: Display = .translation {
        didSet { updateLabels() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true

        primaryLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        primaryLabel.textColor = BabelPalette.mutedInk
        secondaryLabel.isHidden = true

        let stack = UIStackView(arrangedSubviews: [primaryLabel, secondaryLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 3
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: BabelChromeMetrics.minimumHitTarget),
            heightAnchor.constraint(greaterThanOrEqualToConstant: BabelChromeMetrics.minimumHitTarget),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateLabels()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updateLabels() {
        switch display {
        case .original:
            primaryLabel.text = "原"
            accessibilityLabel = "翻译内容"
        case .translation:
            primaryLabel.text = "译"
            accessibilityLabel = "显示原文"
        case .translating:
            primaryLabel.text = "译"
            accessibilityLabel = "正在翻译"
        }
    }
}

extension UIView {
    func babelPinToEdges(of view: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: view.leadingAnchor),
            trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topAnchor.constraint(equalTo: view.topAnchor),
            bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
