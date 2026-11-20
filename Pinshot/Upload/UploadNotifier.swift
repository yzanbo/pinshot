import AppKit
@preconcurrency import UserNotifications

/// 上げ終えたときの macOS の通知（設定の「上げ終えたら通知する」）。
/// 通知を押すと、共有リンクをブラウザで開く。通知を許可していなければ、何もしない（画像の上のお知らせだけになる）
@MainActor
final class UploadNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = UploadNotifier()

    private var center: UNUserNotificationCenter { .current() }
    /// 通知に付けるリンクの名前（裏から呼ばれる通知の受け口でも読む）
    private nonisolated static let linkKey = "link"

    /// 通知の許可を求める（まだ決めていなければ、macOS が確かめる画面を出す）
    func requestPermission() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 通知を出す（設定でオフ・許可がないときは出さない）
    func notify(title: String, body: String, link: URL? = nil) {
        guard AppSettings.shared.notifiesUploads else { return }
        center.delegate = self
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let link { content.userInfo = [Self.linkKey: link.absoluteString] }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        let center = center
        Task {
            switch await center.notificationSettings().authorizationStatus {
            case .authorized, .provisional:
                try? await center.add(request)
            case .notDetermined:
                // 初めて上げたときに許可を求め、許されたら出す
                if (try? await center.requestAuthorization(options: [.alert, .sound])) == true {
                    try? await center.add(request)
                }
            default:
                break
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Pinshot が前にあるときも、通知を出す
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    /// 通知を押したら、共有リンクをブラウザで開く
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let link = (response.notification.request.content.userInfo[Self.linkKey] as? String).flatMap(URL.init(string:))
        Task { @MainActor in
            if let link { NSWorkspace.shared.open(link) }
            completionHandler()
        }
    }
}
