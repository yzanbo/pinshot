import AppKit
import SwiftUI

/// 書き出し（保存の仕方・背景）
struct ExportSettingsView: View {
    @ObservedObject var settings: AppSettings

    /// ホームフォルダを「~」にした、保存先のパス
    private var folderPath: String {
        (settings.saveFolder.path as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        SettingsPane {
            Section("保存") {
                Picker("保存の仕方", selection: $settings.saveMode) {
                    ForEach(SaveMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                LabeledContent(settings.saveMode == .folder ? "保存先のフォルダ" : "最初に開くフォルダ") {
                    HStack(spacing: 6) {
                        Text(folderPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(settings.saveFolder.path)
                        Button {
                            NSWorkspace.shared.open(settings.saveFolder)
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                        }
                        .buttonStyle(.borderless)
                        .help("Finder で開く")
                        Button("選ぶ…") { chooseFolder() }
                    }
                }
                SettingsNote("PNG で保存します。名前は「Pinshot 日付 時刻」の形で付きます。")
            }
            Section {
                Toggle("浮かせた画像に背景を付ける", isOn: $settings.exportDecoration.isEnabled)
                Picker("背景", selection: $settings.exportDecoration.background) {
                    ForEach(ExportBackground.allCases) { background in
                        Text(background.label).tag(background)
                    }
                }
                Picker("余白", selection: $settings.exportDecoration.padding) {
                    ForEach(ExportPadding.allCases) { padding in
                        Text(padding.label).tag(padding)
                    }
                }
                Picker("角の丸み", selection: $settings.exportDecoration.corner) {
                    ForEach(ExportCorner.allCases) { corner in
                        Text(corner.label).tag(corner)
                    }
                }
                Toggle("影を付ける", isOn: $settings.exportDecoration.shadow)
                LabeledContent("見本") {
                    ExportDecorationPreview(decoration: settings.exportDecoration)
                }
            } header: {
                Text("背景")
            } footer: {
                SettingsNote("背景を付けると、画面の上でも、コピー・保存した画像でも同じ見た目になります。画像ごとに、ツールバーの背景のボタンや右クリックの「背景を付ける」でも切り替えられます。")
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.saveFolder
        panel.prompt = "選ぶ"
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveFolder = url
        }
    }
}

/// 書き出しの背景の見本
private struct ExportDecorationPreview: View {
    let decoration: ExportDecoration

    var body: some View {
        let colors = decoration.background.colors.map { Color(nsColor: $0.nsColor) }
        let scale: CGFloat = 0.35
        ZStack {
            if colors.count >= 2 {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                colors.first ?? .white
            }
            RoundedRectangle(cornerRadius: decoration.corner.points * scale * 1.5)
                .fill(Color.white)
                .overlay(
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(Color.gray.opacity(0.5)).frame(width: 50, height: 5)
                        Capsule().fill(Color.gray.opacity(0.3)).frame(width: 70, height: 5)
                        Capsule().fill(Color.gray.opacity(0.3)).frame(width: 40, height: 5)
                    }
                )
                .shadow(color: .black.opacity(decoration.shadow ? 0.3 : 0), radius: 6, y: 3)
                .padding(decoration.padding.points * scale)
        }
        .frame(width: 160, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(decoration.isEnabled ? 1 : 0.45)
    }
}
