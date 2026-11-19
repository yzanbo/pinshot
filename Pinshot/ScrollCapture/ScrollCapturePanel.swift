import AppKit
import SwiftUI

/// 操作パネルに出す状態
@MainActor
final class ScrollCaptureModel: ObservableObject {
    @Published var preview: NSImage?
    @Published var heightPoints = 0
    @Published var message = "準備しています…"
    @Published var warning: String?
    @Published var isTrusted = AccessibilityPermission.isGranted
    /// 自動でスクロールするか（オフにすると、自分でスクロールして撮る）
    @Published var autoScroll = true

    var finish: () -> Void = {}
    var cancel: () -> Void = {}
}

/// 撮っている範囲の外側に描く点線の枠
final class ScrollBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        path.lineWidth = 3
        path.setLineDash([8, 5], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}

/// スクロールキャプチャ中の操作パネル
struct ScrollCapturePanelView: View {
    @ObservedObject var model: ScrollCaptureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "arrow.down.doc")
                    .foregroundStyle(.tint)
                Text("スクロールキャプチャ")
                    .font(.headline)
                Spacer()
                Text("\(model.heightPoints) pt")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                // つないだ画像の下の方（いま足したところ）が見えるように
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.08)
                    if let preview = model.preview {
                        Image(nsImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 80)
                    }
                }
                .frame(width: 80, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))

                VStack(alignment: .leading, spacing: 8) {
                    Text(model.message)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    if let warning = model.warning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.isTrusted {
                        Toggle("自動でスクロールする", isOn: $model.autoScroll)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .hoverCursor()
                    } else {
                        Text("自動でスクロールするには「アクセシビリティ」の許可が必要です。許可するまでは、自分でスクロールすると撮れます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("アクセシビリティを許可…") {
                            AccessibilityPermission.request()
                        }
                        .controlSize(.small)
                        .hoverCursor()
                    }
                }
            }

            HStack {
                Text("esc でも完了できます")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("キャンセル") { model.cancel() }
                    .hoverCursor()
                Button("完了") { model.finish() }
                    .buttonStyle(.borderedProminent)
                    .hoverCursor()
            }
        }
        .padding(14)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
    }
}
