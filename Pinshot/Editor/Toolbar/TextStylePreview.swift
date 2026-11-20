import AppKit
import SwiftUI

/// 文字ツールのオプションの先頭に出す見本。いまの設定（大きさ・フォント・縁取り・マーカー・色・不透明度）で、
/// 次に文字を入力したらどう見えるかを、書き込みと同じ描き方（AnnotationRenderer）で描く
struct TextStylePreview: View {
    let style: TextStyle
    let color: RGBAColor
    let fontSize: CGFloat

    /// 見本の文字（日本語と英数字の両方の見え方が分かるように）
    private static let sample = "見本 Aa"
    /// 見本の高さの上限（大きい文字は、縮めて収める）
    private static let maxHeight: CGFloat = 34

    var body: some View {
        Image(nsImage: Self.render(style: style, color: color, fontSize: fontSize))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 150, maxHeight: Self.maxHeight)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(checkerboard)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15)))
            .help("次に入力する文字の見え方（\(Int(fontSize)) pt）")
    }

    /// 白い文字も黒い文字も見えるよう、薄い市松模様を敷く
    private var checkerboard: some View {
        Canvas { context, size in
            let cell: CGFloat = 6
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.82)))
            for row in 0...Int(size.height / cell) {
                for column in 0...Int(size.width / cell) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)), with: .color(Color(white: 0.66)))
                }
            }
        }
    }

    /// 見本の画像（書き込みと同じ描き方。大きさは実際の文字の大きさで描き、表示で縮める）
    static func render(style: TextStyle, color: RGBAColor, fontSize: CGFloat) -> NSImage {
        let runs = [TextRun(text: sample, fontSize: fontSize)]
        let annotation = Annotation(shape: .text(runs: runs, origin: .zero, style: style, width: nil), color: color, lineWidth: 0)
        // 縁取り・マーカーのはみ出しも入るよう、書き込みの範囲に合わせる
        let bounds = annotation.bounds.insetBy(dx: -2, dy: -2).integral
        let size = NSSize(width: max(bounds.width, 1), height: max(bounds.height, 1))
        return NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
            AnnotationRenderer.draw(annotation, in: ctx, imageSize: size, effects: EffectImages(), shadow: AppSettings.shared.annotationShadow)
            return true
        }
    }
}
