//
//  BabelShellViewController.swift
//  NetNewsWire
//
//  Phase-one root for the independent Babel interface.
//

import UIKit

final class BabelShellViewController: UIViewController {

	var onOpenGenesisV2: (() -> Void)?

	private let contentStack = UIStackView()

	override func viewDidLoad() {
		super.viewDidLoad()
		configureView()
	}

	private func configureView() {
		view.backgroundColor = .systemBackground

		let eyebrowLabel = UILabel()
		eyebrowLabel.text = "BABEL · PHASE 1"
		eyebrowLabel.font = .preferredFont(forTextStyle: .caption1)
		eyebrowLabel.textColor = .secondaryLabel

		let titleLabel = UILabel()
		titleLabel.text = "Babel"
		titleLabel.font = .systemFont(ofSize: 42, weight: .semibold)
		titleLabel.adjustsFontForContentSizeCategory = true

		let descriptionLabel = UILabel()
		descriptionLabel.text = "新的阅读外壳已经与创世版本 2 分离。下一步会在这里接入首页、时间线和阅读页。"
		descriptionLabel.font = .preferredFont(forTextStyle: .body)
		descriptionLabel.textColor = .secondaryLabel
		descriptionLabel.numberOfLines = 0

		let statusLabel = UILabel()
		statusLabel.text = "旧界面与全部阅读功能仍然保留"
		statusLabel.font = .preferredFont(forTextStyle: .subheadline)
		statusLabel.textColor = .label
		statusLabel.numberOfLines = 0

		var buttonConfiguration = UIButton.Configuration.filled()
		buttonConfiguration.title = "打开创世版本 2"
		buttonConfiguration.cornerStyle = .large
		buttonConfiguration.image = UIImage(systemName: "arrow.backward")
		buttonConfiguration.imagePadding = 8

		let legacyButton = UIButton(configuration: buttonConfiguration)
		legacyButton.addTarget(self, action: #selector(openGenesisV2), for: .touchUpInside)

		contentStack.axis = .vertical
		contentStack.alignment = .fill
		contentStack.spacing = 18
		contentStack.translatesAutoresizingMaskIntoConstraints = false
		contentStack.addArrangedSubview(eyebrowLabel)
		contentStack.addArrangedSubview(titleLabel)
		contentStack.addArrangedSubview(descriptionLabel)
		contentStack.setCustomSpacing(30, after: descriptionLabel)
		contentStack.addArrangedSubview(statusLabel)
		contentStack.addArrangedSubview(legacyButton)

		view.addSubview(contentStack)

		NSLayoutConstraint.activate([
			contentStack.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
			contentStack.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
			contentStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
			legacyButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
		])
	}

	@objc private func openGenesisV2() {
		onOpenGenesisV2?()
	}
}
