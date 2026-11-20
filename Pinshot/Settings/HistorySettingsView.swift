import AppKit
import SwiftUI

/// 撮った画像の履歴（残すか・残す期間と枚数・いまの枚数と容量）
struct HistorySettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var history = CaptureHistory.shared

    var body: some View {
        SettingsPane {
            Section("残し方") {
                Toggle("撮った画像を履歴に残す", isOn: $settings.historyEnabled)
                OptionPicker("残す期間", selection: $settings.historyPeriod)
                .disabled(!settings.historyEnabled)
                OptionPicker("残す枚数", selection: $settings.historyLimit)
                .disabled(!settings.historyEnabled)
            }
            Section("一覧") {
                Picker("表示", selection: $settings.historyLayout) {
                    ForEach(HistoryLayout.allCases) { layout in
                        Label(layout.label, systemImage: layout.symbolName).tag(layout)
                    }
                }
            }
            Section {
                LabeledContent("枚数と容量") {
                    Text(history.summaryText)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button("一覧を開く…") { CaptureHistoryWindowController.shared.show() }
                        .hoverRole()
                    Button {
                        NSWorkspace.shared.open(CaptureHistory.shared.folder)
                    } label: {
                        Label("Finder で開く", systemImage: "folder")
                    }
                    .hoverRole()
                    Spacer()
                    Button("すべて消す…") { CaptureHistoryWindowController.confirmRemoveAll() }
                        .disabled(history.entries.isEmpty)
                        .hoverRole(history.entries.isEmpty ? .inactive : .pressable)
                }
            } header: {
                Text("いまの履歴")
            } footer: {
                SettingsNote("履歴は、この Mac の中（~/Library/Application Support/Pinshot/History）にだけ置きます。期間を過ぎたものと、枚数を超えた古いものは自動で消えます。")
            }
        }
    }
}
