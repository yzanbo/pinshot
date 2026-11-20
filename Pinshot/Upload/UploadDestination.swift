import Foundation

/// 上げる保存先（いまは Gyazo。あとで Dropbox・Google Drive・OneDrive・Box も足せるようにしておく）。
/// 保存先ごとに「上げる」「共有リンクを作る」「消す」と、できること（capabilities）を持つ。
/// 自動で上げる・URL をコピーする・知らせる・履歴に残す、は保存先に関わらず UploadCenter が行う
@MainActor
protocol UploadDestination: AnyObject {
    var id: UploadDestinationID { get }
    var capabilities: UploadCapabilities { get }
    /// ログインの仕方（設定の画面で出し分ける）
    var signInStyle: UploadSignInStyle { get }
    /// ログインしているか（許可証を持っているか）
    var isSignedIn: Bool { get }

    /// 上げる。上げたファイルを返す。progress には、送った割合（0〜1）を渡す
    func upload(_ item: UploadItem, progress: @escaping UploadProgress) async throws -> RemoteFile
    /// 上げたファイルの共有リンクを作る（もうあれば、それを返す）
    func shareLink(for file: RemoteFile) async throws -> SharedLink
    /// 上げたファイルを消す（capabilities.canDelete が true のときだけ呼ぶ）
    func delete(_ file: RemoteFile) async throws
    /// ログアウトする（許可証を手放す。保存先で取り消せるものは取り消す）
    func signOut() async

    /// ログインの画面を開いてログインする（signInStyle が .oauth の保存先）
    func signIn() async throws
    /// 利用者が貼った許可証を使う（signInStyle が .pastedToken の保存先。使えるか確かめてから覚える）
    func useToken(_ token: String) async throws
    /// つないでいるアカウントの名前（設定に出す。出せなければ nil）
    func accountName() async throws -> String?
}

extension UploadDestination {
    func signIn() async throws {
        throw UploadError.notSignedIn(id)
    }

    func useToken(_ token: String) async throws {
        throw UploadError.notSignedIn(id)
    }

    func accountName() async throws -> String? { nil }
}

/// 使える保存先の一覧（アプリの番号がない版では、その保存先は出さない）
@MainActor
enum UploadDestinations {
    private static var cache: [UploadDestinationID: UploadDestination] = [:]

    /// id の保存先（この版で使えなければ nil）
    static func destination(for id: UploadDestinationID) -> UploadDestination? {
        if let cached = cache[id] { return cached }
        let made: UploadDestination?
        switch id {
        // Gyazo は、利用者が貼った許可証を使うので、アプリの番号が要らない（いつも使える）
        case .gyazo: made = GyazoDestination()
        }
        cache[id] = made
        return made
    }

    /// この版で使える保存先
    static var available: [UploadDestinationID] {
        UploadDestinationID.allCases.filter { destination(for: $0) != nil }
    }

    /// 設定で選んでいる保存先（選んでいない・この版で使えなければ nil）
    static var current: UploadDestination? {
        AppSettings.shared.uploadDestination.flatMap(destination(for:))
    }
}

/// ログインの仕方
enum UploadSignInStyle {
    /// ログインの画面を開き、「許可する」を押してもらう（OAuthClient を使う保存先）
    case oauth
    /// 利用者が保存先で作った許可証を、設定に貼ってもらう（Gyazo）
    case pastedToken
}
