import SwiftUI

/// 浮かせた画像
struct PinSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsPane {
            Section("表示") {
                Toggle("常に最前面に表示する", isOn: $settings.alwaysOnTop)
                LabeledContent("浮かせたときの不透明度") {
                    HStack {
                        Slider(value: $settings.defaultOpacity, in: 0.2...1, step: 0.1)
                            .frame(width: 160)
                        Text("\(Int((settings.defaultOpacity * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                SettingsNote("どちらも、画像ごとに右クリックのメニューから変えられます。")
            }
            Section {
                Picker("操作バーと捨てるボタン", selection: $settings.closeButtonMode) {
                    ForEach(CloseButtonMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Toggle("操作バー（不透明度・コピー・保存・編集・捨てる）を出す", isOn: $settings.showsQuickActions)
                    .disabled(settings.closeButtonMode == .hidden)
            } header: {
                Text("画像の上のボタン")
            } footer: {
                SettingsNote("出さないときも、ダブルクリックか ⌘E で編集、右クリックでコピー・保存・閉じるなどができます。")
            }
            Section("書き込み") {
                Toggle("書き込みに影を付ける（背景に埋もれにくくなる）", isOn: $settings.annotationShadow)
            }
        }
    }
}
