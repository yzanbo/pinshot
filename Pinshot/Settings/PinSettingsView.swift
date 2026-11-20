import SwiftUI

/// 浮かせた画像
struct PinSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsPane {
            Section {
                Toggle("常に最前面に表示する", isOn: $settings.alwaysOnTop)
                LabeledContent("浮かせたときの不透明度") {
                    HStack {
                        Slider(value: $settings.defaultOpacity, in: 0.2...1, step: 0.1)
                            .frame(width: 160)
                        Text(settings.defaultOpacity.percentText)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                SettingTitle("表示", info: "どちらも、画像ごとに右クリックのメニューから変えられます。")
            }
            Section {
                OptionPicker("出し方", selection: $settings.closeButtonMode)
                Toggle(isOn: $settings.showsQuickActions) {
                    SettingTitle("画像の下に操作バーを出す", info: "不透明度・拡大率・コピー・保存・履歴・編集のバーです。オフにすると、ダブルクリックで編集するまで画像の下に何も出しません（編集モードのツールバーはいつも出ます）。画像の右クリックからも切り替えられます。\n\n出さないときも、ダブルクリックか ⌘E で編集、右クリックでコピー・保存・閉じるなどができます。")
                }
                .disabled(settings.closeButtonMode == .hidden)
            } header: {
                Text("閉じるボタンと操作バー")
            }
            Section("そのほか") {
                Toggle(isOn: $settings.restorePins) {
                    SettingTitle("終了・再起動のあとも、浮かせていた画像を戻す", info: "浮かせていた画像と閉じた画像（最大 10 枚）を、書き込み・位置・拡大率・不透明度・背景ごと、次に起動したときに戻します。画像はこの Mac の中（~/Library/Application Support/Pinshot/Pins）にだけ置きます。オフにすると、置いていたものを削除します。")
                }
                Toggle(isOn: $settings.textPopoverClosesOnOutsideClick) {
                    SettingTitle("読み取った文字の吹き出しを、外を押したら閉じる", info: "オフ（初期設定）のときは、吹き出しの「閉じる」か esc で閉じるまで出したままにします。ほかの所を押しても閉じないので、見比べながら直せます。")
                }
                Toggle(isOn: $settings.annotationShadow) {
                    SettingTitle("書き込みに影を付ける", info: "矢印や文字などの書き込みに薄い影を付けて、背景に埋もれにくくします。蛍光ペン・モザイク・ぼかし・スポットライトには付けません。")
                }
            }
        }
    }
}
