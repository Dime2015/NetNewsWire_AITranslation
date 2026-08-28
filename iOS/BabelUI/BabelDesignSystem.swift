//
//  BabelDesignSystem.swift
//  NetNewsWire
//

import UIKit

enum BabelPalette {

	static let background = UIColor { traits in
		traits.userInterfaceStyle == .dark
			? UIColor(red: 0.067, green: 0.067, blue: 0.059, alpha: 1)
			: UIColor(red: 0.957, green: 0.945, blue: 0.910, alpha: 1)
	}

	static let raisedBackground = UIColor { traits in
		traits.userInterfaceStyle == .dark
			? UIColor(red: 0.11, green: 0.11, blue: 0.10, alpha: 1)
			: UIColor(red: 0.985, green: 0.978, blue: 0.955, alpha: 1)
	}

	static let ink = UIColor { traits in
		traits.userInterfaceStyle == .dark
			? UIColor(red: 0.94, green: 0.93, blue: 0.89, alpha: 1)
			: UIColor(red: 0.10, green: 0.10, blue: 0.085, alpha: 1)
	}

	static let mutedInk = UIColor { traits in
		traits.userInterfaceStyle == .dark
			? UIColor(red: 0.62, green: 0.61, blue: 0.57, alpha: 1)
			: UIColor(red: 0.39, green: 0.38, blue: 0.34, alpha: 1)
	}

	static let hairline = UIColor { traits in
		traits.userInterfaceStyle == .dark
			? UIColor.white.withAlphaComponent(0.12)
			: UIColor.black.withAlphaComponent(0.11)
	}

	static let accent = UIColor { traits in
		traits.userInterfaceStyle == .dark
			? UIColor(red: 0.95, green: 0.53, blue: 0.34, alpha: 1)
			: UIColor(red: 0.76, green: 0.25, blue: 0.12, alpha: 1)
	}
}

enum BabelTypography {

	static func display(size: CGFloat) -> UIFont {
		let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
			.withDesign(.serif)?
			.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]]) ?? UIFontDescriptor()
		return UIFont(descriptor: descriptor, size: size)
	}

	static func title(size: CGFloat = 24, weight: UIFont.Weight = .semibold) -> UIFont {
		UIFont.systemFont(ofSize: size, weight: weight)
	}

	static func reading(size: CGFloat = 18) -> UIFont {
		let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).withDesign(.serif)
		return UIFont(descriptor: descriptor ?? UIFontDescriptor(), size: size)
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
