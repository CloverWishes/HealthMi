import Foundation
import UserNotifications

/// 本地通知管理：后台同步失败时通知用户。
enum NotificationManager {
    static let requestIdentifier = "sync-failed"

    /// 请求通知授权。
    static func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            // 授权失败时静默跳过，不影响主功能
        }
    }

    /// 检查是否已授权。
    static func isAuthorized() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus == .authorized)
            }
        }
    }

    /// 发送同步失败本地通知。
    static func notifySyncFailure(_ errorDescription: String) async {
        guard await isAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = "HealthMi 同步失败"
        content.body = "同步出错：\(errorDescription)，请打开 App 查看"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: requestIdentifier, content: content, trigger: trigger
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // 通知发送失败不影响主功能
        }
    }
}
