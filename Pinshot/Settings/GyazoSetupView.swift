import AppKit
import Combine
import SwiftUI

/// Gyazo につなぐまでの案内の窓（3 つの手順を、上から順に進めてもらう）。
/// 利用者が自分の Gyazo にアプリを登録して、アクセストークンを作り、ここに貼る
/// （Pinshot の合言葉 client_secret は作らない・配らない）
@MainActor
final class GyazoSetupWindowController {
    static let shared = GyazoSetupWindowController()

    private var window: NSWindow?
    private var model: GyazoSetupModel?

    func show() {
        // 閉じていた窓を開き直すときは、前に開いたときの状態（打ちかけのトークン・使えなかった知らせ）を捨て、
        // つながっているかを取り直す（設定の「外す」で外したあとに開くと、手順から出す）
        if let window, !window.isVisible { model?.reset() }
        if window == nil {
            let model = GyazoSetupModel()
            model.close = { [weak self] in self?.window?.close() }
            let hosting = NSHostingController(rootView: GyazoSetupView(model: model))
            hosting.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable]
            window.title = "Gyazo につなぐ"
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
            self.model = model
        }
        if let window { DockIcon.show(for: window) }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// 案内の状態
@MainActor
final class GyazoSetupModel: ObservableObject {
    /// 貼った文字列
    @Published var tokenText = ""
    /// 確かめている途中か
    @Published private(set) var isChecking = false
    /// つながったアカウントの名前（つながったら、名前が分からなくても空文字）
    @Published private(set) var connectedName: String?
    /// 確かめて使えなかったときの知らせ
    @Published private(set) var errorText: String?
    /// 直前にコピーしたことを知らせる（「コピーしました」）
    @Published private(set) var copiedValue: String?

    var close: () -> Void = {}

    /// 登録するときに入れる値（コピーして、Gyazo の欄に貼ってもらう）
    static let appName = "Pinshot"
    static let callbackURL = "http://localhost"

    private var destination: UploadDestination? { UploadDestinations.destination(for: .gyazo) }
    private var accountObserver: AnyCancellable?

    init() {
        syncConnection()
        // 設定の「外す」など、ほかの所でつないだ・外したら、出している中身も合わせる
        accountObserver = NotificationCenter.default.publisher(for: .uploadAccountDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncConnection() }
    }

    /// 開き直したとき、前の状態を捨てる（打ちかけのトークン・使えなかった知らせ・コピーの知らせ）
    func reset() {
        tokenText = ""
        errorText = nil
        copiedValue = nil
        syncConnection()
    }

    /// つながっているかを、上げる先から取り直す
    private func syncConnection() {
        let signedIn = destination?.isSignedIn == true
        if signedIn, connectedName == nil {
            connectedName = ""
            Task { await loadName() }
        } else if !signedIn, connectedName != nil {
            connectedName = nil
        }
    }

    var canConnect: Bool {
        !tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isChecking
    }

    // MARK: - 手順のボタン

    func openNewApplicationPage() {
        NSWorkspace.shared.open(GyazoDestination.newApplicationURL)
    }

    func openApplicationsPage() {
        NSWorkspace.shared.open(GyazoDestination.applicationsURL)
    }

    func copy(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        copiedValue = value
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedValue == value { copiedValue = nil }
        }
    }

    // MARK: - つなぐ

    /// コピーしてきたトークンを貼って、そのままつなぐ（押したときだけクリップボードを読む）
    func pasteAndConnect() {
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard UploadRules.looksLikeAccessToken(text) else {
            errorText = "クリップボードに、トークンらしい文字列がありません。手順 2 で「Generate」を押して出た文字列をコピーしてから、もう一度押してください。"
            return
        }
        tokenText = text
        connect()
    }

