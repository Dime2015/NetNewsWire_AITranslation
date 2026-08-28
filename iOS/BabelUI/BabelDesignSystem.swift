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
            ? UIColor(red: 0.115, green: 0.115, blue: 0.125, alpha: 1)
            : UIColor(red: 0.945, green: 0.940, blue: 0.945, alpha: 1)
    }
    static let raisedBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.185, green: 0.185, blue: 0.195, alpha: 1)
            : UIColor(red: 0.875, green: 0.870, blue: 0.875, alpha: 1)
    }
    static let ink = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : .black
    }
    static let mutedInk = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.58, alpha: 1)
            : UIColor(white: 0.42, alpha: 1)
    }
    static let hairline = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor.black.withAlphaComponent(0.10)
    }
    static let accent = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.28, blue: 0.30, alpha: 1)
            : UIColor(red: 0.82, green: 0.17, blue: 0.18, alpha: 1)
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
