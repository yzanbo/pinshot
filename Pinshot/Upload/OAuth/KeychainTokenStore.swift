import Foundation
import Security

/// 保存先の許可証を、キーチェーンに置く（保存先ごとに 1 つ。中身は OAuthToken の JSON）。
/// アドホック署名だと、ビルドし直すたびに macOS がキーチェーンへのアクセスを確かめることがある
/// （「yzanbo Code Signing」の証明書（make cert）で署名すると、聞かれにくい）
enum KeychainTokenStore {
    /// キーチェーンでの置き場所の名前。アプリの ID から作る（配る Pinshot では dev.portfolio.pinshot.upload。
    /// ID の違う更新の試験用アプリは別の名前になり、ふだんの Pinshot の許可証を読んだり消したりしない）
    private static let service = (Bundle.main.bundleIdentifier ?? "dev.portfolio.pinshot") + ".upload"

    static func load(for destination: UploadDestinationID) -> OAuthToken? {
        var query = baseQuery(for: destination)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(OAuthToken.self, from: data)
    }

    /// 置く（前のものがあれば置き換える）
    static func save(_ token: OAuthToken, for destination: UploadDestinationID) throws {
        let data = try JSONEncoder().encode(token)
        let query = baseQuery(for: destination)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            // 画面のロックを解いたあとなら、裏からも読める（撮ったらすぐ上げるため）
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            item[kSecAttrLabel as String] = "Pinshot（\(destination.label) の許可証）"
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func delete(for destination: UploadDestinationID) {
        SecItemDelete(baseQuery(for: destination) as CFDictionary)
    }

    private static func baseQuery(for destination: UploadDestinationID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: destination.rawValue,
        ]
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return "キーチェーンに保存できませんでした（\(message)）"
        }
    }
}
