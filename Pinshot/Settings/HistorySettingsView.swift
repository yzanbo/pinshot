import AppKit
import SwiftUI

/// 履歴（撮った画像・読み取った文字のそれぞれを残すか・残す期間と数、いまの数と容量）
struct HistorySettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var history = CaptureHistory.shared
    @ObservedObject var texts = TextHistory.shared

    var body: some View {
        SettingsPane {
            // 撮った画像と読み取った文字は、残し方を別々に決める
            Section("撮った画像") {
                Toggle("撮った画像を履歴に残す", isOn: $settings.historyEnabled)
                OptionPicker("残す期間", selection: $settings.historyPeriod)
                    .disabled(!settings.historyEnabled)
                OptionPicker("残す数", selection: $settings.historyLimit)
                    .disabled(!settings.historyEnabled)
            }
            Section("読み取った文字") {
                Toggle("読み取った文字を履歴に残す", isOn: $settings.textHistoryEnabled)
                OptionPicker("残す期間", selection: $settings.textHistoryPeriod)
                    .disabled(!settings.textHistoryEnabled)
                OptionPicker("残す数", selection: $settings.textHistoryLimit)
                    .disabled(!settings.textHistoryEnabled)
            }
            Section("一覧") {
                layoutPicker("撮った画像の表示", selection: $settings.historyLayout)
                layoutPicker("読み取った文字の表示", selection: $settings.textHistoryLayout)
            }
            Section {
                LabeledContent("撮った画像") {
                    Text(history.summaryText)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("読み取った文字") {
                    Text(texts.summaryText)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button("画像の一覧…") { CaptureHistoryWindowController.shared.show(tab: .images) }
                        .hoverRole()
                    Button("文字の一覧…") { CaptureHistoryWindowController.shared.show(tab: .texts) }
                        .hoverRole()
                    Button {
                        NSWorkspace.shared.open(CaptureHistory.shared.folder)
                    } label: {
                        Label("Finder で開く", systemImage: "folder")
                    }
                    .hoverRole()
                    Spacer()
                    Menu("削除…") {
                        Button("撮った画像をすべて削除…") { CaptureHistoryWindowController.confirmRemoveAll() }
                            .disabled(history.entries.isEmpty)
                        Button("読み取った文字をすべて削除…") { CaptureHistoryWindowController.confirmRemoveAllTexts() }
                            .disabled(texts.entries.isEmpty)
                    }
                    .fixedSize()
                    .disabled(history.entries.isEmpty && texts.entries.isEmpty)
                    .hoverRole(history.entries.isEmpty && texts.entries.isEmpty ? .inactive : .pressable)
                }
            } header: {
                Text("いまの履歴")
            } footer: {
                SettingsNote("履歴は、この Mac の中（~/Library/Application Support/Pinshot/History）にだけ置きます。期間を過ぎたものと、数を超えた古いものは自動で削除されます。")
            }
        }
    }

    /// 一覧の表示方法を選ぶ
    private func layoutPicker<Layout: HistoryLayoutOption>(_ title: String, selection: Binding<Layout>) -> some View {
        Picker(title, selection: selection) {
            ForEach(Layout.allCases) { layout in
                Label(layout.label, systemImage: layout.symbolName).tag(layout)
            }
        }
    }
}
