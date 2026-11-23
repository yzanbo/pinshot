import AppKit
import ApplicationServices
import AVFoundation
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

/// アクセシビリティ（メニューを開いている間のショートカットに使う）の許可
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

// MARK: - マイク

/// マイク（録画に声を入れるときに使う）の許可
@MainActor
enum MicrophonePermission {
    static var isGranted: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }

    /// まだ聞いていないか（聞いていなければ、「許可する…」で macOS の確かめるダイアログを出せる）
    static var isUndetermined: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined }

    /// 許可されているか。まだ聞いていなければ、macOS の確かめるダイアログを出して聞く
    static func requestIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// 許可を求める（まだ聞いていなければダイアログ、断ったことがあればシステム設定のマイクのページを開く）
    static func request(onChange: @escaping @MainActor () -> Void = {}) {
        guard isUndetermined else { return openSettings() }
        Task { @MainActor in
            _ = await requestIfNeeded()
            onChange()
        }
    }

    static func openSettings() {
        PrivacySettings.open("Privacy_Microphone")
    }
}

// MARK: - 設定・案内の画面に出す状態

/// 画面収録・アクセシビリティ・マイクの許可の状態（出している間だけ、1 秒ごとに確かめ直す）。
/// 設定と使い方の画面で同じものを使う（「許可する…」を押したかも、どちらの画面にも出すため）
@MainActor
final class PermissionModel: ObservableObject {
    static let shared = PermissionModel()

    /// 画面収録（画面を撮るのに必要）
    @Published private(set) var granted = ScreenPermission.isGranted
    @Published private(set) var requested = false
    /// アクセシビリティ（メニューを開いている間のショートカットに使う）
    @Published private(set) var accessibilityGranted = AccessibilityPermission.isGranted
    /// マイク（録画に声を入れるときに使う）
    @Published private(set) var microphoneGranted = MicrophonePermission.isGranted
    private var timer: AnyCancellable?
    /// 許可の状態を出している窓の数（0 になったら、確かめ直すのをやめる）
    private var watchers = 0

    private init() {}

    /// 許可の状態を出す窓を開いた（閉じたら stopWatching を呼ぶ）。出している間だけ、1 秒ごとに確かめ直す
    func startWatching() {
        watchers += 1
        refresh()
        guard timer == nil else { return }
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    /// 許可の状態を出す窓を閉じた
    func stopWatching() {
        watchers = max(0, watchers - 1)
        if watchers == 0 { timer = nil }
    }

    private func refresh() {
        // 変わったときだけ知らせる（毎秒、画面を描き直さないように）
        let screen = ScreenPermission.isGranted
        if granted != screen { granted = screen }
        let accessibility = AccessibilityPermission.isGranted
        if accessibilityGranted != accessibility { accessibilityGranted = accessibility }
        let microphone = MicrophonePermission.isGranted
        if microphoneGranted != microphone { microphoneGranted = microphone }
    }

    func request() {
        ScreenPermission.request()
        requested = true
    }

    func requestAccessibility() {
        AccessibilityPermission.request()
    }

    func requestMicrophone() {
        MicrophonePermission.request { [weak self] in self?.refresh() }
    }
}
