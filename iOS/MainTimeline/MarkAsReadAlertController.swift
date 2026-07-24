//
//  UndoAvailableAlertController.swift
//  NetNewsWire
//
//  Created by Phil Viso on 9/29/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import Foundation
import UIKit

protocol MarkAsReadAlertControllerSourceType {}
extension CGRect: MarkAsReadAlertControllerSourceType {}
extension UIView: MarkAsReadAlertControllerSourceType {}
extension UIBarButtonItem: MarkAsReadAlertControllerSourceType {}

@MainActor struct MarkAsReadAlertController {

	static func confirm<T>(_ controller: UIViewController?,
	                       coordinator: SceneCoordinator?,
	                       confirmTitle: String,
	                       sourceType: T,
	                       cancelCompletion: (() -> Void)? = nil,
	                       completion: @escaping () -> Void) where T: MarkAsReadAlertControllerSourceType {

		guard let controller, let coordinator else {
			completion()
			return
		}

		if AppDefaults.shared.confirmMarkAllAsRead {
			// [外观] 系统动作单换成自绘品牌选单;文案与三个选项原样保留,
			// 实现住在 iOS/DesignKit/NNWMenu+Bridges.swift(本 fork 新增)。
			// 下面上游原有的 alert(...) 不再被调用,原样保留以便与上游合并。
			NNWMenu.showMarkAsReadConfirm(in: controller, coordinator: coordinator,
										  confirmTitle: confirmTitle, sourceType: sourceType,
										  cancelCompletion: cancelCompletion, completion: completion)
		} else {
			completion()
		}
	}

	private static func alert<T>(coordinator: SceneCoordinator,
	                             confirmTitle: String,
	                             cancelCompletion: (() -> Void)?,
	                             sourceType: T,
	                             completion: @escaping (UIAlertAction) -> Void) -> UIAlertController where T: MarkAsReadAlertControllerSourceType {

		let title = NSLocalizedString("Mark As Read", comment: "Mark As Read")
		let message = NSLocalizedString("You can turn this confirmation off in Settings.",
										comment: "You can turn this confirmation off in Settings.")
		let cancelTitle = NSLocalizedString("Cancel", comment: "Cancel button")
		let settingsTitle = NSLocalizedString("Open Settings", comment: "Open Settings button")

		let alertController = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
		let cancelAction = UIAlertAction(title: cancelTitle, style: .cancel) { _ in
			cancelCompletion?()
		}
		let settingsAction = UIAlertAction(title: settingsTitle, style: .default) { _ in
			Task { @MainActor in
				coordinator.showSettings(scrollToArticlesSection: true)
			}
		}
		let markAction = UIAlertAction(title: confirmTitle, style: .default, handler: completion)

		alertController.addAction(markAction)
		alertController.addAction(settingsAction)
		alertController.addAction(cancelAction)

		if let barButtonItem = sourceType as? UIBarButtonItem {
			alertController.popoverPresentationController?.barButtonItem = barButtonItem
		}

		if let rect = sourceType as? CGRect {
			alertController.popoverPresentationController?.sourceRect = rect
		}

		if let view = sourceType as? UIView {
			alertController.popoverPresentationController?.sourceView = view
		}

		return alertController
	}

}
