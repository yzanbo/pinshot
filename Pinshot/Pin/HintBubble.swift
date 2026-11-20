import AppKit
import SwiftUI

/// ボタンにマウスを乗せたときに出す、説明のポップアップ（出すのは HoverHints から）
@MainActor
final class HintBubble {
    private let panel: NSPanel
    private let label = NSTextField(wrappingLabelWithString: "")
    private let maxTextWidth: CGFloat = 340
    private let padding = NSSize(width: 10, height: 6)

    var isShown: Bool { panel.isVisible }

    init() {
        panel = OverlayPanel(contentRect: .zero, level: .popUpMenu, defer: true)
        panel.ignoresMouseEvents = true

        let background = NSView()
        background.wantsLayer = true
        background.layer?.cornerRadius = 7
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        label.font = .systemFont(ofSize: 11)
        label.textColor = .white
        label.maximumNumberOfLines = 3
        background.addSubview(label)
        panel.contentView = background
    }

    /// anchor（マウスの位置）の横あたりで、avoiding（ツールバー）の上に出す。上に入らなければ下。
    /// keepOut を渡すと、その四角（録画している範囲など）に重ならない側に出し、どちらも重なるときは出さない。出したら true
    @discardableResult
    func show(_ text: String, at anchor: NSPoint, avoiding avoid: NSRect, keepOut: NSRect? = nil) -> Bool {
        label.stringValue = text
        label.preferredMaxLayoutWidth = maxTextWidth
        let textSize = label.sizeThatFits(NSSize(width: maxTextWidth, height: 200))
        let size = NSSize(width: ceil(textSize.width) + padding.width * 2, height: ceil(textSize.height) + padding.height * 2)
        label.frame = NSRect(x: padding.width, y: padding.height, width: ceil(textSize.width), height: ceil(textSize.height))

        let screen = ScreenGeometry.screen(containing: anchor)
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        let x = ScreenGeometry.clampedX(anchor.x - size.width / 2, width: size.width, in: visible)
        let above = NSRect(origin: NSPoint(x: x, y: avoid.maxY + 6), size: size)
        let below = NSRect(origin: NSPoint(x: x, y: avoid.minY - size.height - 6), size: size)
        let frame: NSRect
        if let keepOut {
            // 画面に収まり、keepOut に重ならない側（上を先に見る）。どちらもだめなら出さない
            let fits = { (rect: NSRect) in rect.minY >= visible.minY && rect.maxY <= visible.maxY && !rect.intersects(keepOut) }
            guard let chosen = [above, below].first(where: fits) else {
                hide()
                return false
            }
            frame = chosen
        } else {
            frame = above.maxY > visible.maxY ? below : above
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        return true
    }

    func hide() {
        panel.orderOut(nil)
    }
}

/// 説明のポップアップを出す入口（いつも 1 つだけ出す）。初めは少し待ってから出し、出ている間はすぐ差し替える。
/// 浮かせた画像のバー・ツールバーは、Pinshot が前面にないときにも使うので、前面のときしか出ない .help の代わりにこれを使う。
/// クリックしたら隠す（押したあとに説明が残らないように）
@MainActor
final class HoverHints {
    static let shared = HoverHints()

    private let bubble = HintBubble()
    private var task: Task<Void, Never>?
    /// 出している（出そうとしている）説明
    private var current: String?
    /// 出さない間（つまみで画像やツールバーを動かしている間）。true にしたら、出している説明も消す
    var isSuppressed = false {
        didSet { if isSuppressed { hide() } }
    }
    private var clickMonitor: Any?

    private init() {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.hide()
            return event
        }
    }

    /// text を出す。avoiding は出す直前に聞く、重ねたくない窓の位置（その上に出し、上に入らなければ下）。nil なら出さない。
    /// keepOut も出す直前に聞く、決して重ねない四角（録画している範囲など。重ならずに出せなければ出さない）
    func show(_ text: String, avoiding: @escaping @MainActor () -> NSRect?, keepOut: (@MainActor () -> NSRect?)? = nil) {
        guard !isSuppressed else { return }
        task?.cancel()
        current = text
        if bubble.isShown {
            guard let rect = avoiding() else { return hide() }
            bubble.show(text, at: NSEvent.mouseLocation, avoiding: rect, keepOut: keepOut?())
            return
        }
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled, !self.isSuppressed, self.current == text, let rect = avoiding() else { return }
            self.bubble.show(text, at: NSEvent.mouseLocation, avoiding: rect, keepOut: keepOut?())
        }
    }

    /// text を出しているときだけ隠す（ほかのボタンに乗り移っていたら、そちらの説明は残す）
    func end(_ text: String?) {
        guard let text, current == text else { return }
        hide()
    }

    func hide() {
        task?.cancel()
        current = nil
        bubble.hide()
    }

    /// マウスの真下にある自分の窓（ボタンのあるバー・編集ツールバーなど）に重ならないよう、text を出す。
    /// 編集ツールバーの表示メニューの「ボタンに乗せたら説明を出す」をオフにしていたら出さない（すべてのバーで同じ）
    func showOverWindowUnderMouse(_ text: String, keepOut: (@MainActor () -> NSRect?)? = nil) {
        guard EditorState.savedShowsHints else { return }
        show(text, avoiding: {
            let number = NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
            return NSApp.window(withWindowNumber: number)?.frame
        }, keepOut: keepOut)
    }
}

extension View {
    /// マウスを乗せている間、説明のポップアップを出す（Pinshot が前面にないときも出る）。
    /// keepOut を渡すと、その四角に重ならない所にだけ出す（録画の操作パネルの説明を、録画に写さないため）
    func hoverHint(_ text: String, keepOut: (@MainActor () -> NSRect?)? = nil) -> some View {
        self
            .onHover { hovering in
                if hovering {
                    HoverHints.shared.showOverWindowUnderMouse(text, keepOut: keepOut)
                } else {
                    HoverHints.shared.end(text)
                }
            }
            .accessibilityHint(Text(text))
    }
}
