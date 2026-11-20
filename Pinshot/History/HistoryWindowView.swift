import SwiftUI

/// 履歴のウィンドウで見ているもの
enum HistoryTab: String, CaseIterable, Identifiable {
    /// 撮った画像
    case images
    /// 読み取った文字
    case texts
    /// 上げたもの（共有リンク）
    case uploads

    var id: String { rawValue }

    var label: String {
        switch self {
        case .images: "画像"
        case .texts: "文字"
        case .uploads: "共有"
        }
    }

    var symbolName: String {
        switch self {
        case .images: "photo.on.rectangle"
        case .texts: "text.viewfinder"
        case .uploads: "link"
        }
    }
}

/// 履歴のウィンドウで見ているもの（上の帯で切り替える）
@MainActor
final class HistoryWindowState: ObservableObject {
    @Published var tab: HistoryTab = .images
}

/// 履歴のウィンドウの中身。上の帯で「画像 / 文字 / 共有」を切り替える
struct HistoryWindowView: View {
    @ObservedObject var state: HistoryWindowState
    let notice: HistoryNotice
    @ObservedObject var imageModel: CaptureHistoryViewModel
    @ObservedObject var textModel: TextHistoryViewModel
    @ObservedObject var uploadModel: UploadHistoryViewModel
    @ObservedObject var images = CaptureHistory.shared
    @ObservedObject var texts = TextHistory.shared
    @ObservedObject var uploads = UploadHistory.shared
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            switch state.tab {
            case .images: CaptureHistoryView(history: images, model: imageModel)
            case .texts: TextHistoryView(history: texts, model: textModel)
            case .uploads: UploadHistoryView(history: uploads, model: uploadModel)
            }
        }
        .overlay(alignment: .bottom) { HistoryNoticeView(notice: notice) }
        .frame(minWidth: 460, minHeight: 340)
    }

    /// 上の帯（左に「画像 / 文字」。右に、画像なら表示方法、文字なら探す欄と表示方法）
    private var topBar: some View {
        HStack(spacing: 10) {
            Picker("履歴", selection: $state.tab) {
                ForEach(HistoryTab.allCases) { tab in
                    Label("\(tab.label)（\(count(of: tab))）", systemImage: tab.symbolName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .hoverRole()
            Spacer(minLength: 8)
            switch state.tab {
            case .images:
                if !images.entries.isEmpty { layoutPicker($settings.historyLayout) }
            case .texts:
                if !texts.entries.isEmpty {
                    TextField("文字を探す", text: $textModel.query)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                    layoutPicker($settings.textHistoryLayout)
                }
            case .uploads:
                if !uploads.entries.isEmpty { layoutPicker($settings.uploadHistoryLayout) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func count(of tab: HistoryTab) -> Int {
        switch tab {
        case .images: images.entries.count
        case .texts: texts.entries.count
        case .uploads: uploads.entries.count
        }
    }

    /// 一覧の表示方法の切り替え（画像・文字・共有）
    private func layoutPicker<Layout: HistoryLayoutOption>(_ selection: Binding<Layout>) -> some View {
        HStack(spacing: 8) {
            Text(selection.wrappedValue.label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Picker("表示", selection: selection) {
                ForEach(Layout.allCases) { layout in
                    Image(systemName: layout.symbolName)
                        .help(layout.label)
                        .tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .hoverRole()
        }
    }
}
