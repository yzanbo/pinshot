import AppKit
import AuthenticationServices

/// OAuth 2.0 のログイン（どの保存先でも同じ部品）。
/// ログインの画面は ASWebAuthenticationSession で出し、引換券は localhost の受け口で受け取る。
/// 受け口の番号がどれも使われていたら、ブラウザでログインして、画面に出た文字列を貼ってもらう
@MainActor
final class OAuthClient: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthClient()

    private var session: ASWebAuthenticationSession?

    /// ログインして、許可証を受け取る
    func signIn(with configuration: OAuthConfiguration, for destination: UploadDestinationID) async throws -> OAuthToken {
        let pkce = PKCE.generate()
        let state = PKCE.randomURLSafeString(byteCount: 16)
        switch configuration.redirect {
        case .loopback(let ports, let path):
            if let receiver = await LoopbackReceiver.start(ports: ports, path: path) {
                defer { receiver.stop() }
                let redirectURI = OAuthRedirect.loopbackURI(port: receiver.port, path: path)
                let url = configuration.authorizationURL(redirectURI: redirectURI, state: state, pkce: pkce)
                let callback = try await authorize(url, receiver: receiver)
                let code = try Self.code(from: callback, expectedState: state)
                return try await exchange(code: code, pkce: pkce, redirectURI: redirectURI, configuration: configuration, for: destination)
            }
            // 受け口を開けないときは、戻り先を付けずにログインして、出た文字列を貼ってもらう
            let url = configuration.authorizationURL(redirectURI: nil, state: state, pkce: pkce)
            NSWorkspace.shared.open(url)
            guard let code = Self.askForCode(destination) else { throw UploadError.cancelled }
            return try await exchange(code: code, pkce: pkce, redirectURI: nil, configuration: configuration, for: destination)
        }
    }

    /// 許可証を取り直す
    func refresh(_ token: OAuthToken, with configuration: OAuthConfiguration, for destination: UploadDestinationID) async throws -> OAuthToken {
        guard let refreshToken = token.refreshToken else { throw UploadError.notSignedIn(destination) }
        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = configuration.refreshRequestBody(refreshToken: refreshToken)
        let data: Data
        do {
            data = try await UploadHTTP.send(request, for: destination)
        } catch UploadError.server(_, let status, _) where status == 400 {
            // 取り直す許可証が取り消された・切れた
            throw UploadError.notSignedIn(destination)
        }
        let response = try UploadHTTP.decode(OAuthTokenResponse.self, from: data, for: destination)
        return response.token(keepingRefreshToken: refreshToken)
    }

    // MARK: - ログインの画面

    /// ログインの画面を出し、受け口に引換券が届いたら閉じる（利用者が画面を閉じたら、やめたことにする）
    private func authorize(_ url: URL, receiver: LoopbackReceiver) async throws -> OAuthCallback {
        NSApp.activate(ignoringOtherApps: true)
        return try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            let finish: @MainActor (Result<OAuthCallback, Error>) -> Void = { [weak self] result in
                guard once.claim() else { return }
                self?.session?.cancel()
                self?.session = nil
                continuation.resume(with: result)
            }
            // 戻り先は localhost なので、画面のほうでは受け取らない（閉じられたときだけ知らせが来る）
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { _, _ in
                Task { @MainActor in finish(.failure(UploadError.cancelled)) }
            }
            session.presentationContextProvider = self
            self.session = session
            Task {
                do {
                    let callback = try await receiver.waitForCallback()
                    await MainActor.run { finish(.success(callback)) }
                } catch {
                    await MainActor.run { finish(.failure(error)) }
                }
            }
            if !session.start() {
                finish(.failure(UploadError.cancelled))
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeKey } ?? NSWindow()
        }
    }

    // MARK: - 引換券を許可証に替える

    private func exchange(
        code: String,
        pkce: PKCE,
        redirectURI: String?,
        configuration: OAuthConfiguration,
        for destination: UploadDestinationID
    ) async throws -> OAuthToken {
        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = configuration.tokenRequestBody(code: code, pkce: pkce, redirectURI: redirectURI)
        let data = try await UploadHTTP.send(request, for: destination)
        return try UploadHTTP.decode(OAuthTokenResponse.self, from: data, for: destination).token()
    }

    /// 届いた知らせから引換券を取り出す（state が違うものは、ほかから送られたものとして断る）
    private static func code(from callback: OAuthCallback, expectedState: String) throws -> String {
        switch callback {
        case .code(let code, let state):
            guard state == expectedState else { throw UploadError.cancelled }
            return code
        case .denied:
            throw UploadError.cancelled
        }
    }

    /// 保存先の画面に出た文字列を貼ってもらう（貼らずに閉じたら nil）
    private static func askForCode(_ destination: UploadDestinationID) -> String? {
        let alert = NSAlert()
        alert.messageText = "\(destination.label) の画面に出た文字列を貼ってください"
        alert.informativeText = "ブラウザで \(destination.label) にログインして「許可」を押すと、文字列が出ます。それをコピーして、ここに貼ってください。"
        alert.icon = NSApp.applicationIconImage
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "ここに貼る"
        alert.accessoryView = field
        alert.addButton(withTitle: "ログイン")
        alert.addButton(withTitle: "キャンセル")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let code = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty ? nil : code
    }
}

/// 一度だけ通す印（ログインの画面と受け口の、先に来たほうだけを使う）
@MainActor
private final class Once {
    private var claimed = false

    func claim() -> Bool {
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

/// 保存先 1 つぶんのログインの状態（許可証をキーチェーンに置き、切れそうなら取り直す）
@MainActor
final class OAuthSession {
    let destination: UploadDestinationID
    let configuration: OAuthConfiguration
    /// 読んだ許可証（キーチェーンを何度も読まないよう、覚えておく）
    private var token: OAuthToken?
    private var loaded = false

    init(destination: UploadDestinationID, configuration: OAuthConfiguration) {
        self.destination = destination
        self.configuration = configuration
    }

    var isSignedIn: Bool { currentToken != nil }

    private var currentToken: OAuthToken? {
        if !loaded {
            token = KeychainTokenStore.load(for: destination)
            loaded = true
        }
        return token
    }

    func signIn() async throws {
        let token = try await OAuthClient.shared.signIn(with: configuration, for: destination)
        try store(token)
    }

    /// 使える許可証（切れそうなら取り直す。取り直せなければ、ログインし直しが要る）。
    /// forceRefresh: 保存先に断られた（401）ときに、期限の前でも取り直す
    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard var token = currentToken else { throw UploadError.notSignedIn(destination) }
        if token.needsRefresh() || (forceRefresh && token.refreshToken != nil) {
            do {
                token = try await OAuthClient.shared.refresh(token, with: configuration, for: destination)
                try store(token)
            } catch UploadError.notSignedIn(let destination) {
                forget()
                throw UploadError.notSignedIn(destination)
            }
        }
        return token.accessToken
    }

    /// 許可証を手放す（保存先での取り消しは、保存先ごとに行う）
    func forget() {
        KeychainTokenStore.delete(for: destination)
        token = nil
        loaded = true
    }

    private func store(_ token: OAuthToken) throws {
        try KeychainTokenStore.save(token, for: destination)
        self.token = token
        loaded = true
    }
}
