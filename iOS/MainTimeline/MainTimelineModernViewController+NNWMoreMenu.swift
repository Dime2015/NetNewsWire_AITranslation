//
//  MainTimelineModernViewController+NNWMoreMenu.swift
//  NetNewsWire — AI 翻译 fork
//
//  [外观] 本 fork 新增,上游没有这个文件。
//
//  文章列表右滑「更多」的自绘品牌选单(替代上游拼的系统动作单)。
//  上游文件里那段 30 多行的 UIAlertController 拼装,收敛成对本文件一行调用。
//
//  ## 和上游的分工(接手前必须看懂,别不小心拆了)
//
//  「该不该显示某一项」和「这一项叫什么」**全部复用上游的工厂方法**
//  (markAboveAsReadAlertAction 等 —— 返回 nil 就是不该显示,返回的 action 自带本地化标题)。
//  这样上游将来改判断条件、改文案,我们**自动跟上**,不用抄一份逻辑来养。
//
//  只有「按下去做什么」是这里重写的 —— UIAlertAction 里存的动作闭包取不出来
//  (系统不开放),所以每一项的动作体都是对着上游工厂**照抄一行**:
//  markAboveAsRead / discloseFeed / showBrowserForArticle …… 全是上游自己的方法。
//  ⚠️ 唯一的例外是「本源全部标为已读」:它的工厂要把整个源的文章都取一遍才能判断,
//  调工厂再在动作里重取会白取两次,所以那一项连判断带动作都在这里写(和上游逐行对齐)。
//
//  ## 时序:为什么一进来就 completion(true)
//
//  completion 是系统给右滑按钮的回调,调了它右滑面板才收回去。
//  原来系统动作单是"弹窗关了才收回";改成自绘选单后**先收面板、再弹选单**
//  (和系统长按菜单的观感一致),选单锚定在那一行 cell 上,不受面板收回影响。
//

#if os(iOS)

import UIKit
import Articles

extension MainTimelineModernViewController {

	/// [外观] 右滑「更多」→ 品牌选单。从被滑的那一行旁边弹出。
	func nnwShowTimelineMoreMenu(for article: Article, indexPath: IndexPath,
								 completion: @escaping (Bool) -> Void) {

		// 先把右滑面板收回去(见文件头「时序」)
		completion(true)

		// 工厂方法要一个 completion 参数;面板已经收了,给个空的
		let noop: (Bool) -> Void = { _ in }
		let contentView = collectionView?.cellForItem(at: indexPath)?.contentView

		var mainGroup: [NNWMenu.Item] = []

		// 上方标已读 / 下方标已读(确认框沿用上游 MarkAsReadAlertController 那条路,
		// 那条路已经换成品牌卡片,见 NNWMenu+Bridges.swift)
		if let action = markAboveAsReadAlertAction(article, indexPath: indexPath, completion: noop),
		   let title = action.title, let contentView {
			mainGroup.append(NNWMenu.Item(title: title, icon: "arrow.up.to.line") { [weak self] in
				guard let self else { return }
				MarkAsReadAlertController.confirm(self, coordinator: self.coordinator,
												  confirmTitle: title, sourceType: contentView) { [weak self] in
					self?.markAboveAsRead(article)
				}
			})
		}
		if let action = markBelowAsReadAlertAction(article, indexPath: indexPath, completion: noop),
		   let title = action.title, let contentView {
			mainGroup.append(NNWMenu.Item(title: title, icon: "arrow.down.to.line") { [weak self] in
				guard let self else { return }
				MarkAsReadAlertController.confirm(self, coordinator: self.coordinator,
												  confirmTitle: title, sourceType: contentView) { [weak self] in
					self?.markBelowAsRead(article)
				}
			})
		}

		// 前往订阅源
		if let action = discloseFeedAlertAction(article, completion: noop), let title = action.title,
		   let feed = article.feed {
			mainGroup.append(NNWMenu.Item(title: title, icon: "list.bullet") { [weak self] in
				self?.discloseFeed(feed, animations: [.scroll, .navigation])
			})
		}

		// 本源全部标为已读(文件头说的例外:判断要取全源文章,取一次、判断和动作共用)
		if let feed = article.feed, let contentView {
			let articles = Array(feed.fetchArticles())
			if articles.canMarkAllAsRead() {
				let format = NSLocalizedString("Mark All as Read in “%@”", comment: "Command")
				let title = NSString.localizedStringWithFormat(format as NSString, feed.nameForDisplay) as String
				mainGroup.append(NNWMenu.Item(title: title, icon: "checkmark.circle") { [weak self] in
					guard let self else { return }
					MarkAsReadAlertController.confirm(self, coordinator: self.coordinator,
													  confirmTitle: title, sourceType: contentView) { [weak self] in
						self?.markAllAsRead(articles)
					}
				})
			}
		}

		var secondaryGroup: [NNWMenu.Item] = []

		// 浏览器打开 / 分享
		if let action = openInBrowserAlertAction(article, completion: noop), let title = action.title {
			secondaryGroup.append(NNWMenu.Item(title: title, icon: "safari") { [weak self] in
				self?.showBrowserForArticle(article)
			})
		}
		if let action = shareAlertAction(article, indexPath: indexPath, completion: noop),
		   let title = action.title, let url = article.preferredURL {
			secondaryGroup.append(NNWMenu.Item(title: title, icon: "square.and.arrow.up") { [weak self] in
				self?.shareDialogForTableCell(indexPath: indexPath, url: url, title: article.title)
			})
		}

		// 全部工厂都说"不该显示"(没订阅源也没链接的文章)→ 没菜单可弹,静静收场
		guard !(mainGroup.isEmpty && secondaryGroup.isEmpty) else { return }

		let anchor: NNWMenu.Anchor
		if let cell = collectionView?.cellForItem(at: indexPath) {
			anchor = .view(cell)
		} else {
			anchor = .center
		}
		NNWMenu.show(in: self, anchor: anchor, sections: [mainGroup, secondaryGroup])
	}
}

#endif
