import ServiceManagement
import SwiftUI

/// 一般（見た目・キャプチャ・許可・起動・このアプリについて）
struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var loginItem: LoginItemModel
    @ObservedObject var permission: PermissionModel

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        SettingsPane {
            Section("表示") {
                OptionPicker("見た目", info: "ツールバー・メニュー・設定などの色です。「システム」なら、Mac のライト / ダークの設定に合わせます。", selection: $settings.appearance)
                .pickerStyle(.segmented)
            }
            Section("キャプチャ") {
                Picker(selection: $settings.detailedCaptureUI) {
                    Text("シンプル").tag(false)
                    Text("くわしく").tag(true)
                } label: {
                    SettingTitle("範囲を選ぶ画面", info: "シンプル：画面はそのままで、カーソルの横に座標を出します。\nくわしく：画面を暗くして、ルーペと十字線を出します。1 ピクセル単位で合わせたいときに。")
                }
                .pickerStyle(.segmented)
                Toggle("撮ったら、クリップボードにもコピーする", isOn: $settings.copyAfterCapture)
            }
            Section {
                PermissionRow(
                    title: "画面収録",
                    detail: "画面を撮るのに必要です。",
                    isGranted: permission.granted,
                    request: { permission.request() }
                )
                PermissionRow(
                    title: "アクセシビリティ",
                    detail: "スクロールキャプチャで自動でスクロールするのと、メニューを開いたままショートカットで撮るのに使います。",
                    isGranted: permission.accessibilityGranted,
                    request: { permission.requestAccessibility() }
                )
            } header: {
                Text("許可")
            } footer: {
                if !permission.granted, permission.requested {
                    HStack {
                        SettingsNote("システム設定で Pinshot をオンにしたら、Pinshot を再起動してください。")
                        Spacer()
                        Button("Pinshot を再起動") { AppRelauncher.relaunch() }
                            .controlSize(.small)
                            .hoverRole()
                    }
                }
            }
            Section("起動") {
                Toggle("ログイン時に Pinshot を起動する", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.set($0) }
                ))
                if let message = loginItem.errorMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            Section("Pinshot について") {
                LabeledContent("バージョン", value: version)
                LabeledContent("使い方") {
                    Button("使い方を見る…") { WelcomeWindowController.shared.show() }
                        .hoverRole()
                }
            }
        }
    }
}

/// 許可の 1 行（許可済みならチェック、まだならボタン）
private struct PermissionRow: View {
    let title: String
    let detail: String
    let isGranted: Bool
    let request: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingTitle(title, info: detail)
            Spacer()
            if isGranted {
                Label("許可済み", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("許可する…", action: request)
                    .hoverRole()
            }
        }
    }
}

/// ログイン時に起動するかどうか（SMAppService）
@MainActor
final class LoginItemModel: ObservableObject {
    @Published private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var errorMessage: String?

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = "設定できませんでした: \(error.localizedDescription)"
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
