import AppKit
import QuartzCore

/// 文字を読み取っている間と、読み取ったあとの見た目（画像の上に重ねる。クリックは下へ通す）。
/// - 読み取り中: 読む範囲をアクセントカラーの点線で囲み、外を少し暗くし、光の帯を上から下へ流す
/// - 読み取れたとき: 読み取った文字の場所を色付きの枠で光らせてから消す
/// - 見つからなかったとき: 枠を左右に揺らしてから消す
final class TextScanOverlay: NSView {
    private let dim = CAShapeLayer()
    private let border = CAShapeLayer()
    private let band = CAGradientLayer()
    private var region: NSRect = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    // クリックは下の画像に通す
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var accent: CGColor { NSColor.controlAccentColor.cgColor }

    /// 読み取りを始めた（region はこのビューの座標）
    func startScanning(in region: NSRect) {
        guard let root = layer else { return }
        self.region = region

        let outside = CGMutablePath()
        outside.addRect(bounds)
        outside.addRect(region)
        dim.path = outside
        dim.fillRule = .evenOdd
        dim.fillColor = NSColor.black.withAlphaComponent(0.25).cgColor
        root.addSublayer(dim)

        border.path = CGPath(roundedRect: region.insetBy(dx: 1, dy: 1), cornerWidth: 4, cornerHeight: 4, transform: nil)
        border.fillColor = nil
        border.strokeColor = accent
        border.lineWidth = 2
        border.lineDashPattern = [6, 4]
        root.addSublayer(border)
        // 点線を少しずつ流して、動いていることを分かりやすくする
        let marching = CABasicAnimation(keyPath: "lineDashPhase")
        marching.fromValue = 0
        marching.toValue = -20
        marching.duration = 0.6
        marching.repeatCount = .infinity
        border.add(marching, forKey: "marching")

        // 上から下へ流れる光の帯
        let bandHeight = min(36, max(12, region.height * 0.25))
        band.frame = NSRect(x: region.minX, y: region.minY, width: region.width, height: bandHeight)
        let clear = NSColor.controlAccentColor.withAlphaComponent(0).cgColor
        band.colors = [clear, NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor, clear]
        band.startPoint = CGPoint(x: 0.5, y: 0)
        band.endPoint = CGPoint(x: 0.5, y: 1)
        let mask = CAShapeLayer()
        mask.path = CGPath(rect: region, transform: nil)
        let bandHolder = CALayer()
        bandHolder.frame = bounds
        bandHolder.mask = mask
        bandHolder.addSublayer(band)
        bandHolder.name = "band"
        root.addSublayer(bandHolder)
        let sweep = CABasicAnimation(keyPath: "position.y")
        sweep.fromValue = region.minY - bandHeight / 2
        sweep.toValue = region.maxY + bandHeight / 2
        sweep.duration = max(0.7, min(1.4, region.height / 300))
        sweep.repeatCount = .infinity
        band.add(sweep, forKey: "sweep")
    }

    /// 読み取れた（boxes は読み取った文字の場所。このビューの座標）。光らせたあと消え、onDone を呼ぶ
    func finish(found boxes: [NSRect], onDone: @escaping () -> Void) {
        stopScanning()
        guard let root = layer else { return onDone() }
        border.lineDashPattern = nil
        let highlight = CAShapeLayer()
        let path = CGMutablePath()
        for box in boxes {
            path.addRoundedRect(in: box.insetBy(dx: -2, dy: -1), cornerWidth: 3, cornerHeight: 3)
        }
        highlight.path = path
        highlight.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
        highlight.strokeColor = accent
        highlight.lineWidth = 1.5
        root.addSublayer(highlight)
        let pop = CAKeyframeAnimation(keyPath: "opacity")
        pop.values = [0, 1, 1]
        pop.keyTimes = [0, 0.2, 1]
        pop.duration = 0.25
        highlight.add(pop, forKey: "pop")
        fadeOut(after: 0.9, onDone: onDone)
    }

    /// 文字が見つからなかった。枠を揺らしたあと消え、onDone を呼ぶ
    func finishNotFound(onDone: @escaping () -> Void) {
        stopScanning()
        border.lineDashPattern = nil
        border.strokeColor = NSColor.systemOrange.cgColor
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -6, 6, -4, 4, 0]
        shake.duration = 0.35
        border.add(shake, forKey: "shake")
        fadeOut(after: 0.5, onDone: onDone)
    }

    private func stopScanning() {
        border.removeAnimation(forKey: "marching")
        layer?.sublayers?.first { $0.name == "band" }?.removeFromSuperlayer()
    }

    private func fadeOut(after delay: TimeInterval, onDone: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                self?.animator().alphaValue = 0
            }, completionHandler: onDone)
        }
    }
}
