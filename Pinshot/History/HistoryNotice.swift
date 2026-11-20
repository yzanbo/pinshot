import SwiftUI

/// 履歴のウィンドウに出す、操作したあとの短い知らせ（「コピーしました」など。少したつと消える）
@MainActor
final class HistoryNotice: ObservableObject {
    @Published private(set) var text: String?
    /// 途中の知らせか（アップロードの途中など。印をくるくる回し、次の知らせまで消さない）
    @Published private(set) var isWorking = false
    private var task: Task<Void, Never>?

    /// working なら、次の知らせを出すまで消さない
    func show(_ text: String, working: Bool = false) {
        self.text = text
        isWorking = working
        task?.cancel()
        guard !working else { return }
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
                Label {
                    Text(text)
                } icon: {
                    if notice.isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                }
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
