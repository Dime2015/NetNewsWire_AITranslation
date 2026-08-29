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
            : UIColor(red: 229.0 / 255.0, green: 226.0 / 255.0, blue: 227.0 / 255.0, alpha: 1)
    }
    static let ink = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 216.0 / 255.0, green: 216.0 / 255.0, blue: 216.0 / 255.0, alpha: 1)
            : UIColor(red: 66.0 / 255.0, green: 63.0 / 255.0, blue: 64.0 / 255.0, alpha: 1)
    }
    static let mutedInk = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 108.0 / 255.0, green: 108.0 / 255.0, blue: 108.0 / 255.0, alpha: 1)
            : UIColor(red: 136.0 / 255.0, green: 136.0 / 255.0, blue: 134.0 / 255.0, alpha: 1)
    }
    static let hairline = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor.black.withAlphaComponent(0.10)
    }
    static let accent = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 214.0 / 255.0, green: 76.0 / 255.0, blue: 70.0 / 255.0, alpha: 1)
            : UIColor(red: 68.0 / 255.0, green: 190.0 / 255.0, blue: 156.0 / 255.0, alpha: 1)
    }
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
