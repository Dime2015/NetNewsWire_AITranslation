//
//  FetchRequestOperation.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 6/20/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import Foundation
import os
import RSCore
import RSDatabase
import Account
import Articles
import ErrorLog

// Main thread only.
// Runs an asynchronous fetch.

typealias FetchRequestOperationResultBlock = (Set<Article>, FetchRequestOperation) -> Void

// TODO: unify these two versions of FetchRequestOperation,
// which diverged when we changed — just on iOS — how we keep track
// of sidebar item hide-read-articles settings.

#if os(macOS)

@MainActor final class FetchRequestOperation {

	let id: Int
	let readFilterEnabledTable: [SidebarItemIdentifier: Bool]
	let resultBlock: FetchRequestOperationResultBlock
	var isCanceled = false
	var isFinished = false
	private let fetchers: [ArticleFetcher]

	init(id: Int, readFilterEnabledTable: [SidebarItemIdentifier: Bool], fetchers: [ArticleFetcher], resultBlock: @escaping FetchRequestOperationResultBlock) {
		precondition(Thread.isMainThread)
		self.id = id
		self.readFilterEnabledTable = readFilterEnabledTable
		self.fetchers = fetchers
		self.resultBlock = resultBlock
	}

	@MainActor func run(_ completion: @escaping (FetchRequestOperation) -> Void) {
		precondition(Thread.isMainThread)
		precondition(!isFinished)

		Task { @MainActor in
			var didCallCompletion = false

			func callCompletionIfNeeded() {
				if !didCallCompletion {
					didCallCompletion = true
					completion(self)
				}
			}

			if isCanceled {
				callCompletionIfNeeded()
				return
			}

			if fetchers.isEmpty {
				isFinished = true
				resultBlock(Set<Article>(), self)
				callCompletionIfNeeded()
				return
			}

			Self.logger.debug("FetchRequestOperation \(self.id, privacy: .public): run starting — \(self.fetchers.count) fetcher(s)")

			let numberOfFetchers = fetchers.count
			var fetchersReturned = 0
			var fetchedArticles = Set<Article>()

			@MainActor func process(_ articles: Set<Article>) {
				precondition(Thread.isMainThread)
				guard !self.isCanceled else {
					callCompletionIfNeeded()
					return
				}

				assert(!self.isFinished)

				fetchedArticles.formUnion(articles)
				fetchersReturned += 1
				if fetchersReturned == numberOfFetchers {
					self.isFinished = true
					self.resultBlock(fetchedArticles, self)
					callCompletionIfNeeded()
				}
			}

			for fetcher in fetchers {
				let articles: Set<Article>

				if (fetcher as? SidebarItem)?.readFiltered(readFilterEnabledTable: readFilterEnabledTable) ?? true {
					articles = await fetcher.fetchUnreadArticlesAsync()
				} else {
					articles = await fetcher.fetchArticlesAsync()
				}

				process(articles)
			}

			// Belt-and-suspenders: ensure the queue never deadlocks even if
			// the loop above is ever refactored to skip process().
			callCompletionIfNeeded()
		}
	}
}

#else

@MainActor final class FetchRequestOperation {

	let id: Int
	let hidingReadArticlesState: HidingReadArticlesState
	let resultBlock: FetchRequestOperationResultBlock
	var isCanceled = false
	var isFinished = false
	private let fetchers: [ArticleFetcher]

	init(id: Int, hidingReadArticlesState: HidingReadArticlesState, fetchers: [ArticleFetcher], resultBlock: @escaping FetchRequestOperationResultBlock) {
		precondition(Thread.isMainThread)
		self.id = id
		self.hidingReadArticlesState = hidingReadArticlesState
		self.fetchers = fetchers
		self.resultBlock = resultBlock
	}

	@MainActor func run(_ completion: @escaping (FetchRequestOperation) -> Void) {
		precondition(Thread.isMainThread)
		precondition(!isFinished)

		Task { @MainActor in
			var didCallCompletion = false

			func callCompletionIfNeeded() {
				if !didCallCompletion {
					didCallCompletion = true
					completion(self)
				}
			}

			if isCanceled {
				callCompletionIfNeeded()
				return
			}

			if fetchers.isEmpty {
				isFinished = true
				resultBlock(Set<Article>(), self)
				callCompletionIfNeeded()
				return
			}

			Self.logger.debug("FetchRequestOperation \(self.id, privacy: .public): run starting — \(self.fetchers.count) fetcher(s)")

			let numberOfFetchers = fetchers.count
			var fetchersReturned = 0
			var fetchedArticles = Set<Article>()

			@MainActor func process(_ articles: Set<Article>) {
				precondition(Thread.isMainThread)
				guard !self.isCanceled else {
					callCompletionIfNeeded()
					return
				}

				assert(!self.isFinished)

				fetchedArticles.formUnion(articles)
				fetchersReturned += 1
				if fetchersReturned == numberOfFetchers {
					self.isFinished = true
					self.resultBlock(fetchedArticles, self)
					callCompletionIfNeeded()
				}
			}

			@MainActor func fetcherHidesReadArticles(_ fetcher: ArticleFetcher) -> Bool {
				guard let sidebarItem = fetcher as? SidebarItem, let sidebarItemID = sidebarItem.sidebarItemID else {
					return false
				}
				// [阅读档] 底部三档是总闸,盖过上游"每个源各记一份"的表(实现见 iOS/ReadingMode/)。
				// ⚠️ 借上游自己的守卫排除「全部未读」那个智能源 —— 它的定义就是"未读",
				// 让总闸把它改成"显示已读"会自相矛盾(上游 canToggle 对它返回 false)。
				if hidingReadArticlesState.canToggleHidingReadArticles(for: sidebarItemID),
				   let forced = NNWReadingModeStore.shared.hidesReadArticles {
					return forced
				}
				return hidingReadArticlesState.isHidingReadArticles(for: sidebarItemID)
			}

			for fetcher in fetchers {
				let articles: Set<Article>
				// [阅读档] ★ 档:只要加过星的。
				// **取全部再在内存里筛** —— 和上游自己算未读是同一个套路
				//(`Feed.fetchUnreadArticles()` 就是 `fetchArticles().unreadArticles()`),
				// 而且这条路上游在「全部」档下本来就要走一遍,没有新增的数据库开销。
				if NNWReadingModeStore.shared.mode == .starred {
					articles = await fetcher.fetchArticlesAsync().filter { $0.status.starred }
				} else if fetcherHidesReadArticles(fetcher) {
					articles = await fetcher.fetchUnreadArticlesAsync()
				} else {
					articles = await fetcher.fetchArticlesAsync()
				}
				process(articles)
			}

			// Ensure the queue never deadlocks even if
			// the loop above is ever refactored to skip process().
			callCompletionIfNeeded()
		}
	}
}

#endif

private extension FetchRequestOperation {

	static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FetchRequestOperation")
	static let errorLogSourceID = 101

	static func postFetchError(_ error: Error, fileName: String = #fileID, functionName: String = #function, lineNumber: Int = #line) {
		let typeName = String(describing: type(of: error))
		let description = "\(typeName): \(error.localizedDescription)"
		let userInfo = ErrorLogUserInfoKey.userInfo(sourceName: "Timeline", sourceID: errorLogSourceID, operation: "Fetching articles", errorMessage: description, fileName: fileName, functionName: functionName, lineNumber: lineNumber)
		NotificationCenter.default.post(name: .appDidEncounterError, object: nil, userInfo: userInfo)
	}
}
