import Foundation

extension BinaryFloatingPoint {
    /// 0〜1 の割合を「80%」の形にする（不透明度・拡大率の表示に使う。拡大率は 1 を超えてもよい）
    var percentText: String {
        "\(Int((Double(self) * 100).rounded()))%"
    }
}
