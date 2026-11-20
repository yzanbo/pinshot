import Combine

/// 浮かせた画像の見た目（操作バーのスライダーと、⌥ + スクロールなどで変えた値を同じにする）
@MainActor
final class PinAppearance: ObservableObject {
    @Published var opacity: Double
    /// 表示の拡大率（1 が実寸）
    @Published var zoom: Double

    init(opacity: Double, zoom: Double = 1) {
        self.opacity = opacity
        self.zoom = zoom
    }
}
