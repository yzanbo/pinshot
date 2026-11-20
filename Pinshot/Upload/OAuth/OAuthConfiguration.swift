import Foundation

// OAuth 2.0 のログインの決まり（画面やネットに関わらない部分。テストにも入れる）。
// 保存先ごとに違うのは OAuthConfiguration の中身（接続先・権限の名前・戻り先）だけにする

/// ログインのあと、引換券（認可コード）を受け取る場所
enum OAuthRedirect: Equatable {
    /// Pinshot の中に、ログインの間だけ受け口を開く（http://localhost:番号/path）。
    /// ports は登録してある番号で、空いている最初の番号を使う
    case loopback(ports: [UInt16], path: String)

    /// localhost の戻り先の URL
    static func loopbackURI(port: UInt16, path: String) -> String {
        "http://localhost:\(port)\(path)"
    }
}

/// 保存先ごとの、ログインの設定
struct OAuthConfiguration: Equatable {
    /// ログインの画面（利用者が「許可する」を押すところ）
    var authorizeURL: URL
    /// 引換券を許可証に替えるところ
    var tokenURL: URL
    /// アプリの番号（client_id）。PKCE で使うものは公開してよい値
    var clientID: String
    /// 求める権限の名前
    var scopes: [String]
    /// 保存先ごとに足す値（リフレッシュトークンを求める token_access_type=offline など）
    var extraAuthorizeParameters: [String: String] = [:]
    var redirect: OAuthRedirect

    /// ログインの画面の URL。redirectURI が nil なら戻り先を付けない（保存先の画面に出た文字列を、利用者が貼る形）
    func authorizationURL(redirectURI: String?, state: String, pkce: PKCE) -> URL {
        var parts = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        var items = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
            URLQueryItem(name: "state", value: state),
        ]
        if let redirectURI {
            items.append(URLQueryItem(name: "redirect_uri", value: redirectURI))
        }
        if !scopes.isEmpty {
            items.append(URLQueryItem(name: "scope", value: scopes.joined(separator: " ")))
        }
        // 並びを決めておく（テストで確かめやすくする）
        for key in extraAuthorizeParameters.keys.sorted() {
            items.append(URLQueryItem(name: key, value: extraAuthorizeParameters[key]))
        }
        parts.queryItems = items
        return parts.url ?? authorizeURL
    }

    /// 引換券を許可証に替えるときの本文（application/x-www-form-urlencoded）
    func tokenRequestBody(code: String, pkce: PKCE, redirectURI: String?) -> Data {
        var fields = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("code_verifier", pkce.verifier),
            ("client_id", clientID),
        ]
        if let redirectURI {
            fields.append(("redirect_uri", redirectURI))
        }
        return OAuthForm.encode(fields)
    }

    /// 許可証を取り直すときの本文
    func refreshRequestBody(refreshToken: String) -> Data {
        OAuthForm.encode([
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", clientID),
        ])
    }
}

/// application/x-www-form-urlencoded の本文を作る
enum OAuthForm {
    /// 値に使ってよい文字（ほかは %XX にする）
    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func encode(_ fields: [(String, String)]) -> Data {
        let text = fields
            .map { "\(escape($0.0))=\(escape($0.1))" }
            .joined(separator: "&")
        return Data(text.utf8)
    }

    static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

/// 許可証（アクセストークン）と、取り直すための許可証（リフレッシュトークン）。キーチェーンに JSON で置く
struct OAuthToken: Codable, Equatable {
    var accessToken: String
    /// 取り直すための許可証（ない保存先・貼った許可証では nil）
    var refreshToken: String?
    /// 許可証が切れる時刻（期限がなければ nil）
    var expiresAt: Date?

    /// そろそろ切れるか（切れる 2 分前から、取り直す）
    func needsRefresh(now: Date = Date(), margin: TimeInterval = 120) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) <= margin
    }
}

/// 許可証を受け取ったときの返事（RFC 6749 の形）
struct OAuthTokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Double?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }

    /// 返事を許可証にする。取り直したときの返事に refresh_token がなければ、前のものを使い続ける
    func token(receivedAt now: Date = Date(), keepingRefreshToken previous: String? = nil) -> OAuthToken {
        OAuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken ?? previous,
            expiresAt: expiresIn.map { now.addingTimeInterval($0) }
        )
    }
}

/// ログインの戻り先に届いた知らせ（引換券か、断られた理由）
enum OAuthCallback: Equatable {
    case code(String, state: String?)
    case denied(String)

    /// 戻り先の URL から読む（code があれば引換券、error があれば断られた）
    init?(url: URL) {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let code = value("code"), !code.isEmpty {
            self = .code(code, state: value("state"))
        } else if let error = value("error") {
            self = .denied(value("error_description") ?? error)
        } else {
            return nil
        }
    }

    /// localhost の受け口に届いた HTTP の頭の行（例: 「GET /oauth/callback?code=…&state=… HTTP/1.1」）から読む。
    /// path が違うもの（ブラウザが勝手に聞く favicon など）は nil
    init?(requestLine: String, expectedPath: String) {
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let url = URL(string: "http://localhost" + parts[1]),
              url.path == expectedPath else { return nil }
        self.init(url: url)
    }
}
