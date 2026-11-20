import AppKit
import ApplicationServices
import Combine
import ScreenCaptureKit

// MARK: - 画面収録

/// 画面収録（画面を撮るのに必要）の許可
@MainActor
enum ScreenPermission {
    /// 実際に画面の一覧を取れたことがあれば true（CGPreflight が古い答えを返すことがあるため）
    static var confirmed = false

    static var isGranted: Bool {
        confirmed || CGPreflightScreenCaptureAccess()
    }

    /// 許可がないために失敗したエラーかどうか
    static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain, nsError.code == SCStreamError.Code.userDeclined.rawValue {
            return true
        }
        return !CGPreflightScreenCaptureAccess()
    }

    /// 許可を求め、システム設定の画面収録のページを開く
    static func request() {
        CGRequestScreenCaptureAccess()
        openSettings()
    }

    static func openSettings() {
        PrivacySettings.open("Privacy_ScreenCapture")
    }
}

/// システム設定の「プライバシーとセキュリティ」のページ
@MainActor
enum PrivacySettings {
    /// pane（Privacy_ScreenCapture・Privacy_Accessibility など）のページを開く
    static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - アクセシビリティ

/// アクセシビリティ（スクロールキャプチャの自動スクロールと、メニューを開いている間のショートカットに使う）の許可
@MainActor
enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// 許可を求めるダイアログを出し、システム設定のページを開く
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        PrivacySettings.open("Privacy_Accessibility")
    }
}

// MARK: - 設定・案内の画面に出す状態

/// 画面収録・アクセシビリティの許可の状態（1 秒ごとに確かめ直す）
@MainActor
final class PermissionModel: ObservableObject {
    /// 画面収録（画面を撮るのに必要）
    @Published private(set) var granted = ScreenPermission.isGranted
    @Published private(set) var requested = false
    /// アクセシビリティ（スクロールキャプチャの自動スクロールと、メニューを開いている間のショートカットに使う）
    @Published private(set) var accessibilityGranted = AccessibilityPermission.isGranted
    private var timer: AnyCancellable?

    init() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        // 変わったときだけ知らせる（毎秒、画面を描き直さないように）
        let screen = ScreenPermission.isGranted
        if granted != screen { granted = screen }
        let accessibility = AccessibilityPermission.isGranted
        if accessibilityGranted != accessibility { accessibilityGranted = accessibility }
    }

    func request() {
        ScreenPermission.request()
        requested = true
    }

    func requestAccessibility() {
        AccessibilityPermission.request()
    }
}
