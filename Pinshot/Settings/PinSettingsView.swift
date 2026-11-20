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
                Picker("出し方", selection: $settings.closeButtonMode) {
                    ForEach(CloseButtonMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Toggle("画像の下に操作バーを出す", isOn: $settings.showsQuickActions)
                    .disabled(settings.closeButtonMode == .hidden)
                SettingsNote("不透明度・拡大率・コピー・保存・履歴・編集のバーです。オフにすると、ダブルクリックで編集するまで画像の下に何も出しません（編集モードのツールバーはいつも出ます）。画像の右クリックからも切り替えられます。")
            } header: {
                Text("閉じるボタンと操作バー")
            } footer: {
                SettingsNote("出さないときも、ダブルクリックか ⌘E で編集、右クリックでコピー・保存・閉じるなどができます。")
            }
            Section {
                Toggle("終了・再起動のあとも、浮かせていた画像を戻す", isOn: $settings.restorePins)
            } header: {
                Text("終了したとき")
            } footer: {
                SettingsNote("浮かせていた画像と閉じた画像（最大 10 枚）を、書き込み・位置・拡大率・不透明度・背景ごと、次に起動したときに戻します。画像はこの Mac の中（~/Library/Application Support/Pinshot/Pins）にだけ置きます。オフにすると、置いていたものを消します。")
            }
            Section("書き込み") {
                Toggle("書き込みに影を付ける（背景に埋もれにくくなる）", isOn: $settings.annotationShadow)
            }
        }
    }
}
