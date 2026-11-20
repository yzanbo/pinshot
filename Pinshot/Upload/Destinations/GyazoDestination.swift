import Foundation

/// Gyazo に上げる。
/// 利用者が自分で Gyazo にアプリを登録して作った許可証（アクセストークン）を、設定に貼ってもらう
/// （Pinshot の合言葉 client_secret は作らない・配らない）。許可証には期限がない
@MainActor
final class GyazoDestination: UploadDestination {
    let id = UploadDestinationID.gyazo
    let signInStyle = UploadSignInStyle.pastedToken
    let capabilities = UploadCapabilities(
        // 動画を API で上げられるかは資料に書かれていないので、上げない
        uploadsMovies: false,
        providesDirectURL: true,
        canDelete: true,
        // 大きさの上限は資料に書かれていない
        maxFileBytes: nil
    )

    /// 登録したアプリの一覧（アクセストークンを作り直すところ）
    static let applicationsURL = URL(string: "https://gyazo.com/oauth/applications")!
    /// 新しいアプリを登録するページ
    static let newApplicationURL = URL(string: "https://gyazo.com/oauth/applications/new")!

    /// 読んだ許可証（キーチェーンを何度も読まないよう、覚えておく）
    private var token: String?
    private var loaded = false

    private var currentToken: String? {
        if !loaded {
            token = KeychainTokenStore.load(for: id)?.accessToken
            loaded = true
        }
        return token
    }

    var isSignedIn: Bool { currentToken != nil }

    // MARK: - 許可証

    /// 貼った許可証が使えるか確かめてから、キーチェーンに置く
    func useToken(_ text: String) async throws {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw UploadError.notSignedIn(id) }
        _ = try await currentUser(token: token)
        try KeychainTokenStore.save(OAuthToken(accessToken: token, refreshToken: nil, expiresAt: nil), for: id)
        self.token = token
        loaded = true
    }

    /// 許可証を手放す（Gyazo での取り消しは、利用者が Gyazo でアプリを消して行う）
    func signOut() async {
        KeychainTokenStore.delete(for: id)
        token = nil
        loaded = true
    }

    func accountName() async throws -> String? {
        guard let token = currentToken else { return nil }
        return try await currentUser(token: token).name
    }

    private func currentUser(token: String) async throws -> User {
        var request = URLRequest(url: URL(string: "https://api.gyazo.com/api/users/me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data = try await UploadHTTP.send(request, for: id)
        return try UploadHTTP.decode(UserResponse.self, from: data, for: id).user
    }

    // MARK: - 上げる・リンク・消す

    func upload(_ item: UploadItem, progress: @escaping UploadProgress) async throws -> RemoteFile {
        guard let token = currentToken else { throw UploadError.notSignedIn(id) }
        guard item.kind != .movie else { throw UploadError.unsupportedKind(id, item.kind) }
        let data: Data
        switch item.payload {
        case .data(let bytes): data = bytes
        case .file(let url): data = try Data(contentsOf: url)
        }
        var form = MultipartForm()
        form.addField(name: "access_policy", value: "anyone")
        form.addField(name: "app", value: "Pinshot")
        form.addFile(name: "imagedata", fileName: item.fileName, mimeType: item.kind.mimeType, data: data)

        var request = URLRequest(url: URL(string: "https://upload.gyazo.com/api/upload")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        let response = try await UploadHTTP.upload(request, body: form.finalized(), for: id, progress: progress)
        let image = try UploadHTTP.decode(Image.self, from: response, for: id)
        var info: [String: String] = [:]
        info["pageURL"] = image.permalinkURL?.absoluteString
        info["directURL"] = image.url?.absoluteString
        return RemoteFile(destination: id, id: image.imageID, info: info)
    }

    func shareLink(for file: RemoteFile) async throws -> SharedLink {
        // 上げたときの返事に URL が入っているので、ふつうはそれを使う（回数の上限を使わない）
        if let page = file.info["pageURL"].flatMap(URL.init(string:)) {
            return SharedLink(pageURL: page, directURL: file.info["directURL"].flatMap(URL.init(string:)))
        }
        guard let token = currentToken else { throw UploadError.notSignedIn(id) }
        var request = URLRequest(url: URL(string: "https://api.gyazo.com/api/images/\(file.id)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data = try await UploadHTTP.send(request, for: id)
        let image = try UploadHTTP.decode(Image.self, from: data, for: id)
        guard let page = image.permalinkURL else { throw UploadError.invalidResponse(id) }
        return SharedLink(pageURL: page, directURL: image.url)
    }

    func delete(_ file: RemoteFile) async throws {
        guard let token = currentToken else { throw UploadError.notSignedIn(id) }
        var request = URLRequest(url: URL(string: "https://api.gyazo.com/api/images/\(file.id)")!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await UploadHTTP.send(request, for: id)
    }

    // MARK: - 受け取る形

    private struct Image: Decodable {
        let imageID: String
        /// ページの URL（https://gyazo.com/…）
        let permalinkURL: URL?
        /// 画像そのものの URL（https://i.gyazo.com/….png）
        let url: URL?

        enum CodingKeys: String, CodingKey {
            case imageID = "image_id"
            case permalinkURL = "permalink_url"
            case url
        }
    }

    private struct UserResponse: Decodable {
        let user: User
    }

    private struct User: Decodable {
        let name: String?
    }
}
