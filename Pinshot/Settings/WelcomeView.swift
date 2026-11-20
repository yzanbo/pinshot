import AppKit
import SwiftUI

/// 初めて起動したときと、画面収録の許可がないときに出す案内
@MainActor
final class WelcomeWindowController: NSObject {
    static let shared = WelcomeWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingView(rootView: WelcomeView(
                settings: AppSettings.shared,
                permission: PermissionModel(),
                close: { [weak self] in self?.window?.close() }
            ))
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct WelcomeView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var permission: PermissionModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                // アプリのアイコン
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pinshot へようこそ")
                        .font(.title2.bold())
                    Text("撮った画面を、いつでも最前面に浮かべておけます。")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                StepRow(
                    symbol: "menubar.arrow.up.rectangle",
                    title: "メニューバーに常駐します",
                    detail: "画面右上のカメラのアイコンから、キャプチャや設定を開けます。"
                )
                StepRow(
                    symbol: "keyboard",
                    title: settings.shortcut(for: .captureRegion).map { "\($0.displayString) でキャプチャ" } ?? "メニューバーからキャプチャ",
                    detail: "範囲・ウィンドウ・画面全体を選べます。撮った画像は、その場所に浮かびます。"
                )
                StepRow(
                    symbol: "pencil.tip.crop.circle",
                    title: "ダブルクリックで書き込み",
                    detail: "矢印・四角・文字・モザイクを書き込めます。右クリックでコピーや保存、× で閉じます。"
                )
            }

            Divider()

            permissionSection

            HStack {
                Button("設定を開く…") {
                    SettingsWindowController.shared.show()
                }
                .hoverRole()
                Spacer()
                Button(permission.granted ? "はじめる" : "あとで") {
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .hoverRole()
            }
        }
        .padding(28)
        .frame(width: 460)
    }

    @ViewBuilder
    private var permissionSection: some View {
        if permission.granted {
            Label("画面収録は許可されています", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("画面収録の許可が必要です", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.headline)
                Text(permission.requested
                     ? "システム設定で Pinshot をオンにしたら、Pinshot を再起動してください。"
                     : "画面を撮るには、システム設定で「画面収録」を許可する必要があります。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("許可する…") {
                        permission.request()
                    }
                    .buttonStyle(.borderedProminent)
                    .hoverRole()
                    if permission.requested {
                        Button("Pinshot を再起動") {
                            AppRelauncher.relaunch()
                        }
                        .hoverRole()
                    }
                }
                Text("すでに許可しているのにこの画面が出るときは、システム設定の一覧で Pinshot を選んで「−」で消し、もう一度「許可する…」を押してから再起動してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct StepRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
