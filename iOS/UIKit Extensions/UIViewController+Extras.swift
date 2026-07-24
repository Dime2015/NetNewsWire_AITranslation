//
//  UIViewController-Extensions.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 1/16/20.
//  Copyright © 2020 Ranchero Software. All rights reserved.
//

import UIKit
import RSCore
import Account

extension UIViewController {

	func presentError(_ error: Error, dismiss: (() -> Void)? = nil) {
		if let accountError = error as? AccountError, accountError.isCredentialsError {
			presentAccountError(accountError, dismiss: dismiss)
		} else if let decodingError = error as? DecodingError {
			let errorTitle = NSLocalizedString("Error", comment: "Error")
			var informativeText: String = ""
			switch decodingError {
			case .typeMismatch(let type, _):
				let localizedError = NSLocalizedString("This theme cannot be used because the the type—“%@”—is mismatched in the Info.plist", comment: "Type mismatch")
				informativeText = NSString.localizedStringWithFormat(localizedError as NSString, type as! CVarArg) as String
				presentError(title: errorTitle, message: informativeText, dismiss: dismiss)
			case .valueNotFound(let value, _):
				let localizedError = NSLocalizedString("This theme cannot be used because the the value—“%@”—is not found in the Info.plist.", comment: "Decoding value missing")
				informativeText = NSString.localizedStringWithFormat(localizedError as NSString, value as! CVarArg) as String
				presentError(title: errorTitle, message: informativeText, dismiss: dismiss)
			case .keyNotFound(let codingKey, _):
				let localizedError = NSLocalizedString("This theme cannot be used because the the key—“%@”—is not found in the Info.plist.", comment: "Decoding key missing")
				informativeText = NSString.localizedStringWithFormat(localizedError as NSString, codingKey.stringValue) as String
				presentError(title: errorTitle, message: informativeText, dismiss: dismiss)
			case .dataCorrupted(let context):
				guard let error = context.underlyingError as NSError?,
					  let debugDescription = error.userInfo["NSDebugDescription"] as? String else {
					informativeText = error.localizedDescription
					presentError(title: errorTitle, message: informativeText, dismiss: dismiss)
					return
				}
				let localizedError = NSLocalizedString("This theme cannot be used because of data corruption in the Info.plist. %@.", comment: "Decoding key missing")
				informativeText = NSString.localizedStringWithFormat(localizedError as NSString, debugDescription) as String
				presentError(title: errorTitle, message: informativeText, dismiss: dismiss)

			default:
				informativeText = error.localizedDescription
				presentError(title: errorTitle, message: informativeText, dismiss: dismiss)
			}
		} else {
			// Check if error supports recovery options
			if let recoverableError = error as? (RecoverableError & LocalizedError),
			   !recoverableError.recoveryOptions.isEmpty {
				presentErrorWithRecovery(error: recoverableError, dismiss: dismiss)
			} else {
				let errorTitle = NSLocalizedString("Error", comment: "Error")
				presentError(title: errorTitle, message: error.localizedDescription, dismiss: dismiss)
			}
		}
	}

}

private extension UIViewController {

	func presentAccountError(_ error: AccountError, dismiss: (() -> Void)? = nil) {
		// [外观] 系统 alert 换成自绘品牌卡片(NNWMenu,本 fork 新增);选项与行为原样保留
		let title = NSLocalizedString("Account Error", comment: "Account Error")
		var items: [NNWMenu.Item] = []

		let account = AccountError.account(from: error)
		if account?.type == .feedbin {
			let credentialsTitle = NSLocalizedString("Update Credentials", comment: "Update Credentials")
			items.append(NNWMenu.Item(title: credentialsTitle, icon: "key") { [weak self] in
				dismiss?()

				let navController = UIStoryboard.account.instantiateViewController(withIdentifier: "FeedbinAccountNavigationViewController") as! UINavigationController
				navController.modalPresentationStyle = .formSheet
				let addViewController = navController.topViewController as! FeedbinAccountViewController
				addViewController.account = account
				self?.present(navController, animated: true)
			})
		}

		let dismissTitle = NSLocalizedString("OK", comment: "OK button")
		items.append(NNWMenu.Item(title: dismissTitle, icon: nil) { dismiss?() })

		NNWMenu.show(in: self, anchor: .center, title: title, message: error.localizedDescription,
					 sections: [items], onCancel: dismiss)
	}

	func presentErrorWithRecovery(error: RecoverableError & LocalizedError, dismiss: (() -> Void)? = nil) {
		// [外观] 系统 alert 换成自绘品牌卡片;恢复选项逐条变成菜单行,行为原样保留
		let title = error.errorDescription ?? NSLocalizedString("Error", comment: "Error")
		let message = [error.failureReason, error.recoverySuggestion].compactMap { $0 }.joined(separator: " ")

		let items: [NNWMenu.Item] = error.recoveryOptions.enumerated().map { index, option in
			NNWMenu.Item(title: option, icon: nil) {
				dismiss?()
				_ = error.attemptRecovery(optionIndex: index)
			}
		}

		NNWMenu.show(in: self, anchor: .center, title: title, message: message,
					 sections: [items], onCancel: dismiss)
	}

}
