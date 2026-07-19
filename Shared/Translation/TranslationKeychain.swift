//
//  TranslationKeychain.swift
//  NetNewsWire — AI 翻译 fork
//
//  把翻译服务的 API key 存进系统钥匙串(Keychain)。
//
//  为什么用 Keychain 而不是普通的偏好设置:
//  API key 是密钥。普通偏好设置存成明文 plist,任何能读到 app 数据的人都能看见。
//  Keychain 是 iOS 提供的加密保险箱,专门放这类东西。
//
//  ⚠️ 注意:本文件**没有**使用项目里已有的 Modules/Secrets/CredentialsManager,
//  因为那属于 CLAUDE.md 第 2 节列的 A 级禁区(账户/凭据体系)。
//  这里用系统 Security 框架自己实现,不碰上游任何代码。
//
//  这个文件不属于上游 NetNewsWire,是本 fork 新增的。
//

import Foundation
import Security

enum TranslationKeychain {

	/// 钥匙串条目的归属标识。用本 fork 专属的名字,避免和上游的账户凭据混在一起。
	private static let service = "NetNewsWire.AITranslation"

	/// 条目名。将来若要支持多个服务商,可以按服务商分成多条。
	private static let account = "translation-api-key"

	/// 读出 API key。没存过返回 nil。
	static func readAPIKey() -> String? {

		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne
		]

		var item: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &item)

		guard status == errSecSuccess,
			  let data = item as? Data,
			  let key = String(data: data, encoding: .utf8),
			  !key.isEmpty else {
			return nil
		}

		return key
	}

	/// 存入 API key。传空字符串等同于删除。
	@discardableResult
	static func saveAPIKey(_ key: String) -> Bool {

		let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)

		guard !trimmed.isEmpty else {
			return deleteAPIKey()
		}

		guard let data = trimmed.data(using: .utf8) else {
			return false
		}

		// 先删再加,省去"存在就更新、不存在就新建"的分支判断
		_ = deleteAPIKey()

		let attributes: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecValueData as String: data,
			// 只在本机可用、且设备解锁后才可读。不参与 iCloud 钥匙串同步。
			kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
		]

		return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
	}

	/// 删除已存的 API key。
	@discardableResult
	static func deleteAPIKey() -> Bool {

		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account
		]

		let status = SecItemDelete(query as CFDictionary)
		return status == errSecSuccess || status == errSecItemNotFound
	}
}