    func connect() {
        guard let destination, canConnect else { return }
        isChecking = true
        errorText = nil
        let token = tokenText
        Task {
            defer { isChecking = false }
            do {
                try await destination.useToken(token)
                tokenText = ""
                connectedName = ""
                await loadName()
                NotificationCenter.default.post(name: .uploadAccountDidChange, object: nil)
            } catch {
                errorText = "このトークンでは、つなげませんでした。手順 2 で作った文字列を、そのまま貼ってください。"
            }
        }
    }

    func disconnect() {
        guard let destination else { return }
        Task {
            await destination.signOut()
            connectedName = nil
            NotificationCenter.default.post(name: .uploadAccountDidChange, object: nil)
        }
    }

    private func loadName() async {
        let name = try? await destination?.accountName()
        if connectedName != nil { connectedName = (name ?? nil) ?? "" }
    }
}

extension Notification.Name {
    /// 上げる先にログインした・ログアウトした（設定の表示を直す）
    static let uploadAccountDidChange = Notification.Name("Pinshot.uploadAccountDidChange")
}

/// 案内の中身
struct GyazoSetupView: View {
    @ObservedObject var model: GyazoSetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let name = model.connectedName {
                connected(name)
            } else {
                header
                step(1, "Gyazo にアプリを登録する") {
                    Text("下のボタンで Gyazo の登録ページを開きます（Gyazo にログインしていなければ、ログインしてください）。「名前」と「Callback URL」の欄に、次の値を貼って登録します。")
                        .fixedSize(horizontal: false, vertical: true)
                    valueRow("名前", GyazoSetupModel.appName)
                    valueRow("Callback URL", GyazoSetupModel.callbackURL, note: "使いませんが、入れないと登録できません")
                    Button("登録ページを開く") { model.openNewApplicationPage() }
                        .buttonStyle(.borderedProminent)
                }
                step(2, "アクセストークンを作ってコピーする") {
                    Text("登録したアプリのページで「Generate」（アクセストークンを作る）を押し、出た文字列をコピーします。ページを閉じてしまったら、アプリの一覧から開き直せます。")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("アプリの一覧を開く") { model.openApplicationsPage() }
                }
                step(3, "Pinshot に貼ってつなぐ") {
                    Text("コピーしたら、下の「貼り付けてつなぐ」を押します（欄に貼って「つなぐ」でもかまいません）。")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("貼り付けてつなぐ") { model.pasteAndConnect() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isChecking)
                        SecureField("アクセストークン", text: $model.tokenText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { model.connect() }
                    }
                    if let error = model.errorText {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        if model.isChecking {
                            ProgressView().controlSize(.small)
                            Text("確かめています…").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("つなぐ") { model.connect() }
                            .disabled(!model.canConnect)
                    }
                }
                footer
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gyazo につなぐ")
                .font(.title2.bold())
            Text("あなたの Gyazo に、Pinshot 用のアプリを登録してつなぎます。3 つの手順で、数分で終わります。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        Text("アプリはあなたの Gyazo のアカウントに登録されます。トークンはこの Mac のキーチェーンに保存し、ほかには送りません。やめるときは、Gyazo でアプリを消してください。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 番号付きの手順
    private func step<Content: View>(_ number: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content()
            }
        }
    }

    /// 登録の欄に貼る値と、コピーのボタン
    private func valueRow(_ label: String, _ value: String, note: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.body.monospaced())
                .textSelection(.enabled)
            Spacer()
            Button(model.copiedValue == value ? "コピーしました" : "コピー") { model.copy(value) }
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
        .help(note ?? "")
    }

    /// つながったとき
    private func connected(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(name.isEmpty ? "Gyazo につながりました" : "\(name) の Gyazo につながりました", systemImage: "checkmark.circle.fill")
                .font(.title3.bold())
                .foregroundStyle(.green)
            Text("浮かせた画像で ⌘U（か右クリックの「アップロードしてリンクをコピー」）を押すと、Gyazo に上げてリンクをコピーします。")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("つなぐのをやめる") { model.disconnect() }
                Spacer()
                Button("閉じる") { model.close() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
