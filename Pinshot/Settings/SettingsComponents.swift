import SwiftUI

/// 設定のタブの共通の見た目
struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
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

/// 選択肢をすべて並べた Picker（名前は選択肢の label）
struct OptionPicker<Option: SettingsOption>: View where Option.AllCases: RandomAccessCollection {
    let title: String
    @Binding var selection: Option

    init(_ title: String, selection: Binding<Option>) {
        self.title = title
        _selection = selection
    }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(Option.allCases) { option in
                Text(option.label).tag(option)
            }
        }
    }
}
