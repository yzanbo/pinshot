import Foundation
import os

extension Logger {
    /// Pinshot の記録（Console や make update-test-log では、subsystem「dev.portfolio.pinshot」で探す）
    ///
    /// subsystem は、更新の試験用アプリ（ID が違う）でも同じにしておく（記録を同じ条件で探せるように）。
    init(pinshot category: String) {
        self.init(subsystem: "dev.portfolio.pinshot", category: category)
    }
}

extension Bundle {
    /// 版（CFBundleShortVersionString。例: 0.5.0）
    var shortVersion: String? {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// ビルド番号（CFBundleVersion。Sparkle は、これで新旧を比べる）
    var buildNumber: String? {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
}
