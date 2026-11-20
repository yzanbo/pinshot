import AppKit
import SwiftUI

/// 共有リンク（上げる先とログイン・コピーする形）。
/// 上げたものは、利用者のアカウントの保存先に入る（Pinshot のサーバーは通らない）
struct ShareSettingsView: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var account = UploadAccountModel()

    var body: some View {
        SettingsPane {
            Section {
                destinationPicker
                if let id = settings.uploadDestination, let destination = UploadDestinations.destination(for: id) {
                    accountRow(id, style: destination.signInStyle)
                }
            } header: {
                SettingTitle("共有リンク", info: "画像を上げて、共有リンクをクリップボードに入れます。Slack・Discord・GitHub などに貼ると、その場で画像が出ます。\n\n上げるのは、あなたのアカウントの保存先です（Pinshot のサーバーは通りません）。リンクを知っている人は、誰でも見られます。\n\n画像の右クリック（か操作バーの「…」）の「アップロードしてリンクをコピー」（⌘U）で上げます。")
            }

            Section {
                OptionPicker(
                    "クリップボードに入れる形",
                    info: "画像の URL と Markdown は、貼るとその場で画像が出ます。画像そのものの URL を出せない保存先では、ページの URL になります。",
                    selection: $settings.shareLinkFormat
                )
                Toggle(isOn: autoUploadBinding) {
                    SettingTitle("撮ったら自動で上げる", info: "撮るたびに、撮ったままの画像（書き込み前）をすぐ上げて、共有リンクをコピーします。初期設定はオフです。\n\n撮った画像が外のサービスに送られるので、パスワードや個人情報が写っていないか気をつけてください。「撮ったらクリップボードにもコピー」もオンのときは、上げ終えたらリンクに置き換わります。")
                }
                .disabled(settings.uploadDestination == nil)
                Toggle(isOn: notifyBinding) {
                    SettingTitle("上げ終えたら通知する", info: "上げ終えたとき・上げられなかったときに、macOS の通知を出します。通知を押すと、リンクをブラウザで開きます。初めて上げるときに、macOS が通知の許可を確かめます。")
                }
                LabeledContent("上げたもの") {
                    Button("一覧を開く…") { CaptureHistoryWindowController.shared.show(tab: .uploads) }
                }
            } header: {
                Text("上げ方")
            }
        }
        .onAppear { account.refresh(for: settings.uploadDestination) }
        // 案内の窓でつないだ・やめたら、表示を直す
        .onReceive(NotificationCenter.default.publisher(for: .uploadAccountDidChange)) { _ in
            account.refresh(for: settings.uploadDestination)
        }
        .onChange(of: settings.uploadDestination) { _, id in
            account.refresh(for: id)
            // Gyazo を選んで、まだつないでいなければ、つなぐまでの案内を出す
            if let id, let destination = UploadDestinations.destination(for: id),
               destination.signInStyle == .pastedToken, !destination.isSignedIn {
                GyazoSetupWindowController.shared.show()
            }
        }
    }

    /// 自動で上げる。オンにするときは、画像が外に送られることを確かめる
    private var autoUploadBinding: Binding<Bool> {
        Binding(
            get: { settings.autoUploadCaptures },
            set: { enabled in
                guard enabled else {
                    settings.autoUploadCaptures = false
                    return
                }
                let label = settings.uploadDestination?.label ?? "上げる先"
                AppAlert.confirm(
                    "撮るたびに、\(label) に自動で上げますか？",
                    detail: "撮った画像は、すぐ \(label) に送られ、リンクを知っている人なら誰でも見られるようになります。パスワードや個人情報が写っていないか気をつけてください。設定でいつでも止められます。",
                    confirmTitle: "自動で上げる"
                ) {
                    settings.autoUploadCaptures = true
                }
            }
        )
    }

    /// 通知する。オンにしたら、macOS に通知の許可を求める
    private var notifyBinding: Binding<Bool> {
        Binding(
            get: { settings.notifiesUploads },
            set: { enabled in
                settings.notifiesUploads = enabled
                if enabled { UploadNotifier.shared.requestPermission() }
            }
        )
    }

    /// 上げる先（なし・Gyazo など）
    private var destinationPicker: some View {
        Picker(selection: $settings.uploadDestination) {
            Text("なし").tag(UploadDestinationID?.none)
            ForEach(UploadDestinations.available) { id in
                Text(id.label).tag(UploadDestinationID?.some(id))
            }
        } label: {
            SettingTitle("上げる先", info: "Gyazo：あなたの Gyazo に入ります（誰でも見られる設定で上げます）。動画は上げられません。")
        }
    }

    /// ログインの状態と、ログイン・ログアウトのボタン
    private func accountRow(_ id: UploadDestinationID, style: UploadSignInStyle) -> some View {
        LabeledContent(id.label) {
            HStack(spacing: 8) {
                if account.isWorking {
                    ProgressView().controlSize(.small)
                }
                Text(account.statusText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if account.isSignedIn {
                    Button(account.usesPastedToken ? "外す" : "ログアウト") { account.signOut() }
                        .disabled(account.isWorking)
                } else if style == .pastedToken {
                    // 許可証の作り方から貼るまでを、案内の窓で 1 つずつ進めてもらう
                    Button("\(id.label) につなぐ…") { GyazoSetupWindowController.shared.show() }
                } else {
                    Button("ログイン…") { account.signIn() }
                        .disabled(account.isWorking)
                }
            }
        }
    }

}

/// 選んでいる上げる先のログインの状態（設定に出す）
@MainActor
final class UploadAccountModel: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var accountName: String?
    /// ログイン・ログアウトの途中なら、その知らせ
    @Published private(set) var workingText: String?
    private var destinationID: UploadDestinationID?

    /// 許可証を貼る保存先か（Gyazo）
    var usesPastedToken: Bool { destination?.signInStyle == .pastedToken }

    var isWorking: Bool { workingText != nil }

    var statusText: String {
        if let workingText { return workingText }
        guard isSignedIn else { return usesPastedToken ? "つながっていません" : "ログインしていません" }
        return accountName.map { "\($0) でログイン中" } ?? "ログイン中"
    }

    private var destination: UploadDestination? {
        destinationID.flatMap(UploadDestinations.destination(for:))
    }

    func refresh(for id: UploadDestinationID?) {
        destinationID = id
        isSignedIn = destination?.isSignedIn ?? false
        accountName = nil
        guard isSignedIn, let destination else { return }
        Task {
            let name = try? await destination.accountName()
            if destination.id == self.destinationID { self.accountName = name ?? nil }
        }
    }

    func signIn() {
        guard let destination else { return }
        workingText = "ログインしています…"
        Task {
            defer { workingText = nil }
            do {
                try await destination.signIn()
            } catch UploadError.cancelled {
                // やめたときは何も出さない
            } catch {
                AppAlert.inform("\(destination.id.label) にログインできませんでした", detail: error.localizedDescription)
            }
            refresh(for: destinationID)
        }
    }

    func signOut() {
        guard let destination else { return }
        workingText = "ログアウトしています…"
        Task {
            await destination.signOut()
            workingText = nil
            refresh(for: destinationID)
        }
    }
}
