import AppKit
import SwiftUI

/// 設定のウィンドウ。macOS の設定画面と同じく、上のタブで項目を分ける
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let settings = AppSettings.shared
            let tabs = SettingsTabViewController()
            tabs.tabStyle = .toolbar
            tabs.addTabViewItem(makeTab("一般", symbol: "gearshape", view: GeneralSettingsView(
                settings: settings,
                loginItem: LoginItemModel(),
                permission: PermissionModel()
            )))
            tabs.addTabViewItem(makeTab("画像", symbol: "photo.on.rectangle", view: PinSettingsView(settings: settings)))
            tabs.addTabViewItem(makeTab("書き出し", symbol: "square.and.arrow.up", view: ExportSettingsView(settings: settings)))
            tabs.addTabViewItem(makeTab("ショートカット", symbol: "keyboard", view: ShortcutSettingsView(
                settings: settings,
                recorder: ShortcutRecorderModel(settings: settings)
            )))

            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            // 最初のタブの名前を、ウィンドウの名前にする（何もしないと「Untitled」になる）
            window.title = tabs.tabViewItems.first?.label ?? "設定"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeTab<Content: View>(_ label: String, symbol: String, view: Content) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view)
        controller.title = label
        // タブごとの中身の大きさに合わせて、ウィンドウの大きさを変える
        controller.sizingOptions = [.preferredContentSize]
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }

    func windowWillClose(_ notification: Notification) {
        // 記録の途中で閉じたら、記録をやめる
        AppSettings.shared.recordingAction = nil
    }
}

/// 設定のタブ。選んだタブの名前を、ウィンドウの名前にする（macOS の設定画面と同じ）
private final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let label = tabViewItem?.label {
            view.window?.title = label
        }
    }
}
