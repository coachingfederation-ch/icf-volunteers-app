import Foundation
import UIKit
import UserNotifications

/// Owns remote-notification registration and delivery, and pushes the APNs
/// token + tapped-payload into the web view via `PushBridge`.
final class PushHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushHandler()

    /// Latest APNs device token, forwarded to the web view when it changes.
    private(set) var deviceToken: Data? {
        didSet { PushBridge.shared.pushTokenDidChange(tokenString) }
    }

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    var tokenString: String? {
        guard let data = deviceToken else { return nil }
        return data.map { String(format: "%02x", $0) }.joined()
    }

    func registerForRemoteNotifications() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[APNs] authorization error: \(error.localizedDescription)")
                    return
                }
                print("[APNs] authorization granted: \(granted)")
                if granted {
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            }
        }
    }

    func deviceTokenDidChange(_ token: Data) {
        deviceToken = token
    }

    // MARK: - Foreground presentation (show banners while the app is open)

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }

    // MARK: - Tap on a notification → route the web view

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let payload = response.notification.request.content.userInfo
        PushBridge.shared.openPushPayload(payload)
        completionHandler()
    }

    /// Called from the AppDelegate for silent/background pushes.
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) {
        // If a "waiting chat" push arrives while backgrounded, reflect the
        // badge. The web view handles the real routing when opened.
        if let badge = (userInfo["aps"] as? [String: Any])?["badge"] as? Int {
            UNUserNotificationCenter.current().setBadgeCount(badge) { _ in }
        }
    }
}
