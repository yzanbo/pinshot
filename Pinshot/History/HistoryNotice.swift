import SwiftUI

/// 履歴のウィンドウに出す、操作したあとの短い知らせ（「コピーしました」など。少したつと消える）
@MainActor
final class HistoryNotice: ObservableObject {
    @Published private(set) var text: String?
    private var task: Task<Void, Never>?

    func show(_ text: String) {
        self.text = text
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.text = nil
        }
    }
}

/// 知らせを、ウィンドウの下のほうに浮かべて出す
struct HistoryNoticeView: View {
    @ObservedObject var notice: HistoryNotice

    var body: some View {
        Group {
            if let text = notice.text {
                Label(text, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                    .padding(.bottom, 60)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.15), value: notice.text)
    }
}
