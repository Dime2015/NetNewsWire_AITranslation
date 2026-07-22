//
//  ArticleReadingStateStore.swift
//  NetNewsWire — AI 翻译 fork
//
//  [状态记忆] item③:按「单篇文章」记住两个阅读状态 ——
//    - 阅读模式(Reader View)开没开
//    - 是否显示译文
//  打开文章时据此自动恢复(翻译仅在本地有缓存时自动秒显,不会悄悄联网;
//  这条规则在 TranslationController.autoApplyTranslationFromCacheIfNeeded 里落实)。
//
//  为什么要自己存:上游只有「按订阅源」的「总是用阅读视图」开关
//  (Feed.readerViewAlwaysEnabled),没有「按单篇文章」的记忆;
//  而全局的 AppDefaults.isShowingExtractedArticle 只用于 app 重启时恢复上一篇。
//
//  存在哪:UserDefaults。每篇只占一个整数位掩码,几百条也就几 KB。
//  为防无限膨胀,按「最近写过」做 LRU,超过上限就丢最旧的。
//  两个状态都为假的文章不留条目(删掉),所以普通文章不会留下垃圾。
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

#if os(iOS)

import Foundation

@MainActor
enum ArticleReadingStateStore {

	/// 一篇文章的两个记忆状态。
	struct State: Equatable {
		var readerMode: Bool
		var translated: Bool

		/// 两个都为假 —— 这篇没什么可记的,存储里不留条目。
		var isEmpty: Bool { !readerMode && !translated }
	}

	// UserDefaults 里的两个键:一个存「文章ID → 位掩码」,一个存最近写过的顺序(旧→新)。
	private static let maskKey = "nnwArticleReadingState"
	private static let orderKey = "nnwArticleReadingStateOrder"

	/// 最多记多少篇。超了从最旧的开始丢。
	private static let maxEntries = 500

	private static let readerBit = 1
	private static let translatedBit = 2

	/// 读一篇文章的记忆状态。没记过就返回「两个都关」。
	static func state(for articleID: String) -> State {
		let dict = UserDefaults.standard.dictionary(forKey: maskKey) as? [String: Int] ?? [:]
		let mask = dict[articleID] ?? 0
		return State(readerMode: mask & readerBit != 0,
					 translated: mask & translatedBit != 0)
	}

	/// 写一篇文章的完整状态。两个都为假时删掉这条(不留垃圾)。
	static func setState(_ newState: State, for articleID: String) {

		// 没变就不写,省掉每次页面加载都刷一遍 UserDefaults。
		guard newState != state(for: articleID) else {
			return
		}

		var dict = UserDefaults.standard.dictionary(forKey: maskKey) as? [String: Int] ?? [:]
		var order = UserDefaults.standard.stringArray(forKey: orderKey) ?? []

		order.removeAll { $0 == articleID }

		if newState.isEmpty {
			dict[articleID] = nil
		} else {
			var mask = 0
			if newState.readerMode { mask |= readerBit }
			if newState.translated { mask |= translatedBit }
			dict[articleID] = mask
			order.append(articleID)		// 最近写的排最后

			// 超上限 → 从最旧的开始丢
			while order.count > maxEntries {
				let oldest = order.removeFirst()
				dict[oldest] = nil
			}
		}

		UserDefaults.standard.set(dict, forKey: maskKey)
		UserDefaults.standard.set(order, forKey: orderKey)
	}

	/// 只改「阅读模式」这一位,保留另一位。
	static func setReaderMode(_ on: Bool, for articleID: String) {
		var s = state(for: articleID)
		s.readerMode = on
		setState(s, for: articleID)
	}

	/// 只改「已翻译」这一位,保留另一位。
	static func setTranslated(_ on: Bool, for articleID: String) {
		var s = state(for: articleID)
		s.translated = on
		setState(s, for: articleID)
	}
}

#endif
