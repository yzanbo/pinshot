import AppKit
import SwiftUI

/// 右クリックのメニューに足す項目
struct EditableTextMenuItem {
    var title: String
    var symbol: String?
    var action: () -> Void
}

/// 直せる文字の欄（読み取った文字の吹き出し・文字の履歴の右の欄）。
/// SwiftUI の TextEditor は右クリックのメニューを差し替えられず、項目の多い標準のメニュー
/// （書き方の手伝い・読み上げ・縦書きなど）が出るので、NSTextView で作り、短いメニューにする
struct EditableText: NSViewRepresentable {
    @Binding var text: String
    /// 右クリックのメニューで、編集の項目の下に足す項目
    var extraMenuItems: [EditableTextMenuItem] = []

    /// 文字の見た目（高さを測るときも同じものを使う）
    static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    static let lineSpacing: CGFloat = 3
    private static let inset = NSSize(width: 2, height: 4)

    /// 折り返しを含めて、text を全部見せるのに要る高さ（width は欄の幅）
    static func fittingHeight(for text: String, width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        // 行の左右の余白（NSTextContainer の lineFragmentPadding の 5pt ずつ）も引く
        let usable = max(width - inset.width * 2 - 10, 20)
        let rect = ((text.isEmpty ? " " : text) as NSString).boundingRect(
            with: NSSize(width: usable, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph]
        )
        return ceil(rect.height) + inset.height * 2 + 2
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MenuTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = Self.font
        textView.textColor = .labelColor
        textView.textContainerInset = Self.inset
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        // 幅は欄に合わせて折り返し、縦は文字に合わせて伸ばす（はみ出したらスクロール）
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = Self.lineSpacing
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.paragraphStyle] = paragraph
        textView.string = text
        textView.delegate = context.coordinator
        textView.extraMenuItems = extraMenuItems

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MenuTextView else { return }
        context.coordinator.text = $text
        textView.extraMenuItems = extraMenuItems
        // 打っている途中（変換中）に置き換えると入力が壊れるので、違うときだけ入れ直す
        if textView.string != text, !textView.hasMarkedText() {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// 右クリックで、短い日本語のメニューを出す文字の欄
private final class MenuTextView: NSTextView {
    var extraMenuItems: [EditableTextMenuItem] = []
    /// いま開いているメニューに足した項目（開いている間に extraMenuItems が変わっても、押した項目の処理を呼ぶ）
    private var shownExtraItems: [EditableTextMenuItem] = []

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        // 標準の項目は、文字の欄に送る（選んでいなければ「切り取り」「コピー」は押せない。NSTextView が決める）
        menu.addItem(editItem("切り取り", action: #selector(cut(_:)), key: "x"))
        menu.addItem(editItem("コピー", action: #selector(copy(_:)), key: "c"))
        menu.addItem(editItem("ペースト", action: #selector(pasteAsPlainText(_:)), key: "v"))
        menu.addItem(editItem("すべてを選択", action: #selector(selectAll(_:)), key: "a"))
        shownExtraItems = extraMenuItems
        if !shownExtraItems.isEmpty {
            menu.addItem(.separator())
            for (index, extra) in shownExtraItems.enumerated() {
                let item = NSMenuItem(title: extra.title, action: #selector(performExtra(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                item.image = extra.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
                menu.addItem(item)
            }
        }
        return menu
    }

    private func editItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func performExtra(_ sender: NSMenuItem) {
        guard shownExtraItems.indices.contains(sender.tag) else { return }
        shownExtraItems[sender.tag].action()
    }
}

/// 直せる文字の欄の下に出す、いまの状態の 1 行。
/// 色は印だけに付け、文字は読みやすい色にする（色の付いた小さな文字は、半透明の吹き出しの上で読みにくい）
struct EditStatusLine: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(text)
                .foregroundStyle(.primary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
    }
}
