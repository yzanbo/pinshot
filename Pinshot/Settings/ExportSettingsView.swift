import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 保存（保存の仕方・保存先とその中の分け方）。
/// ここで決めるのは、利用者が「保存」したものの行き先。アプリが裏で残すもの（履歴・録画）は、設定の「履歴」で決める。
/// 浮かせた画像の背景は、ツールバーの背景のボタンで決める（「次の画像にも使う」で、これから浮かせる画像の初期設定にもなる）
struct ExportSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsPane {
            Section {
                OptionPicker("保存の仕方", selection: $settings.saveMode)
                LabeledContent(settings.saveMode == .folder ? "保存先" : "最初に開くフォルダ") {
                    folderMenu
                }
                Toggle("種類ごとにフォルダを分ける（画像・GIF・動画）", isOn: $settings.separatesSaveFoldersByKind)
                Toggle("月ごとにフォルダを分ける", isOn: $settings.separatesSaveFoldersByMonth)
                LabeledContent("保存される場所の例") {
                    VStack(alignment: .trailing, spacing: 2) {
                        ForEach(ExportKind.allCases) { kind in
                            Text(example(for: kind))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                    }
                }
            } header: {
                SettingTitle("保存", info: "「決めたフォルダにすぐ保存」のときは、保存先（分けるときは、その中のフォルダ。なければ作る）にすぐ書き出します。「毎回聞く」のときは、保存するたびに場所を聞き、最初は保存先を開きます。\n\n名前は「Pinshot 日付 時刻」、録画とその GIF は「Pinshot 録画 日付 時刻」の形で付くので、分けなくても種類が分かります。保存したものを Pinshot が削除することはありません。")
            }
        }
    }

    /// 保存先のポップアップメニュー（macOS で一般的な形。Safari の「ファイルの保存先」と同じ）。
    /// ボタンにはフォルダのアイコンと名前、押すと 今のフォルダ・Finder で表示・その他…（・初期設定に戻す）
    private var folderMenu: some View {
        let folder = settings.saveFolder
        let isDefault = folder.standardizedFileURL == AppSettings.defaultSaveFolder.standardizedFileURL
        return Menu {
            Button {
            } label: {
                Label(folder.lastPathComponent, systemImage: "checkmark")
            }
            .disabled(true)
            Divider()
            Button("Finder で表示") {
                // まだ保存していなくても開けるよう、なければ作る
                NSWorkspace.shared.open(settings.prepareSaveFolder())
            }
            Button("その他…") { chooseFolder() }
            if !isDefault {
                Divider()
                Button("初期設定に戻す（\(Self.displayPath(AppSettings.defaultSaveFolder))）") {
                    settings.saveFolder = AppSettings.defaultSaveFolder
                    settings.prepareSaveFolder()
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(nsImage: Self.folderIcon(folder))
                Text(folder.lastPathComponent)
                    .lineLimit(1)
            }
        }
        .fixedSize()
        .help(Self.displayPath(folder))
        .hoverRole()
    }

    /// フォルダのアイコン（Finder と同じもの。まだないときは、ふつうのフォルダのアイコン。小さく）
    private static func folderIcon(_ url: URL) -> NSImage {
        let icon = FileManager.default.fileExists(atPath: url.path)
            ? NSWorkspace.shared.icon(forFile: url.path)
            : NSWorkspace.shared.icon(for: .folder)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    /// ホームフォルダを「~」にしたパス
    private static func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    /// kind を保存したときの場所の例（いまの日時で）
    private func example(for kind: ExportKind) -> String {
        let name = kind == .image
            ? ImageExporter.defaultFileName()
            : RecordingRules.fileName(for: Date(), extension: kind.fileExtension)
        return Self.displayPath(settings.saveFolder(for: kind).appendingPathComponent(name))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.saveFolder
        panel.message = "保存したもの（画像・GIF・動画）を置くフォルダを選んでください"
        panel.prompt = "選ぶ"
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveFolder = url
        }
    }
}
