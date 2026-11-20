import AppKit
import SwiftUI

/// ショートカット
struct ShortcutSettingsView: View {
    @ObservedObject var settings: AppSettings
    let recorder: ShortcutRecorderModel

    var body: some View {
        SettingsPane {
            Section {
                rows(for: ShortcutAction.captureActions)
            } header: {
                SettingTitle("キャプチャ", info: "ボタンを押してからキーを押すと割り当てられます（⌘・⌥・⌃ のどれかと一緒に）。どのアプリを使っていても効きます。")
            }
            Section("録画") {
                rows(for: ShortcutAction.recordActions)
            }
            Section("浮かせた画像") {
                rows(for: ShortcutAction.pinActions)
            }
            Section {
                rows(for: ShortcutAction.historyActions)
            } header: {
                Text("履歴")
            } footer: {
                HStack {
                    Spacer()
                    Button("初期設定に戻す") {
                        recorder.stop()
                        settings.resetShortcuts()
                    }
                    .controlSize(.small)
                    .hoverRole()
                }
            }
        }
    }

    private func rows(for actions: [ShortcutAction]) -> some View {
        ForEach(actions) { action in
            LabeledContent {
                ShortcutRecorder(settings: settings, model: recorder, action: action)
            } label: {
                Label(action.label, systemImage: action.symbolName)
            }
        }
    }
}

/// クリックしてからキーを押すと、そのキーをショートカットとして記録する
struct ShortcutRecorder: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: ShortcutRecorderModel
    let action: ShortcutAction

    private var isRecording: Bool { settings.recordingAction == action }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    model.toggle(action)
                } label: {
                    Text(isRecording ? "キーを押してください…" : (settings.shortcut(for: action)?.displayString ?? "なし"))
                        .foregroundStyle(settings.shortcut(for: action) == nil && !isRecording ? .secondary : .primary)
                        .frame(minWidth: 130)
                }
                .hoverRole()
                Button {
                    settings.setShortcut(nil, for: action)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("ショートカットを外す")
                .hoverRole(settings.shortcut(for: action) == nil ? .inactive : .pressable)
                .disabled(settings.shortcut(for: action) == nil)
                .opacity(settings.shortcut(for: action) == nil ? 0.3 : 1)
            }
            if let message = model.message, message.action == action {
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if settings.unavailableShortcuts.contains(action), !isRecording {
                // ほかのアプリが同じキーを使っていると、登録できない
                Label("ほかのアプリが使っているため、効きません", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onDisappear { model.stop() }
    }
}

/// ショートカットの記録（操作ごと）
@MainActor
final class ShortcutRecorderModel: ObservableObject {
    /// 記録の案内や、ほかの操作から外したことを知らせる文（どの操作の行に出すか）
    @Published private(set) var message: (action: ShortcutAction, text: String)?
    /// 設定のウィンドウ。記録するのは、このウィンドウで押したキーだけ（ほかのウィンドウのキーは横取りしない）
    weak var window: NSWindow?
    private let settings: AppSettings
    private var monitor: Any?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func toggle(_ action: ShortcutAction) {
        if settings.recordingAction == action {
            stop()
        } else {
            start(action)
        }
    }

    func start(_ action: ShortcutAction) {
        stop()
        settings.recordingAction = action
        message = (action, "esc でやめる")
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if let window = self.window, event.window !== window { return event }
            if event.keyCode == KeyCode.escape {
                self.stop()
                return nil
            }
            guard let shortcut = Shortcut(event: event) else {
                self.message = (action, "⌘・⌥・⌃ のどれかと一緒に押してください")
                return nil
            }
            let removed = self.settings.setShortcut(shortcut, for: action)
            self.stop()
            if let removed {
                self.message = (action, "「\(removed.label)」から外して、ここに割り当てました")
            }
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        message = nil
        settings.recordingAction = nil
    }
}
