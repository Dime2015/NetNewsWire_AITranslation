//
//  FeedInspectorViewController+NNWUnsubscribe.swift
//  NetNewsWire — AI 翻译 fork
//
//  [取消订阅] 本 fork 新增,上游没有这个文件(2026-08-12,用户要求)。
//
//  给「源信息与设置」页最下面放一颗红色的「取消订阅」按钮。
//
//  ## ⚠️ 第一版是错的,记着别再走回去(2026-08-12 当天真机崩溃)
//  第一版把它做成**表格末尾多加的一个区**。结果一打开这页就崩:
//  `NSRangeException: index 3 beyond bounds [0 .. 2]`。
//
//  原因:这页是 **storyboard 静态表**。静态表的数据源住在 UIKit 内部,
//  它手里那个数组**只有 storyboard 里那 3 个区**。我们让 `numberOfSections`
//  多报一个区,UIKit 就会拿区号 3 去问一整套方法 ——
//  只要有**任何一个**我们没拦下来、漏到了 `super`(footer 标题、footer 高度、
//  各种 estimated…,数量比想象的多得多),就地越界崩溃。
//  +NNWTitleTranslation 加的是**行**,行只需要答三四个问题,拦得住;
//  加**区**要答的问题是开放集合,拦不全 —— 这是两件事,不能照抄。
//
//  ## 现在的做法:`tableView.tableFooterView`
//  表尾视图**完全不经过数据源**,UIKit 只是把它贴在最后一区下面。
//  零个数据源方法被改动 → 结构上不可能再触发静态表越界。
//  视觉上它也正好落在整页最底下,就是我们要的位置。
//
//  ## 取消订阅本身怎么做
//  照抄发现页那套(`FeedDiscoveryViewController.unsubscribe`):跨账户找到这个源的
//  所有落点,逐个调上游公开接口 `Account.removeFeed(_:from:)`。禁区一行没碰。
//  ⚠️ 和列表页的 `performDelete` 不同,这里**不接 undo** —— 本页是模态卡片,
//  做完就关掉了,身后没有能接住撤销的 undoManager(硬接反而会做出一个
//  "撤销了但页面早没了"的假动作)。所以确认框问得实一点,问完就真做。
//

#if os(iOS)

import UIKit
import Account
import RSCore
import os

extension FeedInspectorViewController {

	private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "取消订阅")

	/// 装表尾那颗按钮。上游 `viewDidLoad` 末尾调一次,全部实现住在本文件。
	func nnwInstallUnsubscribeFooter() {

		// 高度是定死的:表尾视图不参与 Auto Layout 的高度协商,
		// UIKit 只认它 frame 里的高度(这是 tableHeaderView / tableFooterView 的老规矩)。
		let footer = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 76))
		footer.autoresizingMask = .flexibleWidth	// 转屏 / 分屏时跟着表格变宽

		let button = UIButton(type: .system)
		button.setTitle("取消订阅", for: .normal)
		button.setTitleColor(.systemRed, for: .normal)		// 破坏性动作:红字,和 iOS 自己的习惯一致
		button.titleLabel?.font = .preferredFont(forTextStyle: .body)
		button.titleLabel?.adjustsFontForContentSizeCategory = true
		button.addTarget(self, action: #selector(nnwUnsubscribeTapped(_:)), for: .touchUpInside)
		button.translatesAutoresizingMaskIntoConstraints = false
		footer.addSubview(button)

		NSLayoutConstraint.activate([
			button.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
			button.topAnchor.constraint(equalTo: footer.topAnchor, constant: 16),
			button.heightAnchor.constraint(equalToConstant: 44)		// 够得着的点按面积
		])

		tableView.tableFooterView = footer
	}

	// MARK: - 点下去之后

	@objc func nnwUnsubscribeTapped(_ sender: UIButton) {

		guard let feed else { return }
		let name = feed.nameForDisplay

		let alert = UIAlertController(title: nil,
									  message: "确定取消订阅「\(name)」吗?",
									  preferredStyle: .actionSheet)
		alert.addAction(UIAlertAction(title: "取消订阅", style: .destructive) { [weak self] _ in
			self?.nnwPerformUnsubscribe(feed)
		})
		alert.addAction(UIAlertAction(title: "取消", style: .cancel))

		// iPad 上 actionSheet 必须锚在触发它的那颗按钮上,否则会崩
		if let popover = alert.popoverPresentationController {
			popover.sourceView = sender
			popover.sourceRect = sender.bounds
		}
		present(alert, animated: true)
	}

	/// 跨账户把这个源的所有落点都删掉(一个源理论上只在一处,但"多账户都订了 /
	/// 一源进了多个文件夹"也一并处理干净)。做法与发现页的取消订阅完全一致。
	private func nnwPerformUnsubscribe(_ feed: Feed) {

		var targets: [(Account, Feed, Container)] = []
		for account in AccountManager.shared.activeAccounts {
			// 用 URL 去认,而不是直接用手里这个对象 —— 和发现页同一套判断
			guard let existing = account.existingFeed(withURL: feed.url) else { continue }
			for container in account.existingContainers(withFeed: existing) {
				targets.append((account, existing, container))
			}
		}

		var pending = targets.count
		guard pending > 0 else {
			// 源已经不在了(可能刚在别处取消过):直接关页面,别让用户对着一张空卡片
			Self.logger.info("[取消订阅] 源已不在任何账户里,直接关页:\(feed.url)")
			dismiss(animated: true)
			return
		}

		// 时间线/Handoff 里可能还记着这个源,一并清掉(和列表页 performDelete 同一手)
		ActivityManager.cleanUp(feed)

		BatchUpdate.shared.start()
		var firstError: Error?

		for (account, existing, container) in targets {
			// 回调在主线程(Account.removeFeed 内部走 @MainActor),这个计数器不会有并发问题
			account.removeFeed(existing, from: container) { [weak self] result in
				if case .failure(let error) = result, firstError == nil {
					firstError = error
				}
				pending -= 1
				guard pending == 0 else { return }

				BatchUpdate.shared.end()
				guard let self else { return }
				if let error = firstError {
					// 失败就留在本页把话说清楚,别把页面关掉让用户以为成了
					Self.logger.error("[取消订阅] 失败:\(feed.url) — \(error.localizedDescription)")
					self.presentError(error)
				} else {
					Self.logger.info("[取消订阅] 已取消订阅:\(feed.url)")
					self.dismiss(animated: true)
				}
			}
		}
	}
}

#endif
