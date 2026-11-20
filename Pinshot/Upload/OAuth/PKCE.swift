import CryptoKit
import Foundation
import Security

/// PKCE（鍵なしのログイン）の使い捨ての合言葉。
/// ログインのたびに verifier を作り、そのハッシュ（challenge）だけを先に渡す。
/// 引換券を許可証に替えるときに verifier を出すので、引換券を盗んだ人は替えられない（RFC 7636）
struct PKCE: Equatable {
    /// 使い捨ての合言葉（43〜128 文字。使ってよい文字だけ）
    let verifier: String
    /// verifier の SHA256 を base64url にしたもの（ログインの初めに渡す）
    let challenge: String
    /// challenge の作り方（いつも S256）
    let method = "S256"

    init(verifier: String) {
        self.verifier = verifier
        challenge = Self.challenge(for: verifier)
    }

    /// 新しい合言葉を作る（32 バイトの乱数から、43 文字）
    static func generate() -> PKCE {
        PKCE(verifier: randomURLSafeString(byteCount: 32))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// 乱数を base64url にした文字列（state にも使う）
    static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        if status != errSecSuccess {
            // 乱数を取れないことはまずないが、念のため別の乱数で埋める
            bytes = (0..<byteCount).map { _ in UInt8.random(in: 0...255) }
        }
        return base64URL(Data(bytes))
    }

    /// base64url（+ を -、/ を _ にし、末尾の = を外す）
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
