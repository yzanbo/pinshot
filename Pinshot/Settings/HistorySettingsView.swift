import AppKit
import SwiftUI

/// 履歴（アプリが裏で残すもの）。撮った画像・読み取った文字・録画の残し方（残すか・期間・数）と、いまの量・操作を、
/// 種類ごとに 2 行の同じ形で並べる（縦に長くなりすぎないように。設定のウィンドウの幅は変わらないので、ほかのタブと同じ幅に収める）
struct HistorySettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var history = CaptureHistory.shared
    @ObservedObject var texts = TextHistory.shared
    @ObservedObject var recordings = RecordingStore.shared

    var body: some View {
        SettingsPane {
            Section {
                kindRow(
                    "撮った画像",
                    symbol: "photo.on.rectangle",
                    keeps: $settings.historyEnabled,
                    period: $settings.historyPeriod,
                    limit: $settings.historyLimit,
                    amount: history.summaryText,
                    open: { CaptureHistoryWindowController.shared.show(tab: .images) },
                    folder: CaptureHistory.shared.folder,
                    canRemove: !history.entries.isEmpty,
                    removeAll: CaptureHistoryWindowController.confirmRemoveAll
                )
                kindRow(
                    "読み取った文字",
                    symbol: "text.viewfinder",
                    keeps: $settings.textHistoryEnabled,
                    period: $settings.textHistoryPeriod,
                    limit: $settings.textHistoryLimit,
                    amount: texts.summaryText,
                    open: { CaptureHistoryWindowController.shared.show(tab: .texts) },
                    folder: TextHistory.shared.folder,
                    canRemove: !texts.entries.isEmpty,
                    removeAll: CaptureHistoryWindowController.confirmRemoveAllTexts
                )
                // 録画は、止めたあとに浮かせて再生するため、いつも残す
                kindRow(
                    "録画",
                    symbol: "record.circle",
                    keeps: nil,
                    period: $settings.recordingPeriod,
                    limit: $settings.recordingLimit,
                    amount: recordings.summaryText,
                    open: nil,
                    folder: recordings.folder,
                    canRemove: recordings.count > 0,
                    removeAll: recordings.confirmRemoveAll
                )
            } header: {
                SettingTitle("残し方", info: "どれも、この Mac の中（~/Library/Application Support/Pinshot）にだけ置きます。期間を過ぎたもの・数を超えた古いものは自動で削除します（浮かせて再生している録画は残します）。\n\n手元に残したいものは「保存」してください。保存した画像・GIF・動画は削除されません。")
            }
            Section("一覧の表示") {
                layoutPicker("撮った画像", selection: $settings.historyLayout)
                layoutPicker("読み取った文字", selection: $settings.textHistoryLayout)
            }
        }
    }

    /// 1 種類ぶんの残し方（同じ形で 3 つ並べる）。
    /// 1 行目は 名前・いまの量・⋯・残す（スイッチ。録画は「いつも」）、2 行目は 残す期間・残す数
    private func kindRow<Period: SettingsOption, Limit: SettingsOption>(
        _ title: String,
        symbol: String,
        keeps: Binding<Bool>?,
        period: Binding<Period>,
        limit: Binding<Limit>,
        amount: String,
        open: (() -> Void)?,
        folder: URL,
        canRemove: Bool,
        removeAll: @escaping () -> Void
    ) -> some View {
        let enabled = keeps?.wrappedValue ?? true
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(title, systemImage: symbol)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(amount)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                actions(open: open, folder: folder, canRemove: canRemove, removeAll: removeAll)
                if let keeps {
                    Toggle("\(title)を残す", isOn: keeps)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .help(keeps.wrappedValue ? "残している（オフにすると、これから残さない。いまあるものは消えない）" : "残していない")
                } else {
                    Text("いつも残す")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("録画は、止めたあとに浮かせて再生するため、いつも残します")
                }
            }
            HStack(spacing: 8) {
                fieldTitle("残す期間")
                compactPicker(period)
                fieldTitle("残す数")
                    .padding(.leading, 8)
                compactPicker(limit)
                Spacer(minLength: 0)
            }
            .padding(.leading, 26)
            .disabled(!enabled)
        }
        .padding(.vertical, 2)
    }

    // MARK: - 部品

    private func fieldTitle(_ title: String) -> some View {
        Text(title)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    /// 小さな選択肢（名前は、前に置いた見出しで分かるので出さない）
    private func compactPicker<Option: SettingsOption>(_ selection: Binding<Option>) -> some View {
        Picker("", selection: selection) {
            ForEach(Array(Option.allCases)) { option in
                Text(option.label).tag(option)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    /// 行の操作（一覧を開く・Finder で開く・すべて削除）をまとめたメニュー
    private func actions(open: (() -> Void)?, folder: URL, canRemove: Bool, removeAll: @escaping () -> Void) -> some View {
        Menu {
            if let open {
                Button("一覧を開く…", action: open)
            }
            Button("Finder で開く") {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                NSWorkspace.shared.open(folder)
            }
            Divider()
            Button("すべて削除…", action: removeAll)
                .disabled(!canRemove)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("一覧を開く・Finder で開く・すべて削除")
        .hoverRole()
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
