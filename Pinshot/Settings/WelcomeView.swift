import AppKit
import SwiftUI

/// 初めて起動したとき・メニューの「使い方と許可…」・画面収録の許可がないときに出す案内
@MainActor
final class WelcomeWindowController: NSObject {
    static let shared = WelcomeWindowController()

    private var window: NSWindow?
    private var hosting: NSHostingView<WelcomeView>?
    private let permission = PermissionModel()

    /// firstLaunch: 初めての起動のとき（見出しを「ようこそ」にする）
    func show(firstLaunch: Bool = false) {
        let view = WelcomeView(
            settings: AppSettings.shared,
            permission: permission,
            isFirstLaunch: firstLaunch,
            close: { [weak self] in self?.window?.close() }
        )
        if let hosting {
            hosting.rootView = view
        } else {
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "使い方と許可"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
            self.hosting = hosting
        }
        if let window, let hosting {
            window.setContentSize(hosting.fittingSize)
        }
        if let window { DockIcon.show(for: window) }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct WelcomeView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var permission: PermissionModel
    let isFirstLaunch: Bool
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            permissions
            usage
            footer
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 22)
        .frame(width: 540)
    }

    // MARK: - 見出し

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: AppSupport.appIcon ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(isFirstLaunch ? "Pinshot へようこそ" : "Pinshot の使い方と許可")
                    .font(.title2.bold())
                Text("撮った画面を、いつでも最前面に浮かべておけるメニューバーのアプリです。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 許可

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("許可", trailing: permission.granted ? "準備ができています" : "画面収録の許可が必要です")
            PermissionCard(
                symbol: "rectangle.dashed.badge.record",
                title: "画面収録",
                badge: permission.granted ? .granted : .required,
                detail: "画面を撮るのに必要です。撮った画像は Mac の中に置きます。ネットに送るのは、共有リンク（設定の「共有」）で上げたときだけです。",
                actionTitle: permission.granted ? nil : "許可する…",
                action: { permission.request() }
            ) {
                if !permission.granted, permission.requested {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("システム設定で Pinshot をオンにしたら、Pinshot を再起動してください。")
                            .font(.callout)
                        HStack(spacing: 8) {
                            Button("Pinshot を再起動") { AppRelauncher.relaunch() }
                                .buttonStyle(.borderedProminent)
                                .hoverRole()
                            Button("システム設定を開く") { ScreenPermission.openSettings() }
                                .hoverRole()
                        }
                        DisclosureGroup("許可しているのに撮れないとき") {
                            Text("システム設定の画面収録の一覧で Pinshot を選んで「−」で削除し、もう一度「許可する…」を押してから再起動してください。新しい版に入れ替えたときも、取り直しが必要です。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                        }
                        .font(.caption)
                    }
                }
            }
            PermissionCard(
                symbol: "hand.raised",
                title: "アクセシビリティ",
                badge: permission.accessibilityGranted ? .granted : .optional,
                detail: "なくても使えます。許可すると、メニューを開いたままでもショートカットで撮れるようになります。",
                actionTitle: permission.accessibilityGranted ? nil : "許可する…",
                action: { permission.requestAccessibility() }
            ) {
                EmptyView()
            }
        }
    }

    // MARK: - 使い方

    private var usage: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("使い方", trailing: nil)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .top), GridItem(.flexible(), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                UsageTile(
                    symbol: "camera.viewfinder",
                    title: settings.shortcut(for: .captureRegion).map { "\($0.displayString) で撮る" } ?? "メニューバーから撮る",
                    detail: "範囲・ウィンドウ・画面全体。撮った画像はその場に浮かびます。"
                )
                UsageTile(
                    symbol: "pin",
                    title: "浮かべて見比べる",
                    detail: "ドラッグで動かす・スクロールで拡大縮小・⌘ + スクロールで不透明度。"
                )
                UsageTile(
                    symbol: "pencil.tip.crop.circle",
                    title: "書き込む",
                    detail: "ダブルクリックか「編集」で、矢印・文字・番号・モザイクなどを書き込めます。"
                )
                UsageTile(
                    symbol: "clock.arrow.circlepath",
                    title: "あとから見返す",
                    detail: "撮った画像は履歴に残ります。メニューバーやツールバーから開けます。"
                )
            }
            Text("画像の下のバーでコピー・保存、左上の外の × で閉じられます。閉じた画像は「閉じた画像を戻す」で戻せます。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 下の帯

    private var footer: some View {
        HStack(spacing: 12) {
            Button("設定を開く…") { SettingsWindowController.shared.show() }
                .hoverRole()
            Spacer()
            Button(permission.granted ? "はじめる" : "あとで") { close() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .hoverRole()
        }
    }

    private func sectionTitle(_ title: String, trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 許可 1 つぶんのカード（状態の印・説明・許可のボタン・必要なら続きの案内）
private struct PermissionCard<Extra: View>: View {
    enum Badge {
        case granted, required, optional

        var text: String {
            switch self {
            case .granted: "許可済み"
            case .required: "必要"
            case .optional: "任意"
            }
        }

        var color: Color {
            switch self {
            case .granted: .green
            case .required: .orange
            case .optional: .secondary
            }
        }

        var symbol: String {
            switch self {
            case .granted: "checkmark.circle.fill"
            case .required: "exclamationmark.circle.fill"
            case .optional: "circle.dashed"
            }
        }
    }

    let symbol: String
    let title: String
    let badge: Badge
    let detail: String
    let actionTitle: String?
    let action: () -> Void
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(.tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline)
                        Label(badge.text, systemImage: badge.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(badge.color)
                    }
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let actionTitle {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .tint(badge == .required ? .accentColor : .gray)
                        .hoverRole()
                }
            }
            extra
                .padding(.leading, 38)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(badge == .required ? Color.orange.opacity(0.5) : Color.primary.opacity(0.08))
        )
    }
}

/// 使い方の 1 項目
private struct UsageTile: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
