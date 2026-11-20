import SwiftUI

/// 設定のタブの共通の見た目
struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        // 設定のウィンドウは、タブを切り替えても横幅が変わらないので、どのタブも同じ幅にする
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 説明の小さな文字（項目の下に添える）
struct SettingsNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 設定の選択肢（名前を持ち、すべての値を並べられる）
protocol SettingsOption: CaseIterable, Identifiable, Hashable {
    var label: String { get }
}

extension AppearanceMode: SettingsOption {}
extension CloseButtonMode: SettingsOption {}
extension SaveMode: SettingsOption {}
extension ExportBackground: SettingsOption {}
extension ExportPadding: SettingsOption {}
extension ExportCorner: SettingsOption {}
extension HistoryPeriod: SettingsOption {}
extension HistoryLimit: SettingsOption {}
extension RecordingLimit: SettingsOption {}

/// 選択肢をすべて並べた Picker（名前は選択肢の label）
struct OptionPicker<Option: SettingsOption>: View where Option.AllCases: RandomAccessCollection {
    let title: String
    /// 項目名の横の ⓘ で出す説明（nil なら出さない）
    let info: String?
    @Binding var selection: Option

    init(_ title: String, info: String? = nil, selection: Binding<Option>) {
        self.title = title
        self.info = info
        _selection = selection
    }

    var body: some View {
        Picker(selection: $selection) {
            ForEach(Option.allCases) { option in
                Text(option.label).tag(option)
            }
        } label: {
            SettingTitle(title, info: info)
        }
    }
}

/// 項目名と、その横の ⓘ（押すと説明が出る）。説明の文を項目の下に並べず、設定の画面を短く保つ
struct SettingTitle: View {
    let title: String
    let info: String?

    init(_ title: String, info: String? = nil) {
        self.title = title
        self.info = info
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            if let info {
                InfoButton(info)
            }
        }
    }
}

/// 押すと、説明を吹き出しで出す ⓘ のボタン
struct InfoButton: View {
    let text: String
    @StateObject private var popover = InfoPopoverState()

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Button {
            popover.isShown.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("説明を見る")
        .hoverRole()
        .popover(isPresented: $popover.isShown, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 300, alignment: .leading)
                .padding(14)
        }
    }
}

/// ⓘ の説明を出しているか
@MainActor
final class InfoPopoverState: ObservableObject {
    @Published var isShown = false
}
