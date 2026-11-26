import ServiceManagement
import SwiftUI

/// 一般（見た目・キャプチャ・許可・起動・このアプリについて（版とアップデート））
struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var loginItem: LoginItemModel
    @ObservedObject var permission: PermissionModel
    @ObservedObject var updates: AppUpdates

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
                Toggle("撮ったら（録画は止めたら）、クリップボードにもコピーする", isOn: $settings.copyAfterCapture)
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
                    detail: "メニューを開いたままショートカットで撮るのに使います。",
                    isGranted: permission.accessibilityGranted,
                    request: { permission.requestAccessibility() }
                )
                PermissionRow(
                    title: "マイク",
                    detail: "録画の音にマイクの音を入れて、自分の声を録るときに使います。",
                    isGranted: permission.microphoneGranted,
                    request: { permission.requestMicrophone() }
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
            Section {
                LabeledContent("バージョン") {
                    HStack(spacing: 10) {
                        Text(AppSupport.versionText)
                        // 更新の機能を使えるビルドだけ（公開鍵の入っていないビルドでは、版だけを出す）
                        if updates.isAvailable {
                            Button("アップデートを確認…") { updates.check() }
                                .disabled(!updates.canCheck)
                                .hoverRole()
                        }
                    }
                }
                if updates.isAvailable {
                    Toggle(isOn: Binding(
                        get: { updates.checksAutomatically },
                        set: { updates.setChecksAutomatically($0) }
                    )) {
                        SettingTitle(
                            "新しい版を自動で確かめる",
                            info: "1 時間に 1 回、GitHub に新しい版がないかを確かめます。見つかると、メニューバーのアイコンの右下に下向きの矢印の印が付き、メニューの上に出る「新しいバージョン … があります…」から更新できます（画面には割り込みません）。印は、入れるか「このバージョンはスキップ」を選ぶまで残ります。オフにしても、メニューの「アップデートを確認…」でいつでも確かめられます。"
                        )
                    }
                }
                LabeledContent("使い方") {
                    Button("使い方を見る…") { WelcomeWindowController.shared.show() }
                        .hoverRole()
                }
            } header: {
                Text("Pinshot について")
            } footer: {
                if updates.isAvailable {
                    SettingsNote(Self.lastCheckNote(updates.lastCheckDate))
                } else {
                    SettingsNote("このビルドには、更新ファイルを確かめる鍵が入っていないので、アップデートの確認は使えません。")
                }
            }
        }
        // 最後に確かめた日時などを、開いたときに聞き直す
        .onAppear { updates.refresh() }
    }

    /// 最後に確かめた日時の説明
    private static func lastCheckNote(_ date: Date?) -> String {
        guard let date else { return "新しい版は、まだ確かめていません。" }
        return "新しい版を最後に確かめた日時：\(date.formatted(date: .abbreviated, time: .shortened))"
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
    @Published private(set) var isEnabled = LoginItemModel.isEnabledNow
    @Published private(set) var errorMessage: String?

    /// いま、ログイン時に起動するようになっているか（システム設定で変えられることもあるので、使うたびに macOS に聞く）
    static var isEnabledNow: Bool { SMAppService.mainApp.status == .enabled }

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
        isEnabled = Self.isEnabledNow
    }
}
