//
//  ColorPaletteTableViewController.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 3/15/20.
//  Copyright © 2020 Ranchero Software. All rights reserved.
//

import UIKit

final class ColorPaletteTableViewController: UITableViewController {

	private var pendingPalette = AppDefaults.userInterfaceColorPalette	// [交互] 待应用的配色;点勾才生效

	// [外观] 暖纸风:表格底色 + 关分隔线;cell 暖底 + 药丸选中
	override func viewDidLoad() {
		super.viewDidLoad()
		AppAppearance.applyPaperStyle(to: tableView)
		nnwInstallCancelSaveItems(saveAction: #selector(saveTapped), cancelAction: #selector(cancelTapped))	// [交互] 左上取消 / 右上勾
	}

	@objc private func cancelTapped() {
		navigationController?.popViewController(animated: true)		// 不改配色,直接退回
	}

	@objc private func saveTapped() {
		AppDefaults.userInterfaceColorPalette = pendingPalette		// 应用配色
		navigationController?.popViewController(animated: true)
	}

	override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		AppAppearance.applyPaperStyle(to: cell)
	}

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return UserInterfaceColorPalette.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
		let rowColorPalette = UserInterfaceColorPalette.allCases[indexPath.row]
		cell.textLabel?.text = String(describing: rowColorPalette)
		cell.accessoryType = (rowColorPalette == pendingPalette) ? .checkmark : .none
        return cell
    }

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
		if let colorPalette = UserInterfaceColorPalette(rawValue: indexPath.row) {
			pendingPalette = colorPalette		// 只标记待选,点勾才生效
			tableView.reloadData()
		}
	}

}
