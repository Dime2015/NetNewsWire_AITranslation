//
//  FeedDiscoveryKeychain.swift
//  NetNewsWire
//
//  [发现] 本 fork 新增,上游没有这个文件。
//
//  统一搜索(播客 + Reddit + YouTube)要用到的第三方凭据,存进系统钥匙串。
//  播客(iTunes Search)不需要凭据;Reddit 和 YouTube 的官方接口都要求调用方
//  自带凭据,免费但要用户自己去申请——这里只负责存取,不负责获取。
//
//  写法抄的是 Shared/Translation/TranslationKeychain.swift(同样绕开 A 级禁区的
//  Modules/Secrets,自己用系统 Security 框架实现)。三个凭据共用一个 service、
//  用不同的 account 名区分,不为每个凭据单开一个文件。
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

import Foundation
import Security

enum FeedDiscoveryKeychain {

	private static let service = "NetNewsWire.FeedDiscovery"

	private enum Account: String {
		case redditClientID = "reddit-client-id"
		case redditClientSecret = "reddit-client-secret"
		case youTubeAPIKey = "youtube-api-key"
	}

	// MARK: - Reddit

	static var redditClientID: String? {
		get { read(.redditClientID) }
		set { write(.redditClientID, newValue) }
	}

	static var redditClientSecret: String? {
		get { read(.redditClientSecret) }
		set { write(.redditClientSecret, newValue) }
	}

	/// 两个都填了,Reddit 搜索才具备条件。
	static var hasRedditCredentials: Bool {
		!(redditClientID ?? "").isEmpty && !(redditClientSecret ?? "").isEmpty
	}

	// MARK: - YouTube

	static var youTubeAPIKey: String? {
		get { read(.youTubeAPIKey) }
		set { write(.youTubeAPIKey, newValue) }
	}

	static var hasYouTubeCredentials: Bool {
		!(youTubeAPIKey ?? "").isEmpty
	}

	// MARK: - 读写(私有,别处别直接碰 Security API)

	private static func read(_ account: Account) -> String? {

		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account.rawValue,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne
		]

		var item: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &item)

		guard status == errSecSuccess,
			  let data = item as? Data,
			  let value = String(data: data, encoding: .utf8),
			  !value.isEmpty else {
			return nil
		}
		return value
	}

	/// 传 nil 或空字符串等同于删除。
	private static func write(_ account: Account, _ newValue: String?) {

		let trimmed = (newValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account.rawValue
		]
		SecItemDelete(query as CFDictionary)	// 先删再加,省去"存在就更新"的分支判断

		guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
			return
		}

		let attributes: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account.rawValue,
			kSecValueData as String: data,
			// 只在本机可用、且设备解锁后才可读。不参与 iCloud 钥匙串同步。
			kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
		]
		SecItemAdd(attributes as CFDictionary, nil)
	}
}
